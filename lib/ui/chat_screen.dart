import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ogg_opus_player/ogg_opus_player.dart';
import 'package:path_provider/path_provider.dart';

import '../ayu/ayu_settings.dart';
import '../ayu/filters.dart';
import '../ayu/message_store.dart';
import '../td/td_client.dart';
import '../td/td_service.dart';
import 'format.dart';
import 'message_bubble.dart';
import 'chat_info_screen.dart';
import 'message_history_screen.dart';
import 'ayu_theme.dart';
import 'voice.dart';
import 'widgets.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.chatId, this.threadId});
  final int chatId;

  /// Комментарии к посту: id корневого сообщения в группе обсуждения.
  final int? threadId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _svc = TdService.instance;
  final _settings = AyuSettings.instance;
  final _store = MessageStore.instance;
  final _input = TextEditingController();
  final _scroll = ScrollController();

  /// Новые сверху (ListView перевёрнут).
  final _messages = <TdObject>[];
  final _deleted = <int>{};
  final _edited = <int>{};
  bool _loading = false;
  bool _hasMore = true;
  bool _showFiltered = false;
  TdObject? _replyTo;
  TdObject? _pinned;
  StreamSubscription? _sub;

  TdObject get _chat => _svc.chats[widget.chatId] ?? {'id': widget.chatId, 'title': ''};
  int get _chatId => widget.chatId;

  @override
  void initState() {
    super.initState();
    _sub = _svc.chatEvents(_chatId).listen(_onEvent);
    _svc.openChat(_chatId);
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _loadMore();
    });
    _init();
  }

  Future<void> _init() async {
    final deleted = await _store.deletedAt(_chatId);
    final edited = await _store.editedIds(_chatId);
    _deleted.addAll(deleted.keys);
    _edited.addAll(edited);
    await _loadMore();
    _markVisibleRead();
    _loadPinned();
  }

  Future<void> _loadPinned() async {
    try {
      final p = await _svc.td.send({'@type': 'getChatPinnedMessage', 'chat_id': _chatId});
      if (mounted) setState(() => _pinned = p);
    } catch (_) {}
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _recorder?.dispose();
    _sub?.cancel();
    _svc.closeChat(_chatId);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // --- Загрузка истории ---------------------------------------------------

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    _loading = true;
    try {
      final fromId = _messages.isEmpty ? 0 : _messages.last['id'] as int;
      final page = <TdObject>[];
      // TDLib может вернуть меньше, чем просили (сначала только локальное), поэтому добираем.
      for (var attempt = 0; attempt < 3 && page.length < 30; attempt++) {
        final from = page.isEmpty ? fromId : page.last['id'] as int;
        final res = await _svc.td.send(widget.threadId == null
            ? {
                '@type': 'getChatHistory',
                'chat_id': _chatId,
                'from_message_id': from,
                'offset': 0,
                'limit': 50,
                'only_local': false,
              }
            : {
                '@type': 'getMessageThreadHistory',
                'chat_id': _chatId,
                'message_id': widget.threadId,
                'from_message_id': from,
                'offset': 0,
                'limit': 50,
              });
        final msgs = (res['messages'] as List? ?? []).cast<TdObject>().where((m) => m['id'] != from).toList();
        if (msgs.isEmpty) break;
        page.addAll(msgs);
      }
      if (page.isEmpty) _hasMore = false;
      unawaited(_svc.cacheLoaded(_chatId, page));

      // Подмешиваем сохранённые удалённые сообщения в этот диапазон.
      final upper = fromId == 0 ? 1 << 53 : fromId - 1;
      final lower = page.isEmpty ? 0 : page.last['id'] as int;
      final saved = _settings.saveDeletedMessages && widget.threadId == null
          ? await _store.deletedInRange(_chatId, lower, upper)
          : <TdObject>[];

      final known = {for (final m in _messages) m['id']};
      final merged = [...page, ...saved.where((m) => !page.any((p) => p['id'] == m['id']))]
          .where((m) => !known.contains(m['id']))
          .toList()
        ..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
      if (mounted) setState(() => _messages.addAll(merged));
    } catch (e) {
      _toast('Ошибка загрузки: $e');
    } finally {
      _loading = false;
    }
  }

  void _markVisibleRead() {
    final ids = [
      for (final m in _messages.take(100))
        if (m['is_outgoing'] != true && !_deleted.contains(m['id'])) m['id'] as int,
    ];
    _svc.viewMessages(_chatId, ids);
  }

  // --- Обновления ---------------------------------------------------------

  int _indexOf(int id) => _messages.indexWhere((m) => m['id'] == id);

  void _onEvent(TdObject u) {
    if (!mounted) return;
    setState(() {
      switch (u['@type']) {
        case 'updateNewMessage':
          final m = u['message'] as TdObject;
          if (widget.threadId != null && m['message_thread_id'] != widget.threadId) break;
          if (_indexOf(m['id'] as int) == -1) {
            _messages.insert(0, m);
            if (m['is_outgoing'] != true) _svc.viewMessages(_chatId, [m['id'] as int]);
          }
        case 'updateMessageSendSucceeded':
        case 'updateMessageSendFailed':
          final i = _indexOf(u['old_message_id'] as int);
          final m = u['message'] as TdObject;
          if (i != -1) {
            _messages[i] = m;
          } else if (_indexOf(m['id'] as int) == -1) {
            _messages.insert(0, m);
          }
          _messages.sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
          if (u['@type'] == 'updateMessageSendFailed') {
            _toast('Не отправлено: ${(u['error'] as TdObject?)?['message'] ?? ''}');
          }
        case 'updateMessageContent':
          final i = _indexOf(u['message_id'] as int);
          if (i != -1) _messages[i] = {..._messages[i], 'content': u['new_content']};
          if (_settings.saveMessagesHistory) _edited.add(u['message_id'] as int);
        case 'updateMessageEdited':
          final i = _indexOf(u['message_id'] as int);
          if (i != -1) {
            _messages[i] = {..._messages[i], 'edit_date': u['edit_date'], 'reply_markup': u['reply_markup']};
          }
        case 'updateMessageIsPinned':
          _loadPinned();
        case 'updateMessageInteractionInfo':
          final i = _indexOf(u['message_id'] as int);
          if (i != -1) _messages[i] = {..._messages[i], 'interaction_info': u['interaction_info']};
        case 'updateDeleteMessages':
          final saved = (u['ayu_saved_ids'] as List? ?? []).cast<int>().toSet();
          for (final id in (u['message_ids'] as List).cast<int>()) {
            if (saved.contains(id)) {
              _deleted.add(id);
            } else if (u['is_permanent'] == true && !_deleted.contains(id)) {
              _messages.removeWhere((m) => m['id'] == id);
            }
          }
      }
    });
  }

  // --- Отправка -----------------------------------------------------------

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    final reply = (_replyTo?['id'] as int?) ?? widget.threadId;
    setState(() => _replyTo = null);
    try {
      final sent = await _svc.sendText(_chatId, text, replyTo: reply);
      _afterSend(sent);
    } on TdError catch (e) {
      _toast(e.message);
      _input.text = text;
    }
  }

  Future<void> _attach() async {
    final c = context.ayu;
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(CupertinoIcons.photo_on_rectangle, color: c.windowActiveTextFg),
            title: const Text('Фото из галереи'),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
          ListTile(
            leading: Icon(CupertinoIcons.camera, color: c.windowActiveTextFg),
            title: const Text('Камера'),
            onTap: () => Navigator.pop(ctx, 'camera'),
          ),
        ]),
      ),
    );
    if (source == null) return;
    try {
      final picker = ImagePicker();
      final files = source == 'camera'
          ? [?await picker.pickImage(source: ImageSource.camera, imageQuality: 88)]
          : await picker.pickMultiImage(imageQuality: 88, limit: 10);
      if (files.isEmpty) return;
      final caption = _input.text.trim();
      _input.clear();
      final reply = (_replyTo?['id'] as int?) ?? widget.threadId;
      setState(() => _replyTo = null);
      for (var i = 0; i < files.length; i++) {
        final sent = await _svc.sendPhoto(_chatId, files[i].path, caption: i == 0 ? caption : '', replyTo: reply);
        _afterSend(sent);
      }
    } on TdError catch (e) {
      _toast('Не удалось отправить фото: ${e.message}');
    } catch (e) {
      _toast('Не удалось отправить фото: $e');
    }
  }

  // --- Голосовые ----------------------------------------------------------

  OggOpusRecorder? _recorder;
  String? _recordPath;
  DateTime? _recordStart;
  Timer? _recordTimer;
  double _recordDx = 0;

  bool get _recording => _recorder != null;

  Future<void> _startRecording() async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().microsecondsSinceEpoch}.ogg';
    final r = OggOpusRecorder(path);
    r.start();
    HapticFeedback.mediumImpact();
    _svc.sendRecordingAction(_chatId);
    setState(() {
      _recorder = r;
      _recordPath = path;
      _recordStart = DateTime.now();
      _recordDx = 0;
    });
    _recordTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _stopRecording({required bool send}) async {
    final r = _recorder;
    if (r == null) return;
    _recordTimer?.cancel();
    setState(() => _recorder = null);
    await r.stop();
    _svc.sendRecordingAction(_chatId, cancel: true);
    if (!send) {
      r.dispose();
      HapticFeedback.lightImpact();
      return;
    }
    final seconds = (await r.duration()).round();
    final wave = await r.getWaveformData();
    r.dispose();
    if (seconds < 1) {
      _toast('Удерживайте, чтобы записать голосовое');
      return;
    }
    try {
      final reply = (_replyTo?['id'] as int?) ?? widget.threadId;
      setState(() => _replyTo = null);
      final sent = await _svc.sendVoice(_chatId, _recordPath!, seconds, Waveform.encode(wave), replyTo: reply);
      _afterSend(sent);
    } on TdError catch (e) {
      _toast(e.message);
    }
  }

  // --- Комментарии и пересылка --------------------------------------------

  Future<void> _openComments(TdObject m) async {
    try {
      final info = await _svc.td.send({'@type': 'getMessageThread', 'chat_id': _chatId, 'message_id': m['id']});
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(chatId: info['chat_id'] as int, threadId: info['message_thread_id'] as int),
        ),
      );
    } on TdError catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _forward(TdObject m) async {
    final target = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ForwardPicker(),
    );
    if (target == null) return;
    try {
      await _svc.forward(target, _chatId, [m['id'] as int]);
      _toast('Сообщение переслано');
    } on TdError catch (e) {
      _toast(e.message);
    }
  }

  void _afterSend(TdObject sent) {
    final scheduling = sent['scheduling_state'] as TdObject?;
    if (scheduling != null) {
      final at = scheduling['send_date'] as int;
      final left = at - DateTime.now().millisecondsSinceEpoch ~/ 1000;
      _toast('👻 Отправится через $left с (отложенная отправка)');
    }
    _svc.markReadAfterAction(_chatId, [
      for (final m in _messages.take(50))
        if (m['is_outgoing'] != true) m['id'] as int,
    ]);
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  // --- Меню сообщения -----------------------------------------------------

  Future<void> _messageMenu(TdObject m) async {
    final id = m['id'] as int;
    final isDeleted = _deleted.contains(id);
    final text = contentText(m['content'] as TdObject?);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!isDeleted) _menuItem(context, 'reply', Icons.reply, 'Ответить'),
          if (!isDeleted) _menuItem(context, 'forward', CupertinoIcons.arrowshape_turn_up_right, 'Переслать'),
          if (text.isNotEmpty) _menuItem(context, 'copy', Icons.copy, 'Копировать'),
          if (_edited.contains(id)) _menuItem(context, 'history', Icons.history, 'История изменений'),
          if (!isDeleted && m['is_outgoing'] != true && !_settings.sendReadMessages)
            _menuItem(context, 'read', Icons.done_all, 'Прочитать (обойти призрака)'),
          _menuItem(context, 'details', Icons.info_outline, 'Подробнее'),
          if (!isDeleted) _menuItem(context, 'delete', Icons.delete_outline, 'Удалить'),
        ]),
      ),
    );
    switch (action) {
      case 'reply':
        setState(() => _replyTo = m);
      case 'forward':
        await _forward(m);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: text));
        _toast('Скопировано');
      case 'history':
        if (!mounted) return;
        Navigator.push(context, MaterialPageRoute(builder: (_) => EditHistoryScreen(current: m)));
      case 'read':
        _svc.viewMessages(_chatId, [id], force: true);
        _toast('Отмечено прочитанным');
      case 'details':
        _showDetails(m);
      case 'delete':
        await _confirmDelete(m);
    }
  }

  Widget _menuItem(BuildContext context, String value, IconData icon, String label) =>
      ListTile(leading: Icon(icon), title: Text(label), onTap: () => Navigator.pop(context, value));

  void _showDetails(TdObject m) {
    final sender = m['sender_id'] as TdObject?;
    final lines = <String>[
      'ID сообщения: ${m['id']}',
      'ID чата: ${m['chat_id']}',
      if (sender != null) 'Отправитель: ${_svc.senderName(sender)} (${sender['user_id'] ?? sender['chat_id']})',
      'Отправлено: ${fullDate(m['date'] as int)}',
      if ((m['edit_date'] as int? ?? 0) != 0) 'Изменено: ${fullDate(m['edit_date'] as int)}',
      if (_deleted.contains(m['id'])) 'Удалено (сохранено AyuGram)',
      if ((m['interaction_info'] as TdObject?)?['view_count'] != null)
        'Просмотров: ${(m['interaction_info'] as TdObject)['view_count']}',
    ];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Подробнее'),
        content: SingleChildScrollView(child: SelectableText(lines.join('\n'))),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(m))),
            child: const Text('Копировать JSON'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(TdObject m) async {
    final canAll = m['can_be_deleted_for_all_users'] == true;
    final revoke = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить сообщение?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Только у меня')),
          if (canAll) TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('У всех')),
        ],
      ),
    );
    if (revoke == null) return;
    setState(() => _messages.removeWhere((x) => x['id'] == m['id']));
    _svc.deleteMessages(_chatId, [m['id'] as int], revoke: revoke);
  }

  // --- UI -----------------------------------------------------------------

  String _subtitle() {
    if (widget.threadId != null) return 'комментарии';
    final chat = _chat;
    final user = _svc.privateUser(chat);
    if (user != null) return userStatus(user);
    final n = _svc.memberCount(chat);
    final channel = _svc.isChannel(chat);
    return n == null
        ? (channel ? 'канал' : 'группа')
        : '${formatThousands(n)} ${channel ? plural(n, 'подписчик', 'подписчика', 'подписчиков') : plural(n, 'участник', 'участника', 'участников')}';
  }

  TdObject? _replyObject(TdObject m) {
    final r = m['reply_to'] as TdObject?;
    if (r?['@type'] != 'messageReplyToMessage') return null;
    final i = _indexOf(r!['message_id'] as int);
    return i == -1 ? null : _messages[i];
  }

  bool _sameSender(TdObject a, TdObject b) =>
      jsonEncode(a['sender_id']) == jsonEncode(b['sender_id']) &&
      dayHeader(a['date'] as int) == dayHeader(b['date'] as int) &&
      !isServiceMessage(a['content'] as TdObject?) &&
      !isServiceMessage(b['content'] as TdObject?);

  void _openInfo() => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatInfoScreen(chatId: _chatId)));

  @override
  Widget build(BuildContext context) {
    final chat = _chat;
    final isGroup = _svc.isGroup(chat);
    final channel = _svc.isChannel(chat);
    final top = MediaQuery.paddingOf(context).top;

    final visible = <TdObject>[];
    var hidden = 0;
    for (final m in _messages) {
      final filtered = AyuFilters.isFiltered(
        chat: chat,
        message: m,
        text: contentText(m['content'] as TdObject?),
        isBlockedUser: _svc.blockedUsers.contains,
      );
      if (filtered && !_showFiltered) {
        hidden++;
      } else {
        visible.add(m);
      }
    }
    final headerHeight = top + 62 + (_pinned != null && widget.threadId == null ? 54 : 0) + (hidden > 0 ? 40 : 0);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: AyuWallpaper(
        child: Stack(children: [
          Column(children: [
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                reverse: true,
                padding: EdgeInsets.only(top: headerHeight + 6, bottom: 8),
                itemCount: visible.length,
                itemBuilder: (context, i) {
                  final m = visible[i];
                  final older = i + 1 < visible.length ? visible[i + 1] : null;
                  final newer = i > 0 ? visible[i - 1] : null;
                  final newDay = older == null || dayHeader(older['date'] as int) != dayHeader(m['date'] as int);
                  final last = newer == null || !_sameSender(newer, m);
                  final incomingGroup = isGroup && m['is_outgoing'] != true && !isServiceMessage(m['content'] as TdObject?);
                  Widget row = MessageBubble(
                    key: ValueKey(m['id']),
                    message: m,
                    chat: chat,
                    isDeleted: _deleted.contains(m['id']),
                    isEdited: _edited.contains(m['id']),
                    showSender: isGroup && (older == null || !_sameSender(older, m)),
                    tail: last,
                    avatarSlot: incomingGroup,
                    replyTo: _replyObject(m),
                    onLongPress: () => _messageMenu(m),
                    onComments: channel ? () => _openComments(m) : null,
                    onForward: channel && !isServiceMessage(m['content'] as TdObject?) ? () => _forward(m) : null,
                  );
                  if (incomingGroup) {
                    final sender = m['sender_id'] as TdObject?;
                    final sid = (sender?['user_id'] ?? sender?['chat_id'] ?? 0) as int;
                    final photo = sender?['@type'] == 'messageSenderUser'
                        ? (_svc.users[sid]?['profile_photo'] as TdObject?)
                        : (_svc.chats[sid]?['photo'] as TdObject?);
                    row = Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(8, 0, 8, last ? 6 : 1),
                        child: last ? Avatar(id: sid, title: _svc.senderName(sender), photo: photo, radius: 17) : const SizedBox(width: 34),
                      ),
                      Expanded(child: row),
                    ]);
                  }
                  if (!newDay) return row;
                  return Column(children: [ServicePill(dayHeader(m['date'] as int)), row]);
                },
              ),
            ),
            _svc.canPost(chat) || widget.threadId != null ? _composer() : _channelBar(chat),
          ]),
          Positioned(top: 0, left: 0, right: 0, child: _header(chat, hidden)),
        ]),
      ),
    );
  }

  /// Шапка как в Telegram для iOS: «назад» с числом непрочитанных, имя по центру, аватар справа.
  Widget _header(TdObject chat, int hidden) {
    final c = context.ayu;
    final saved = _chatId == _svc.myId;
    final user = _svc.privateUser(chat);
    final online = (user?['status'] as TdObject?)?['@type'] == 'userStatusOnline';
    return SafeArea(
      bottom: false,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Glass(
                height: 48,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(CupertinoIcons.chevron_back, color: c.windowFg, size: 26),
                    ValueListenableBuilder<int>(
                      valueListenable: _svc.chatListVersion,
                      builder: (context, _, _) => _svc.unreadMessages > 0
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(color: c.windowFg, borderRadius: BorderRadius.circular(11)),
                              child: Text(compactCount(_svc.unreadMessages),
                                  style: TextStyle(color: c.windowBg, fontSize: 14, fontWeight: FontWeight.w700)),
                            )
                          : const SizedBox(),
                    ),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: widget.threadId == null ? _openInfo : null,
                child: Glass(
                  height: 48,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Flexible(
                          child: Text(
                            widget.threadId != null ? 'Комментарии' : saved ? 'Избранное' : chat['title'] as String? ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: c.windowFg),
                          ),
                        ),
                        if (_svc.isVerified(chat) && widget.threadId == null) const VerifiedBadge(size: 16),
                      ]),
                      if (!saved)
                        Text(_subtitle(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: online ? c.windowActiveTextFg : c.windowSubTextFg)),
                    ]),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: widget.threadId == null ? _openInfo : null,
              onLongPress: _chatMenu,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(color: c.windowBg.withValues(alpha: 0.85), shape: BoxShape.circle),
                child: Avatar(id: _chatId, title: chat['title'] as String? ?? '', photo: chat['photo'] as TdObject?, radius: 22, saved: saved),
              ),
            ),
          ]),
        ),
        if (_pinned != null && widget.threadId == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            child: Glass(
              height: 48,
              radius: 24,
              child: Row(children: [
                const SizedBox(width: 14),
                Container(width: 2.5, height: 30, color: c.windowActiveTextFg),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('Закреплённое сообщение',
                        style: TextStyle(color: c.windowActiveTextFg, fontSize: 14, fontWeight: FontWeight.w600)),
                    Text(contentPreview(_pinned!['content'] as TdObject?).replaceAll('\n', ' '),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.windowFg, fontSize: 14)),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Icon(CupertinoIcons.pin, size: 20, color: c.windowSubTextFg),
                ),
              ]),
            ),
          ),
        if (hidden > 0)
          GestureDetector(
            onTap: () => setState(() => _showFiltered = true),
            child: Glass(
              height: 32,
              radius: 16,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text('Скрыто фильтрами: $hidden · показать', style: TextStyle(color: c.windowActiveTextFg, fontSize: 13.5)),
              ),
            ),
          ),
      ]),
    );
  }

  Future<void> _chatMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _menuItem(ctx, 'read', CupertinoIcons.checkmark_alt_circle, 'Прочитать на сервере'),
          _menuItem(ctx, 'filtered', CupertinoIcons.line_horizontal_3_decrease,
              _showFiltered ? 'Скрыть отфильтрованные' : 'Показать отфильтрованные'),
          _menuItem(ctx, 'deleted', CupertinoIcons.trash, 'Удалённые сообщения'),
        ]),
      ),
    );
    switch (action) {
      case 'read':
        _svc.viewMessages(_chatId, [for (final m in _messages.take(100)) m['id'] as int], force: true);
        _toast('Чат прочитан');
      case 'filtered':
        setState(() => _showFiltered = !_showFiltered);
      case 'deleted':
        if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => DeletedMessagesScreen(chatId: _chatId)));
    }
  }

  /// Каналы без права публикации: «Вкл./Выкл. звук» или «Вступить».
  Widget _channelBar(TdObject chat) {
    final c = context.ayu;
    final status = (_svc.supergroupOf(chat)?['status'] as TdObject?)?['@type'];
    final left = status == 'chatMemberStatusLeft';
    final muted = _svc.isMuted(chat);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        child: Center(
          child: GestureDetector(
            onTap: () async {
              if (left) {
                try {
                  await _svc.td.send({'@type': 'joinChat', 'chat_id': _chatId});
                } on TdError catch (e) {
                  _toast(e.message);
                }
              } else {
                _svc.setMuted(chat, !muted);
              }
              if (mounted) setState(() {});
            },
            child: Glass(
              height: 48,
              child: SizedBox(
                width: 200,
                child: Center(
                  child: Text(left ? 'Вступить' : (muted ? 'Вкл. звук' : 'Выкл. звук'),
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.windowFg)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Поле ввода как в Telegram для iOS: скрепка, «Сообщение», микрофон/отправка.
  Widget _composer() {
    final c = context.ayu;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_replyTo != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Glass(
                radius: 18,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
                  child: Row(children: [
                    Icon(CupertinoIcons.reply, color: c.windowActiveTextFg, size: 20),
                    const SizedBox(width: 10),
                    Container(width: 2, height: 32, color: c.windowActiveTextFg),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Ответ ${_svc.senderName(_replyTo!['sender_id'] as TdObject?)}',
                            style: TextStyle(color: c.windowActiveTextFg, fontWeight: FontWeight.w600, fontSize: 14)),
                        Text(contentPreview(_replyTo!['content'] as TdObject?).replaceAll('\n', ' '),
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.windowFg, fontSize: 14)),
                      ]),
                    ),
                    IconButton(
                      icon: Icon(CupertinoIcons.xmark, color: c.windowSubTextFg, size: 20),
                      onPressed: () => setState(() => _replyTo = null),
                    ),
                  ]),
                ),
              ),
            ),
          ListenableBuilder(
            listenable: _input,
            builder: (context, _) {
              final empty = _input.text.trim().isEmpty;
              final elapsed = _recordStart == null ? 0.0 : DateTime.now().difference(_recordStart!).inMilliseconds / 1000;
              return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (!_recording)
                  GestureDetector(
                    onTap: _attach,
                    child: Glass(
                      height: 48,
                      child: SizedBox(width: 48, child: Icon(CupertinoIcons.paperclip, color: c.windowFg, size: 24)),
                    ),
                  ),
                if (!_recording) const SizedBox(width: 8),
                Expanded(
                  child: Glass(
                    radius: 24,
                    child: _recording
                        ? SizedBox(
                            height: 48,
                            child: Row(children: [
                              const SizedBox(width: 16),
                              const _BlinkingDot(),
                              const SizedBox(width: 8),
                              Text('${elapsed ~/ 60}:${(elapsed % 60).floor().toString().padLeft(2, '0')},${((elapsed * 10) % 10).floor()}',
                                  style: TextStyle(fontSize: 16, color: c.windowFg, fontFeatures: const [FontFeature.tabularFigures()])),
                              Expanded(
                                child: Opacity(
                                  opacity: (1 + _recordDx / 120).clamp(0.2, 1),
                                  child: Text('‹ Влево — отмена',
                                      textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: c.windowSubTextFg)),
                                ),
                              ),
                            ]),
                          )
                        : TextField(
                            controller: _input,
                            minLines: 1,
                            maxLines: 6,
                            textCapitalization: TextCapitalization.sentences,
                            onChanged: (_) => _svc.sendTyping(_chatId),
                            style: TextStyle(fontSize: 17, color: c.windowFg),
                            decoration: InputDecoration(
                              hintText: _settings.isGhostModeActive ? 'Сообщение 👻' : 'Сообщение',
                              hintStyle: TextStyle(color: c.placeholderFg, fontSize: 17),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                if (!empty && !_recording)
                  GestureDetector(
                    onTap: _send,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(color: c.historySendIconFg, shape: BoxShape.circle),
                      child: const Icon(CupertinoIcons.arrow_up, color: Colors.white, size: 26),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: () => _toast('Удерживайте, чтобы записать голосовое'),
                    onLongPressStart: (_) => _startRecording(),
                    onLongPressMoveUpdate: (d) => setState(() => _recordDx = d.offsetFromOrigin.dx),
                    onLongPressEnd: (_) => _stopRecording(send: _recordDx > -100),
                    onLongPressCancel: () => _stopRecording(send: false),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: _recording ? 64 : 48,
                      height: _recording ? 64 : 48,
                      decoration: _recording
                          ? BoxDecoration(color: c.historySendIconFg, shape: BoxShape.circle)
                          : null,
                      child: _recording
                          ? const Icon(CupertinoIcons.mic_fill, color: Colors.white, size: 30)
                          : Glass(height: 48, child: SizedBox(width: 48, child: Icon(CupertinoIcons.mic, color: c.windowFg, size: 25))),
                    ),
                  ),
              ]);
            },
          ),
        ]),
      ),
    );
  }
}

