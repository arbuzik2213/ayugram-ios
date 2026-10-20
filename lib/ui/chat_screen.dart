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
import 'message_history_screen.dart';
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
    final type = chat['type'] as TdObject?;
    String base;
    switch (type?['@type']) {
      case 'chatTypePrivate':
        base = userStatus(_svc.users[type!['user_id']]);
      case 'chatTypeSupergroup':
        base = type!['is_channel'] == true ? 'канал' : 'группа';
      case 'chatTypeBasicGroup':
        base = 'группа';
      default:
        base = '';
    }
    if (_settings.showPeerId) base = '$base · ${peerIdLabel(chat)}';
    return base;
  }

  String? _replyText(TdObject m) {
    final r = m['reply_to'] as TdObject?;
    if (r?['@type'] != 'messageReplyToMessage') return null;
    final i = _indexOf(r!['message_id'] as int);
    if (i == -1) return '↩ ответ';
    final orig = _messages[i];
    return '${_svc.senderName(orig['sender_id'] as TdObject?)}: ${contentPreview(orig['content'] as TdObject?)}';
  }

  @override
  Widget build(BuildContext context) {
    final chat = _chat;
    final type = (chat['type'] as TdObject?)?['@type'];
    final isGroup = type == 'chatTypeBasicGroup' ||
        (type == 'chatTypeSupergroup' && (chat['type'] as TdObject)['is_channel'] != true);

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
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          Avatar(id: _chatId, title: chat['title'] as String? ?? '', photo: chat['photo'] as TdObject?, radius: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(chat['title'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17)),
              Text(_subtitle(), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
            ]),
          ),
        ]),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
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
              const PopupMenuItem(value: 'read', child: Text('Прочитать чат')),
              PopupMenuItem(value: 'filtered', child: Text(_showFiltered ? 'Скрыть отфильтрованные' : 'Показать отфильтрованные')),
              const PopupMenuItem(value: 'deleted', child: Text('Удалённые сообщения')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        if (hidden > 0)
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: InkWell(
              onTap: () => setState(() => _showFiltered = true),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text('Скрыто фильтрами: $hidden — показать', textAlign: TextAlign.center),
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            reverse: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: visible.length,
            itemBuilder: (context, i) {
              final m = visible[i];
              final older = i + 1 < visible.length ? visible[i + 1] : null;
              final newDay = older == null || dayHeader(older['date'] as int) != dayHeader(m['date'] as int);
              final sameSender = older != null &&
                  jsonEncode(older['sender_id']) == jsonEncode(m['sender_id']) &&
                  !newDay;
              final bubble = MessageBubble(
                key: ValueKey(m['id']),
                message: m,
                chat: chat,
                isDeleted: _deleted.contains(m['id']),
                isEdited: _edited.contains(m['id']),
                showSender: isGroup && !sameSender,
                replyPreview: _replyText(m),
                onLongPress: () => _messageMenu(m),
              );
              if (!newDay) return bubble;
              return Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(dayHeader(m['date'] as int),
                      style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor, fontWeight: FontWeight.w600)),
                ),
                bubble,
              ]);
            },
          ),
        ),
        _composer(),
      ]),
    );
  }

  Widget _composer() {
    final canSend = (_chat['permissions'] as TdObject?)?['can_send_basic_messages'] != false ||
        (_chat['type'] as TdObject?)?['@type'] == 'chatTypePrivate';
    return SafeArea(
      top: false,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_replyTo != null)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 0),
            child: Row(children: [
              const Icon(Icons.reply, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(contentPreview(_replyTo!['content'] as TdObject?), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _replyTo = null)),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.attach_file), onPressed: canSend ? _sendPhoto : null),
            Expanded(
              child: TextField(
                controller: _input,
                enabled: canSend,
                minLines: 1,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => _svc.sendTyping(_chatId),
                decoration: InputDecoration(
                  hintText: canSend
                      ? (_settings.isGhostModeActive ? 'Сообщение 👻' : 'Сообщение')
                      : 'Отправка недоступна',
                  filled: true,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                ),
              ),
            ),
            IconButton(icon: const Icon(Icons.send, color: ayuAccent), onPressed: canSend ? _send : null),
          ]),
        ),
      ]),
    );
  }
}
