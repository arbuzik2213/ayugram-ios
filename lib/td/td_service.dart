import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'dart:ui' show instantiateImageCodec;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ayu/ayu_settings.dart';
import '../ayu/message_store.dart';
import 'td_client.dart';

/// Состояние клиента Telegram + перехват запросов по правилам AyuGram
/// (режим призрака, сохранение удалённых и отредактированных сообщений).
class TdService extends ChangeNotifier {
  TdService._();
  static final TdService instance = TdService._();

  final td = TdClient.instance;
  final _settings = AyuSettings.instance;
  final _store = MessageStore.instance;

  TdObject? authState;
  int? myId;

  final chats = <int, TdObject>{};
  final users = <int, TdObject>{};
  final supergroups = <int, TdObject>{};
  final basicGroups = <int, TdObject>{};
  List<TdObject> chatFolders = [];

  /// Непрочитанные сообщения в основном списке (бейдж на вкладке «Чаты»).
  int unreadMessages = 0;

  /// connectionStateReady / Connecting / Updating / WaitingForNetwork.
  String connectionState = 'connectionStateReady';

  // --- Несколько аккаунтов: у каждого своя папка базы TDLib ---
  late SharedPreferences _prefs;
  List<int> accounts = [0];
  int currentAccount = 0;
  int? _switchTo;
  int? _removeOnClose;
  int? _returnTo;

  /// Сохранённые имя/телефон аккаунтов (чтобы показывать неактивные).
  Map<int, Map<String, dynamic>> accountInfo = {};
  final blockedUsers = <int>{};
  final _files = <int, ValueNotifier<TdObject>>{};

  /// Обновления, касающиеся сообщений (уже обработанные AyuGram).
  final _chatEvents = StreamController<TdObject>.broadcast();
  Stream<TdObject> chatEvents(int chatId) => _chatEvents.stream.where((u) => u['chat_id'] == chatId);

  /// Сигнал «список чатов поменялся».
  final chatListVersion = ValueNotifier<int>(0);

  Future<void> _queue = Future.value();
  bool _appActive = true;
  DateTime _suppressStatusUntil = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> start() async {
    _prefs = await SharedPreferences.getInstance();
    accounts = (_prefs.getStringList('accounts') ?? ['0']).map(int.parse).toList();
    currentAccount = _prefs.getInt('current_account') ?? accounts.first;
    if (!accounts.contains(currentAccount)) currentAccount = accounts.first;
    final info = _prefs.getString('account_info');
    if (info != null) {
      accountInfo = (jsonDecode(info) as Map<String, dynamic>)
          .map((k, v) => MapEntry(int.parse(k), Map<String, dynamic>.from(v as Map)));
    }
    _settings.addListener(_applyOnline);
    td.updates.listen((u) {
      // Порядок обработки важен (правка → удаление), поэтому обновления идут по очереди.
      _queue = _queue.then((_) => _handle(u)).catchError((e) => debugPrint('update error: $e'));
    });
    await td.start();
  }

  // ---------------------------------------------------------------------------
  // Обработка обновлений
  // ---------------------------------------------------------------------------