class _BlinkingDot extends StatefulWidget {
  const _BlinkingDot();

  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot> with SingleTickerProviderStateMixin {
  late final _ctl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..repeat(reverse: true);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _ctl,
        child: Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xffff3b30), shape: BoxShape.circle)),
      );
}

/// Выбор чата для пересылки.
class _ForwardPicker extends StatefulWidget {
  @override
  State<_ForwardPicker> createState() => _ForwardPickerState();
}

class _ForwardPickerState extends State<_ForwardPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    final svc = TdService.instance;
    final chats = svc
        .mainChatList()
        .where((x) => svc.canPost(x) && (_q.isEmpty || (x['title'] as String? ?? '').toLowerCase().contains(_q)))
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Text('Переслать', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.windowFg)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Container(
            height: 38,
            decoration: BoxDecoration(color: c.filterInputBg, borderRadius: BorderRadius.circular(19)),
            child: TextField(
              onChanged: (v) => setState(() => _q = v.toLowerCase()),
              style: TextStyle(color: c.windowFg),
              decoration: InputDecoration(
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                prefixIcon: Icon(CupertinoIcons.search, color: c.placeholderFg, size: 20),
                hintText: 'Поиск',
                hintStyle: TextStyle(color: c.placeholderFg),
                border: InputBorder.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: chats.length,
            itemBuilder: (context, i) {
              final chat = chats[i];
              final id = chat['id'] as int;
              return ListTile(
                leading: Avatar(id: id, title: chat['title'] as String? ?? '', photo: chat['photo'] as TdObject?, radius: 21, saved: id == svc.myId),
                title: Text(id == svc.myId ? 'Избранное' : chat['title'] as String? ?? '',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.windowFg, fontWeight: FontWeight.w600)),
                onTap: () => Navigator.pop(context, id),
              );
            },
          ),
        ),
      ]),
    );
  }
}
