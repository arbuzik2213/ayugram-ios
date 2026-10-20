import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

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
          'database_directory': '${docs.path}/tdlib',
          'files_directory': '${docs.path}/tdlib_files',
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
        _applyOnline();
        _loadChats();
        _loadBlocked();
      case 'authorizationStateClosed':
        chats.clear();
        users.clear();
        blockedUsers.clear();
        chatListVersion.value++;
        await td.restart();
    }
  }

  Future<void> _loadChats() async {
    for (var i = 0; i < 10; i++) {
      try {
        await td.send({'@type': 'loadChats', 'chat_list': {'@type': 'chatListMain'}, 'limit': 100});
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
    _appActive = active;
    _applyOnline();
  }

  void _applyOnline() {
    if (authState?['@type'] != 'authorizationStateReady') return;
    final online = _appActive && _settings.sendOnlinePackets;
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

  Future<void> openChat(int chatId) => td.send({'@type': 'openChat', 'chat_id': chatId}).catchError((_) => <String, dynamic>{});
  Future<void> closeChat(int chatId) => td.send({'@type': 'closeChat', 'chat_id': chatId}).catchError((_) => <String, dynamic>{});

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

  Future<TdObject> sendText(int chatId, String text, {int? replyTo}) {
    return td.send({
      '@type': 'sendMessage',
      'chat_id': chatId,
      if (replyTo != null) 'reply_to': {'@type': 'inputMessageReplyToMessage', 'message_id': replyTo},
      'options': sendOptions(),
      'input_message_content': {
        '@type': 'inputMessageText',
        'text': {'@type': 'formattedText', 'text': text, 'entities': []},
      },
    });
  }

  Future<TdObject> sendPhoto(int chatId, String path, {String caption = ''}) async {
    final size = await File(path).length();
    return td.send({
      '@type': 'sendMessage',
      'chat_id': chatId,
      'options': sendOptions(sizeBytes: size),
      'input_message_content': {
        '@type': 'inputMessagePhoto',
        'photo': {'@type': 'inputFileLocal', 'path': path},
        'caption': {'@type': 'formattedText', 'text': caption, 'entities': []},
      },
    });
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

  List<TdObject> mainChatList() {
    final list = <(BigInt, TdObject)>[];
    for (final chat in chats.values) {
      for (final p in (chat['positions'] as List? ?? [])) {
        if ((p['list'] as TdObject)['@type'] == 'chatListMain') {
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
    await td.send({'@type': 'logOut'});
  }
}