  Future<void> _handle(TdObject u) async {
    switch (u['@type']) {
      case 'updateAuthorizationState':
        await _onAuthState(u['authorization_state'] as TdObject);
      case 'updateOption':
        if (u['name'] == 'my_id') {
          // int64 в JSON TDLib приходит строкой.
          myId = int.tryParse('${(u['value'] as TdObject)['value']}');
        }
      case 'updateUser':
        final user = u['user'] as TdObject;
        users[user['id'] as int] = user;
      case 'updateSupergroup':
        final sg = u['supergroup'] as TdObject;
        supergroups[sg['id'] as int] = sg;
        _bumpChats();
      case 'updateUnreadMessageCount':
        if ((u['chat_list'] as TdObject?)?['@type'] == 'chatListMain') {
          unreadMessages = u['unread_count'] as int? ?? 0;
          _bumpChats();
        }
      case 'updateConnectionState':
        connectionState = (u['state'] as TdObject)['@type'] as String;
        _bumpChats();
      case 'updateChatFolders':
        chatFolders = (u['chat_folders'] as List? ?? []).cast<TdObject>();
        _bumpChats();
      case 'updateBasicGroup':
        final bg = u['basic_group'] as TdObject;
        basicGroups[bg['id'] as int] = bg;
      case 'updateUserStatus':
        final uid = u['user_id'] as int;
        users[uid]?['status'] = u['status'];
        if (uid == myId && (u['status'] as TdObject)['@type'] == 'userStatusOnline') {
          _onSelfOnline();
        }
      case 'updateUserFullInfo':
        final info = u['user_full_info'] as TdObject;
        final uid = u['user_id'] as int;
        if (info['block_list'] != null) {
          blockedUsers.add(uid);
        } else {
          blockedUsers.remove(uid);
        }
      case 'updateNewChat':
        final chat = u['chat'] as TdObject;
        chats[chat['id'] as int] = chat;
        _bumpChats();
      case 'updateChatTitle':
      case 'updateChatPhoto':
      case 'updateChatLastMessage':
      case 'updateChatReadInbox':
      case 'updateChatReadOutbox':
      case 'updateChatUnreadMentionCount':
      case 'updateChatNotificationSettings':
      case 'updateChatDraftMessage':
      case 'updateChatIsMarkedAsUnread':
        _mergeChat(u);
      case 'updateChatPosition':
        _updatePosition(u['chat_id'] as int, u['position'] as TdObject);
      case 'updateFile':
        final f = u['file'] as TdObject;
        fileNotifier(f['id'] as int).value = f;
      case 'updateNewMessage':
        final m = u['message'] as TdObject;
        unawaited(_maybeNotify(m));
        if (_shouldCache(m['chat_id'] as int)) await _store.cacheMessages([m]);
        _chatEvents.add({...u, 'chat_id': m['chat_id']});
      case 'updateMessageContent':
        await _onMessageContent(u);
        _chatEvents.add(u);
      case 'updateMessageEdited':
        final cached = await _store.cached(u['chat_id'] as int, u['message_id'] as int);
        if (cached != null) {
          cached['edit_date'] = u['edit_date'];
          await _store.cacheMessages([cached]);
        }
        _chatEvents.add(u);
      case 'updateDeleteMessages':
        await _onDelete(u);
      case 'updateMessageSendSucceeded':
        final m = u['message'] as TdObject;
        if (_shouldCache(m['chat_id'] as int)) await _store.cacheMessages([m]);
        _chatEvents.add({...u, 'chat_id': m['chat_id']});
        _afterOwnMessageSent();
      case 'updateMessageSendFailed':
        final m = u['message'] as TdObject;
        _chatEvents.add({...u, 'chat_id': m['chat_id']});
      case 'updateMessageInteractionInfo':
      case 'updateMessageIsPinned':
        _chatEvents.add(u);
    }
  }

  void _mergeChat(TdObject u) {
    final chat = chats[u['chat_id']];
    if (chat == null) return;
    u.forEach((k, v) {
      if (k == '@type' || k == 'chat_id') return;
      if (k == 'positions') {
        for (final p in (v as List)) {
          _setPosition(chat, p as TdObject);
        }
      } else {
        chat[k] = v;
      }
    });
    _bumpChats();
  }

  void _updatePosition(int chatId, TdObject position) {
    final chat = chats[chatId];
    if (chat == null) return;
    _setPosition(chat, position);
    _bumpChats();
  }

  void _setPosition(TdObject chat, TdObject position) {
    final list = (chat['positions'] as List? ?? []).cast<TdObject>().toList();
    final key = (position['list'] as TdObject)['@type'];
    list.removeWhere((p) => (p['list'] as TdObject)['@type'] == key);
    if (position['order'] != '0' && position['order'] != 0) list.add(position);
    chat['positions'] = list;
  }

  Timer? _chatsDebounce;
  void _bumpChats() {
    _chatsDebounce ??= Timer(const Duration(milliseconds: 60), () {
      _chatsDebounce = null;
      chatListVersion.value++;
    });
  }

