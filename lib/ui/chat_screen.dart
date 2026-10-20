import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

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
import 'widgets.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.chatId});
  final int chatId;

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
        final res = await _svc.td.send({
          '@type': 'getChatHistory',
          'chat_id': _chatId,
          'from_message_id': from,
          'offset': 0,
          'limit': 50,
          'only_local': false,
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
      final saved = _settings.saveDeletedMessages ? await _store.deletedInRange(_chatId, lower, upper) : <TdObject>[];

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
    final reply = _replyTo?['id'] as int?;
    setState(() => _replyTo = null);
    try {
      final sent = await _svc.sendText(_chatId, text, replyTo: reply);
      _afterSend(sent);
    } on TdError catch (e) {
      _toast(e.message);
      _input.text = text;
    }
  }

  Future<void> _sendPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;
    try {
      final sent = await _svc.sendPhoto(_chatId, picked.path, caption: _input.text.trim());
      _input.clear();
      _afterSend(sent);
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
    final chat = _chat;
    String base;
    final user = _svc.privateUser(chat);
    if (user != null) {
      base = userStatus(user);
    } else {
      final n = _svc.memberCount(chat);
      final channel = _svc.isChannel(chat);
      base = n == null
          ? (channel ? 'канал' : 'группа')
          : '${formatThousands(n)} ${channel ? plural(n, 'подписчик', 'подписчика', 'подписчиков') : plural(n, 'участник', 'участника', 'участников')}';
    }
    return base;
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

  void _openInfo() =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => ChatInfoScreen(chatId: _chatId)));

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    final chat = _chat;
    final isGroup = _svc.isGroup(chat);
    final saved = _chatId == _svc.myId;

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

    return Scaffold(
      backgroundColor: c.historyBg,
      appBar: AppBar(
        titleSpacing: 0,
        toolbarHeight: 54,
        title: GestureDetector(
          onTap: _openInfo,
          behavior: HitTestBehavior.opaque,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(saved ? 'Избранное' : chat['title'] as String? ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.windowBoldFg)),
              ),
              if (_svc.isVerified(chat)) const VerifiedBadge(size: 15),
            ]),
            if (!saved)
              Text(_subtitle(),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.windowSubTextFg)),
          ]),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: c.menuIconFg),
            onSelected: (v) {
              switch (v) {
                case 'info':
                  _openInfo();
                case 'read':
                  _svc.viewMessages(_chatId, [for (final m in _messages.take(100)) m['id'] as int], force: true);
                  _toast('Чат прочитан');
                case 'filtered':
                  setState(() => _showFiltered = !_showFiltered);
                case 'deleted':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => DeletedMessagesScreen(chatId: _chatId)));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'info', child: Text('Информация')),
              const PopupMenuItem(value: 'read', child: Text('Прочитать на сервере')),
              PopupMenuItem(value: 'filtered', child: Text(_showFiltered ? 'Скрыть отфильтрованные' : 'Показать отфильтрованные')),
              const PopupMenuItem(value: 'deleted', child: Text('Удалённые сообщения')),
            ],
          ),
        ],
      ),
      body: AyuWallpaper(
        child: Column(children: [
          if (_pinned != null) _pinnedBar(c),
          if (hidden > 0)
            GestureDetector(
              onTap: () => setState(() => _showFiltered = true),
              child: Container(
                width: double.infinity,
                color: c.windowBg,
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Text('Скрыто фильтрами: $hidden · показать',
                    textAlign: TextAlign.center, style: TextStyle(color: c.windowActiveTextFg, fontSize: 14)),
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              reverse: true,
              padding: const EdgeInsets.symmetric(vertical: 6),
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
                      child: last
                          ? Avatar(id: sid, title: _svc.senderName(sender), photo: photo, radius: 16)
                          : const SizedBox(width: 32),
                    ),
                    Expanded(child: row),
                  ]);
                }
                if (!newDay) return row;
                return Column(children: [ServicePill(dayHeader(m['date'] as int)), row]);
              },
            ),
          ),
          _svc.canPost(chat) ? _composer() : _muteBar(chat),
        ]),
      ),
    );
  }

  Widget _pinnedBar(AyuColors c) {
    final p = _pinned!;
    return Material(
      color: c.windowBg,
      child: InkWell(
        onTap: () {
          final i = _indexOf(p['id'] as int);
          if (i != -1) _toast(contentPreview(p['content'] as TdObject?));
        },
        child: Container(
          height: 46,
          padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.historyBg))),
          child: Row(children: [
            Container(width: 2, color: c.windowActiveTextFg),
            const SizedBox(width: 9),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('Закреплённое сообщение',
                    style: TextStyle(color: c.windowActiveTextFg, fontSize: 13.5, fontWeight: FontWeight.w600)),
                Text(contentPreview(p['content'] as TdObject?).replaceAll('\n', ' '),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.windowFg, fontSize: 13.5)),
              ]),
            ),
            Icon(Icons.push_pin_outlined, size: 20, color: c.menuIconFg),
          ]),
        ),
      ),
    );
  }

  /// Нижняя кнопка в канале без права публикации (ChannelBottomButton = MuteUnmute).
  Widget _muteBar(TdObject chat) {
    final c = context.ayu;
    final muted = _svc.isMuted(chat);
    return Material(
      color: c.historyComposeAreaBg,
      child: InkWell(
        onTap: () => setState(() => _svc.setMuted(chat, !muted)),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 48,
            width: double.infinity,
            child: Center(
              child: Text(muted ? 'ВКЛЮЧИТЬ ЗВУК' : 'ВЫКЛЮЧИТЬ ЗВУК',
                  style: TextStyle(color: c.lightButtonFg, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _composer() {
    final c = context.ayu;
    return Container(
      color: c.historyComposeAreaBg,
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_replyTo != null)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 6, 4, 0),
              child: Row(children: [
                Icon(Icons.reply, color: c.windowActiveTextFg),
                const SizedBox(width: 12),
                Container(width: 2, height: 34, color: c.windowActiveTextFg),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Ответ ${_svc.senderName(_replyTo!['sender_id'] as TdObject?)}',
                        style: TextStyle(color: c.windowActiveTextFg, fontWeight: FontWeight.w600, fontSize: 13.5)),
                    Text(contentPreview(_replyTo!['content'] as TdObject?).replaceAll('\n', ' '),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.windowFg, fontSize: 13.5)),
                  ]),
                ),
                IconButton(icon: Icon(Icons.close, color: c.historyComposeIconFg), onPressed: () => setState(() => _replyTo = null)),
              ]),
            ),
          ListenableBuilder(
            listenable: _input,
            builder: (context, _) {
              final empty = _input.text.trim().isEmpty;
              return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                IconButton(
                  icon: Transform.rotate(angle: 0.6, child: Icon(Icons.attach_file, color: c.historyComposeIconFg, size: 24)),
                  onPressed: _sendPhoto,
                ),
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 6,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => _svc.sendTyping(_chatId),
                    style: TextStyle(fontSize: 15, color: c.windowFg),
                    decoration: InputDecoration(
                      hintText: _settings.isGhostModeActive ? 'Написать сообщение… 👻' : 'Написать сообщение…',
                      hintStyle: TextStyle(color: c.placeholderFg, fontSize: 15),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(empty ? Icons.mic_none : Icons.send, color: empty ? c.historyComposeIconFg : c.historySendIconFg, size: 25),
                  onPressed: empty ? () => _toast('Голосовые пока не поддерживаются') : _send,
                ),
              ]);
            },
          ),
        ]),
      ),
    );
  }
}