  Future<void> _onAuthState(TdObject state) async {
    authState = state;
    notifyListeners();
    switch (state['@type']) {
      case 'authorizationStateWaitTdlibParameters':
        final docs = await getApplicationDocumentsDirectory();
        await td.send({
          '@type': 'setTdlibParameters',
          'use_test_dc': false,
          'database_directory': '${docs.path}/${_dir(currentAccount)}',
          'files_directory': '${docs.path}/${_dir(currentAccount)}_files',
          'database_encryption_key': '',
          'use_file_database': true,
          'use_chat_info_database': true,
          'use_message_database': true,
          'use_secret_chats': false,
          'api_id': _settings.apiId,
          'api_hash': _settings.apiHash,
          'system_language_code': Platform.localeName.split('_').first,
          'device_model': 'iPhone',
          'system_version': Platform.operatingSystemVersion,
          'application_version': '1.0 (AyuGram iOS)',
        });
      case 'authorizationStateReady':
        _returnTo = null;
        _applyOnline();
        _loadChats('chatListMain');
        _loadChats('chatListArchive');
        _loadBlocked();
        _saveAccountInfo();
      case 'authorizationStateClosed':
        _resetState();
        if (_removeOnClose != null) {
          accounts.remove(_removeOnClose);
          accountInfo.remove(_removeOnClose);
          if (accounts.isEmpty) accounts = [_removeOnClose!];
          if (!accounts.contains(_switchTo)) _switchTo = accounts.first;
          _removeOnClose = null;
        }
        currentAccount = _switchTo ?? currentAccount;
        _switchTo = null;
        _saveAccounts();
        await td.restart();
    }
  }

  static String _dir(int account) => account == 0 ? 'tdlib' : 'tdlib_$account';

  void _resetState() {
    chats.clear();
    users.clear();
    supergroups.clear();
    basicGroups.clear();
    blockedUsers.clear();
    chatFolders = [];
    unreadMessages = 0;
    myId = null;
    chatListVersion.value++;
  }

  void _saveAccounts() {
    _prefs.setStringList('accounts', accounts.map((e) => '$e').toList());
    _prefs.setInt('current_account', currentAccount);
    _prefs.setString('account_info', jsonEncode(accountInfo.map((k, v) => MapEntry('$k', v))));
    notifyListeners();
  }

  Future<void> _saveAccountInfo() async {
    try {
      final me = await td.send({'@type': 'getMe'});
      users[me['id'] as int] = me;
      myId = me['id'] as int;
      accountInfo[currentAccount] = {
        'id': me['id'],
        'name': '${me['first_name'] ?? ''} ${me['last_name'] ?? ''}'.trim(),
        'phone': me['phone_number'] ?? '',
      };
      _saveAccounts();
    } catch (_) {}
  }

  bool get isAddingAccount => _returnTo != null;

  /// Переключиться на другой сохранённый аккаунт.
  void switchAccount(int account) {
    if (account == currentAccount || !accounts.contains(account)) return;
    _switchTo = account;
    td.fire({'@type': 'close'});
  }

  /// Добавить аккаунт: новая папка базы и экран входа (или регистрации).
  void addAccount() {
    final next = accounts.reduce((a, b) => a > b ? a : b) + 1;
    accounts.add(next);
    _returnTo = currentAccount;
    _saveAccounts();
    switchAccount(next);
  }

  /// Отменить добавление аккаунта и вернуться к прежнему.
  void cancelAddAccount() {
    final back = _returnTo;
    if (back == null) return;
    _returnTo = null;
    _removeOnClose = currentAccount;
    _switchTo = back;
    td.fire({'@type': 'close'});
  }

  Future<void> _loadChats(String list) async {
    for (var i = 0; i < 10; i++) {
      try {
        await td.send({'@type': 'loadChats', 'chat_list': {'@type': list}, 'limit': 100});
      } on TdError {
        break; // 404 — все чаты загружены
      }
    }
  }

  Future<void> _loadBlocked() async {
    try {
      final res = await td.send({
        '@type': 'getBlockedMessageSenders',
        'block_list': {'@type': 'blockListMain'},
        'offset': 0,
        'limit': 100,
      });
      for (final s in (res['senders'] as List? ?? [])) {
        if (s['@type'] == 'messageSenderUser') blockedUsers.add(s['user_id'] as int);
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Сохранение удалённых и истории правок (ayu/data/messages_storage.cpp)
  // ---------------------------------------------------------------------------

  bool isBotChat(int chatId) {
    final type = chats[chatId]?['type'] as TdObject?;
    if (type?['@type'] != 'chatTypePrivate') return false;
    final user = users[type!['user_id']];
    return (user?['type'] as TdObject?)?['@type'] == 'userTypeBot';
  }

  bool _isSavable(int chatId) =>
      _settings.saveDeletedMessages && (!isBotChat(chatId) || _settings.saveForBots);

  bool _shouldCache(int chatId) =>
      (_settings.saveDeletedMessages || _settings.saveMessagesHistory) &&
      (!isBotChat(chatId) || _settings.saveForBots);

  /// Чат-экран сообщает загруженные сообщения — они кэшируются на случай удаления.
  Future<void> cacheLoaded(int chatId, List<TdObject> messages) async {
    if (_shouldCache(chatId)) await _store.cacheMessages(messages);
  }

  Future<void> _onMessageContent(TdObject u) async {
    final chatId = u['chat_id'] as int;
    final id = u['message_id'] as int;
    final old = await _store.cached(chatId, id);
    if (old == null) return;
    if (_settings.saveMessagesHistory && _shouldCache(chatId)) {
      await _store.saveEdit(old);
    }
    old['content'] = u['new_content'];
    await _store.cacheMessages([old]);
  }

  Future<void> _onDelete(TdObject u) async {
    final chatId = u['chat_id'] as int;
    final ids = (u['message_ids'] as List).cast<int>();
    var savedIds = <int>[];
    final own = _selfDeleted.remove(chatId) ?? const <int>{};
    if (u['is_permanent'] == true && u['from_cache'] != true && _isSavable(chatId)) {
      final saved = await _store.markDeleted(chatId, ids.where((id) => !own.contains(id)).toList());
      savedIds = [for (final m in saved) m['id'] as int];
    }
    _chatEvents.add({...u, 'ayu_saved_ids': savedIds});
  }

  /// Сообщения, удалённые самим пользователем, — их не сохраняем как «удалённые».
  final _selfDeleted = <int, Set<int>>{};

  void deleteMessages(int chatId, List<int> ids, {required bool revoke}) {
    _selfDeleted.putIfAbsent(chatId, () => {}).addAll(ids);
    td.fire({'@type': 'deleteMessages', 'chat_id': chatId, 'message_ids': ids, 'revoke': revoke});
  }

  // ---------------------------------------------------------------------------
  // Режим призрака
  // ---------------------------------------------------------------------------

  void setAppActive(bool active) {
    final wasActive = _appActive;
    _appActive = active;
    if (active && !wasActive && authState?['@type'] == 'authorizationStateReady') {
      // После сна iOS соединение могло умереть — просим TDLib переподключиться.
      td.fire({'@type': 'setNetworkType', 'type': {'@type': 'networkTypeOther'}});
    }
    _applyOnline();
  }

  bool? _sentOnline;

  void _applyOnline() {
    if (authState?['@type'] != 'authorizationStateReady') return;
    final online = _appActive && _settings.sendOnlinePackets;
    if (online && _sentOnline != true) {
      // Выключили призрака: TDLib мог считать статус уже «онлайн» и промолчать,
      // поэтому явно сбрасываем и ставим заново — сервер получит updateStatus(online).
      td.fire({'@type': 'setOption', 'name': 'online', 'value': {'@type': 'optionValueBoolean', 'value': false}});
    }
    _sentOnline = online;
    td.fire({'@type': 'setOption', 'name': 'online', 'value': {'@type': 'optionValueBoolean', 'value': online}});
  }

  /// sendOfflinePacketAfterOnline: сервер ставит «онлайн» при отправке сообщений,
  /// поэтому сразу после этого отправляем статус «не в сети».
  void _forceOffline() {
    if (_settings.sendOnlinePackets || !_settings.sendOfflinePacketAfterOnline) return;
    if (DateTime.now().isBefore(_suppressStatusUntil)) return;
    _suppressStatusUntil = DateTime.now().add(const Duration(seconds: 5));
    // TDLib не шлёт статус повторно, если значение не изменилось, — поэтому переключаем туда-обратно.
    td.fire({'@type': 'setOption', 'name': 'online', 'value': {'@type': 'optionValueBoolean', 'value': true}});
    td.fire({'@type': 'setOption', 'name': 'online', 'value': {'@type': 'optionValueBoolean', 'value': false}});
  }

  void _onSelfOnline() {
    if (!_appActive || !_settings.sendOnlinePackets) _forceOffline();
  }

  void _afterOwnMessageSent() {
    Future.delayed(const Duration(milliseconds: 500), _forceOffline);
  }

  /// Открытый сейчас чат (для него не показываем уведомления).
  int? openedChatId;

  Future<void> openChat(int chatId) {
    openedChatId = chatId;
    return td.send({'@type': 'openChat', 'chat_id': chatId}).catchError((_) => <String, dynamic>{});
  }

  Future<void> closeChat(int chatId) {
    if (openedChatId == chatId) openedChatId = null;
    return td.send({'@type': 'closeChat', 'chat_id': chatId}).catchError((_) => <String, dynamic>{});
  }

  /// Отметка о прочтении. В режиме призрака не отправляется.
  void viewMessages(int chatId, List<int> ids, {bool force = false}) {
    if (ids.isEmpty) return;
    if (!_settings.sendReadMessages && !force) return;
    td.fire({
      '@type': 'viewMessages',
      'chat_id': chatId,
      'message_ids': ids,
      'source': {'@type': 'messageSourceChatHistory'},
      'force_read': true,
    });
  }

  /// markReadAfterAction: прочитать чат после собственного действия (отправки сообщения).
  void markReadAfterAction(int chatId, List<int> ids) {
    if (_settings.sendReadMessages || !_settings.markReadAfterAction) return;
    viewMessages(chatId, ids, force: true);
  }

  DateTime _lastTyping = DateTime.fromMillisecondsSinceEpoch(0);

  /// Статус «печатает…». В режиме призрака не отправляется.
  void sendTyping(int chatId) {
    if (!_settings.sendUploadProgress) return;
    final now = DateTime.now();
    if (now.difference(_lastTyping).inSeconds < 4) return;
    _lastTyping = now;
    td.fire({'@type': 'sendChatAction', 'chat_id': chatId, 'action': {'@type': 'chatActionTyping'}});
  }

  /// getScheduleTime из ayu/utils/telegram_helpers.cpp.
  static int scheduleDelay(int sizeBytes) {
    var time = 12;
    time += (sizeBytes / 1024 / 1024 * 0.7).ceil().clamp(6, 1 << 30) + 1;
    return time;
  }

  TdObject sendOptions({int sizeBytes = 0}) {
    final options = <String, dynamic>{
      '@type': 'messageSendOptions',
      'disable_notification': _settings.shouldSendWithoutSound,
    };
    if (_settings.isUseScheduledMessages) {
      final at = DateTime.now().millisecondsSinceEpoch ~/ 1000 + scheduleDelay(sizeBytes);
      options['scheduling_state'] = {'@type': 'messageSchedulingStateSendAtDate', 'send_date': at};
    }
    return options;
  }

  Future<TdObject> _send(int chatId, TdObject content, {int? replyTo, int sizeBytes = 0}) {
    return td.send({
      '@type': 'sendMessage',
      'chat_id': chatId,
      if (replyTo != null) 'reply_to': {'@type': 'inputMessageReplyToMessage', 'message_id': replyTo},
      'options': sendOptions(sizeBytes: sizeBytes),
      'input_message_content': content,
    });
  }

  Future<TdObject> sendText(int chatId, String text, {int? replyTo}) => _send(chatId, {
        '@type': 'inputMessageText',
        'text': {'@type': 'formattedText', 'text': text, 'entities': []},
      }, replyTo: replyTo);

  /// Копирует файл к себе: временные файлы галереи iOS могут исчезнуть до загрузки.
  Future<String> _persist(String path, String prefix) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/outgoing');
    await dir.create(recursive: true);
    final ext = path.contains('.') ? path.substring(path.lastIndexOf('.')) : '';
    final target = '${dir.path}/$prefix${DateTime.now().microsecondsSinceEpoch}$ext';
    await File(path).copy(target);
    return target;
  }

  Future<TdObject> sendPhoto(int chatId, String path, {String caption = '', int? replyTo}) async {
    final local = await _persist(path, 'photo_');
    final bytes = await File(local).readAsBytes();
    var w = 0, h = 0;
    try {
      final codec = await instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      w = frame.image.width;
      h = frame.image.height;
    } catch (_) {}
    return _send(chatId, {
      '@type': 'inputMessagePhoto',
      'photo': {'@type': 'inputFileLocal', 'path': local},
      'width': w,
      'height': h,
      'added_sticker_file_ids': [],
      'caption': {'@type': 'formattedText', 'text': caption, 'entities': []},
    }, replyTo: replyTo, sizeBytes: bytes.length);
  }

  Future<TdObject> sendVoice(int chatId, String path, int seconds, String waveform, {int? replyTo}) async {
    final size = await File(path).length();
    return _send(chatId, {
      '@type': 'inputMessageVoiceNote',
      'voice_note': {'@type': 'inputFileLocal', 'path': path},
      'duration': seconds,
      'waveform': waveform,
    }, replyTo: replyTo, sizeBytes: size);
  }

  /// Статус «записывает голосовое». В режиме призрака не отправляется.
  void sendRecordingAction(int chatId, {bool cancel = false}) {
    if (!_settings.sendUploadProgress) return;
    td.fire({
      '@type': 'sendChatAction',
      'chat_id': chatId,
      'action': cancel ? null : {'@type': 'chatActionRecordingVoiceNote'},
    });
  }

  Future<void> forward(int toChatId, int fromChatId, List<int> ids) async {
    await td.send({
      '@type': 'forwardMessages',
      'chat_id': toChatId,
      'from_chat_id': fromChatId,
      'message_ids': ids,
      'options': sendOptions(),
      'send_copy': false,
      'remove_caption': false,
    });
  }

  // ---------------------------------------------------------------------------
  // Локальные уведомления AyuGram
  // ---------------------------------------------------------------------------

  final notifications = FlutterLocalNotificationsPlugin();
  bool _notificationsReady = false;

  Future<void> initNotifications() async {
    if (_notificationsReady) return;
    await notifications.initialize(
      settings: const InitializationSettings(
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _notificationsReady = true;
  }

  /// Запросить разрешение iOS. Возвращает, разрешил ли пользователь.
  Future<bool> requestNotificationPermission() async {
    await initNotifications();
    final ios = notifications.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
  }

  int _notifyId = 0;

  Future<void> _maybeNotify(TdObject m) async {
    if (!_settings.notificationsEnabled || !_notificationsReady) return;
    if (m['is_outgoing'] == true) return;
    final chatId = m['chat_id'] as int;
    if (_appActive && openedChatId == chatId) return;
    final chat = chats[chatId];
    if (chat == null || isMuted(chat)) return;
    final title = chat['title'] as String? ?? '';
    final sender = isGroup(chat) ? '${senderName(m['sender_id'] as TdObject?)}: ' : '';
    final body = _settings.streamerMode ? 'Новое сообщение' : '$sender${_previewOf(m['content'] as TdObject?)}';
    await notifications.show(
      id: _notifyId++,
      title: _settings.streamerMode ? 'AyuGram' : title,
      body: body,
      notificationDetails: const NotificationDetails(iOS: DarwinNotificationDetails(presentSound: true, presentBadge: true)),
    );
  }

  static String _previewOf(TdObject? c) {
    final t = c?['text'] ?? c?['caption'];
    final text = t is Map ? (t['text'] as String? ?? '') : '';
    return switch (c?['@type']) {
      'messageText' => text,
      'messagePhoto' => text.isEmpty ? 'Фото' : 'Фото, $text',
      'messageVideo' => text.isEmpty ? 'Видео' : 'Видео, $text',
      'messageVoiceNote' => 'Голосовое сообщение',
      'messageVideoNote' => 'Видеосообщение',
      'messageSticker' => '${(c!['sticker'] as Map?)?['emoji'] ?? ''} Стикер',
      'messageDocument' => 'Файл',
      _ => text.isEmpty ? 'Сообщение' : text,
    };
  }

  // ---------------------------------------------------------------------------
  // Файлы
  // ---------------------------------------------------------------------------

  ValueNotifier<TdObject> fileNotifier(int id) =>
      _files.putIfAbsent(id, () => ValueNotifier<TdObject>({'id': id}));

  /// Возвращает notifier файла и запускает загрузку, если её ещё нет.
  ValueNotifier<TdObject> file(TdObject f) {
    final n = fileNotifier(f['id'] as int);
    if ((n.value['local'] as TdObject?) == null) n.value = f;
    final local = n.value['local'] as TdObject?;
    if (local?['is_downloading_completed'] != true && local?['is_downloading_active'] != true) {
      td.fire({'@type': 'downloadFile', 'file_id': f['id'], 'priority': 1, 'synchronous': false});
    }
    return n;
  }

  // ---------------------------------------------------------------------------
  // Вспомогательное
  // ---------------------------------------------------------------------------

  List<TdObject> mainChatList() => chatList('chatListMain');

  /// Чаты списка (chatListMain / chatListArchive), отсортированные по order.
  List<TdObject> chatList(String type) {
    final list = <(BigInt, TdObject)>[];
    for (final chat in chats.values) {
      for (final p in (chat['positions'] as List? ?? [])) {
        if ((p['list'] as TdObject)['@type'] == type) {
          list.add((BigInt.parse('${p['order']}'), chat));
        }
      }
    }
    list.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final e in list) e.$2];
  }

  bool isPinned(TdObject chat) => (chat['positions'] as List? ?? [])
      .any((p) => (p['list'] as TdObject)['@type'] == 'chatListMain' && p['is_pinned'] == true);

  TdObject? supergroupOf(TdObject chat) {
    final t = chat['type'] as TdObject?;
    return t?['@type'] == 'chatTypeSupergroup' ? supergroups[t!['supergroup_id']] : null;
  }

  bool isChannel(TdObject chat) {
    final t = chat['type'] as TdObject?;
    return t?['@type'] == 'chatTypeSupergroup' && t?['is_channel'] == true;
  }

  bool isGroup(TdObject chat) {
    final t = chat['type'] as TdObject?;
    return t?['@type'] == 'chatTypeBasicGroup' || (t?['@type'] == 'chatTypeSupergroup' && t?['is_channel'] != true);
  }

  TdObject? privateUser(TdObject chat) {
    final t = chat['type'] as TdObject?;
    return t?['@type'] == 'chatTypePrivate' ? users[t!['user_id']] : null;
  }

  bool isVerified(TdObject chat) {
    final owner = privateUser(chat) ?? supergroupOf(chat);
    final v = owner?['verification_status'] as TdObject?;
    return v?['is_verified'] == true || owner?['is_verified'] == true;
  }

  int? memberCount(TdObject chat) {
    final t = chat['type'] as TdObject?;
    if (t?['@type'] == 'chatTypeSupergroup') return supergroups[t!['supergroup_id']]?['member_count'] as int?;
    if (t?['@type'] == 'chatTypeBasicGroup') return basicGroups[t!['basic_group_id']]?['member_count'] as int?;
    return null;
  }

  /// Можно ли писать в чат (в каналах — только админам с правом публикации).
  bool canPost(TdObject chat) {
    if (isChannel(chat)) {
      final status = supergroupOf(chat)?['status'] as TdObject?;
      return status?['@type'] == 'chatMemberStatusCreator' ||
          (status?['@type'] == 'chatMemberStatusAdministrator' &&
              (status?['rights'] as TdObject?)?['can_post_messages'] == true);
    }
    return (chat['permissions'] as TdObject?)?['can_send_basic_messages'] != false || privateUser(chat) != null;
  }

  bool isMuted(TdObject chat) => ((chat['notification_settings'] as TdObject?)?['mute_for'] as int? ?? 0) > 0;

  void setMuted(TdObject chat, bool muted) {
    final ns = Map<String, dynamic>.from(chat['notification_settings'] as TdObject? ?? {});
    ns['@type'] = 'chatNotificationSettings';
    ns['use_default_mute_for'] = false;
    ns['mute_for'] = muted ? 2147483647 : 0;
    chat['notification_settings'] = ns;
    td.fire({'@type': 'setChatNotificationSettings', 'chat_id': chat['id'], 'notification_settings': ns});
    _bumpChats();
  }

  String userName(int id) {
    final u = users[id];
    if (u == null) return 'Пользователь $id';
    final name = '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
    return name.isEmpty ? 'Удалённый аккаунт' : name;
  }

  String senderName(TdObject? sender) {
    if (sender == null) return '';
    if (sender['@type'] == 'messageSenderUser') return userName(sender['user_id'] as int);
    return chats[sender['chat_id']]?['title'] as String? ?? '';
  }

  Future<void> logOut() async {
    _removeOnClose = currentAccount;
    _switchTo = accounts.firstWhere((a) => a != currentAccount, orElse: () => currentAccount);
    if (_switchTo == currentAccount) _removeOnClose = null;
    accountInfo.remove(currentAccount);
    await td.send({'@type': 'logOut'});
  }
}
