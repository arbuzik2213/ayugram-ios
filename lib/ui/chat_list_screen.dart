import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../ayu/ayu_settings.dart';
import '../td/td_client.dart';
import '../td/td_service.dart';
import 'ayu_theme.dart';
import 'chat_screen.dart';
import 'countries.dart';
import 'format.dart';
import 'message_bubble.dart' show compactCount;
import 'telegram_settings.dart';
import 'widgets.dart';

/// Главный экран как в Telegram для iOS: вкладки «Контакты / Звонки / Чаты / Настройки»
/// в плавающей панели снизу и отдельная кнопка поиска.
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  int _tab = 2;
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    return Scaffold(
      backgroundColor: c.windowBg,
      body: Stack(children: [
        IndexedStack(index: _tab, children: [
          const ContactsTab(),
          const CallsTab(),
          _ChatsTab(onEditChanged: (v) => setState(() => _editing = v)),
          const TelegramSettingsScreen(embedded: true),
        ]),
        if (!(_editing && _tab == 2))
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 6),
              child: ValueListenableBuilder<int>(
                valueListenable: TdService.instance.chatListVersion,
                builder: (context, _, _) => _TabBar(
                  index: _tab,
                  unread: TdService.instance.unreadMessages,
                  onTap: (i) => setState(() => _tab = i),
                  onSearch: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Стеклянная панель вкладок.
class _TabBar extends StatelessWidget {
  const _TabBar({required this.index, required this.unread, required this.onTap, required this.onSearch});
  final int index;
  final int unread;
  final ValueChanged<int> onTap;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    const tabs = [
      (Icons.account_circle, 'Контакты'),
      (Icons.call, 'Звонки'),
      (Icons.chat_bubble, 'Чаты'),
      (Icons.settings, 'Настройки'),
    ];
    Widget glass({required Widget child}) => Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: c.dark ? 0.4 : 0.12), blurRadius: 18, offset: const Offset(0, 4)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(color: (c.dark ? c.windowBgOver : c.windowBg).withValues(alpha: 0.88), child: child),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(children: [
        Expanded(
          child: glass(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(children: [
                for (var i = 0; i < tabs.length; i++)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onTap(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: 56,
                        decoration: BoxDecoration(
                          color: i == index ? c.windowFg.withValues(alpha: 0.07) : Colors.transparent,
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(tabs[i].$1, size: 26, color: i == index ? c.windowActiveTextFg : c.windowFg.withValues(alpha: 0.85)),
                            const SizedBox(height: 2),
                            Text(tabs[i].$2,
                                maxLines: 1,
                                textScaler: TextScaler.noScaling,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: i == index ? c.windowActiveTextFg : c.windowFg.withValues(alpha: 0.85),
                                )),
                          ]),
                          if (i == 2 && unread > 0)
                            Positioned(
                              top: 2,
                              left: 38,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(color: const Color(0xffff3b30), borderRadius: BorderRadius.circular(10)),
                                child: Text(compactCount(unread),
                                    textScaler: TextScaler.noScaling,
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                              ),
                            ),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: onSearch,
          child: glass(child: SizedBox(width: 64, height: 64, child: Icon(Icons.search, size: 28, color: c.windowFg))),
        ),
      ]),
    );
  }
}

/// Скруглённая «стеклянная» кнопка шапки.
class _Pill extends StatelessWidget {
  const _Pill({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: c.dark ? c.windowBgOver : c.windowBg,
        borderRadius: BorderRadius.circular(23),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: c.dark ? 0.35 : 0.1), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: child,
    );
  }
}

// =============================================================================
// Вкладка «Чаты»
// =============================================================================

class _ChatsTab extends StatefulWidget {
  const _ChatsTab({required this.onEditChanged});
  final ValueChanged<bool> onEditChanged;

  @override
  State<_ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<_ChatsTab> {
  final _svc = TdService.instance;
  bool _editing = false;
  final _selected = <int>{};

  void _setEditing(bool v) {
    setState(() {
      _editing = v;
      _selected.clear();
    });
    widget.onEditChanged(v);
  }

  String _title() => switch (_svc.connectionState) {
        'connectionStateWaitingForNetwork' => 'Ожидание сети…',
        'connectionStateConnecting' || 'connectionStateConnectingToProxy' => 'Соединение…',
        'connectionStateUpdating' => 'Обновление…',
        _ => 'Чаты',
      };

  Future<void> _bulk(String action) async {
    final ids = _selected.toList();
    switch (action) {
      case 'read':
        for (final id in ids) {
          final last = (_svc.chats[id]?['last_message'] as TdObject?)?['id'];
          if (last != null) _svc.viewMessages(id, [last as int], force: true);
          _svc.td.fire({'@type': 'toggleChatIsMarkedAsUnread', 'chat_id': id, 'is_marked_as_unread': false});
        }
      case 'archive':
        for (final id in ids) {
          _svc.td.fire({'@type': 'addChatToList', 'chat_id': id, 'chat_list': {'@type': 'chatListArchive'}});
        }
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Удалить ${ids.length} ${plural(ids.length, 'чат', 'чата', 'чатов')}?'),
            content: const Text('Из групп и каналов вы выйдете, в личных чатах история удалится у вас.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Удалить', style: TextStyle(color: context.ayu.attentionFg)),
              ),
            ],
          ),
        );
        if (ok != true) return;
        for (final id in ids) {
          final chat = _svc.chats[id];
          if (chat == null) continue;
          if (_svc.privateUser(chat) != null) {
            _svc.td.fire({'@type': 'deleteChatHistory', 'chat_id': id, 'remove_from_chat_list': true, 'revoke': false});
          } else {
            _svc.td.fire({'@type': 'leaveChat', 'chat_id': id});
          }
        }
    }
    _setEditing(false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    final s = AyuSettings.instance;
    return SafeArea(
      bottom: false,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
          child: Row(children: [
            GestureDetector(
              onTap: () => _setEditing(!_editing),
              child: _Pill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Center(
                    child: Text(_editing ? 'Готово' : 'Изм.',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.windowFg)),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: _svc.chatListVersion,
                builder: (context, _, _) {
                  final title = _title();
                  return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (title != 'Чаты')
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: c.windowSubTextFg),
                        ),
                      ),
                    Flexible(
                      child: Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.windowFg)),
                    ),
                  ]);
                },
              ),
            ),
            _Pill(
              child: Row(children: [
                ListenableBuilder(
                  listenable: s,
                  builder: (context, _) => IconButton(
                    tooltip: 'Режим призрака',
                    icon: Icon(s.isGhostModeActive ? Icons.visibility_off : Icons.visibility_outlined,
                        color: s.isGhostModeActive ? c.windowActiveTextFg : c.windowFg),
                    onPressed: () {
                      final on = !s.isGhostModeActive;
                      s.setGhostModeEnabled(on);
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(SnackBar(
                          content: Text(on ? 'Режим призрака включён 👻' : 'Режим призрака выключен'),
                          duration: const Duration(seconds: 1),
                        ));
                    },
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.edit_square, color: c.windowFg),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SearchScreen(newMessage: true)),
                  ),
                ),
              ]),
            ),
          ]),
        ),
        Expanded(
          child: ValueListenableBuilder<int>(
            valueListenable: _svc.chatListVersion,
            builder: (context, _, _) {
              final chats = _svc.mainChatList();
              final archive = _svc.chatList('chatListArchive');
              if (chats.isEmpty) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
              final hasArchive = archive.isNotEmpty && !_editing;
              return ListView.builder(
                padding: EdgeInsets.only(bottom: _editing ? 10 : 110),
                itemCount: chats.length + (hasArchive ? 1 : 0),
                itemBuilder: (context, i) {
                  if (hasArchive && i == 0) return _ArchiveRow(chats: archive);
                  final chat = chats[i - (hasArchive ? 1 : 0)];
                  final id = chat['id'] as int;
                  return ChatRow(
                    chat: chat,
                    selected: _editing ? _selected.contains(id) : null,
                    onTap: _editing
                        ? () => setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id))
                        : null,
                  );
                },
              );
            },
          ),
        ),
        if (_editing)
          Container(
            decoration: BoxDecoration(color: c.windowBg, border: Border(top: BorderSide(color: c.inputBorderFg))),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 50,
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  for (final (action, label) in [('read', 'Прочитать'), ('archive', 'В архив'), ('delete', 'Удалить')])
                    TextButton(
                      onPressed: _selected.isEmpty ? null : () => _bulk(action),
                      child: Text(label,
                          style: TextStyle(
                            fontSize: 16,
                            color: _selected.isEmpty
                                ? c.windowSubTextFg
                                : action == 'delete'
                                    ? c.attentionFg
                                    : c.windowActiveTextFg,
                          )),
                    ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Миниатюра медиа из последнего сообщения (minithumbnail TDLib).
Widget? _miniThumb(TdObject? content) {
  if (content == null) return null;
  final media = (content['photo'] ?? content['video'] ?? content['animation'] ?? content['document'] ?? content['video_note'])
      as TdObject?;
  final mini = media?['minithumbnail'] as TdObject?;
  final data = mini?['data'] as String?;
  if (data == null || data.isEmpty) return null;
  return Padding(
    padding: const EdgeInsets.only(right: 5, top: 1),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Image.memory(base64Decode(data), width: 20, height: 20, fit: BoxFit.cover, gaplessPlayback: true),
    ),
  );
}

/// Строка чата как в Telegram для iOS (ChatListItem): аватар 60, превью в две строки.
class ChatRow extends StatelessWidget {
  const ChatRow({super.key, required this.chat, this.selected, this.onTap});
  final TdObject chat;
  final bool? selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    final svc = TdService.instance;
    final streamer = AyuSettings.instance.streamerMode;
    final id = chat['id'] as int;
    final last = chat['last_message'] as TdObject?;
    final unread = chat['unread_count'] as int? ?? 0;
    final markedUnread = chat['is_marked_as_unread'] == true;
    final mentions = chat['unread_mention_count'] as int? ?? 0;
    final muted = svc.isMuted(chat);
    final isGroup = svc.isGroup(chat);
    final saved = id == svc.myId;
    final online = ((svc.privateUser(chat)?['status'] as TdObject?)?['@type'] == 'userStatusOnline') && !saved;
    final content = last?['content'] as TdObject?;
    final outgoing = last?['is_outgoing'] == true && !svc.isChannel(chat) && !saved;
    final read = outgoing && (last!['id'] as int) <= (chat['last_read_outbox_message_id'] as int? ?? 0);
    final draft = chat['draft_message'] as TdObject?;
    final draftText = ((draft?['input_message_text'] as TdObject?)?['text'] as TdObject?)?['text'] as String?;

    final gray = TextStyle(fontSize: 15, color: c.dialogsTextFg, height: 1.25);
    String? sender;
    if (isGroup && last != null && !isServiceMessage(content)) {
      sender = last['is_outgoing'] == true ? 'Вы' : svc.senderName(last['sender_id'] as TdObject?);
    }
    final preview = contentPreview(content).replaceAll('\n', ' ');
    final thumb = _miniThumb(content);
    final forwarded = last?['forward_info'] != null;

    Widget messageLine(int lines) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (forwarded)
            Padding(padding: const EdgeInsets.only(right: 3, top: 1), child: Icon(Icons.shortcut, size: 16, color: c.dialogsTextFg)),
          ?thumb,
          Expanded(child: Text(preview, maxLines: lines, overflow: TextOverflow.ellipsis, style: gray)),
        ]);

    Widget body;
    if (streamer) {
      body = Text('•••', style: gray);
    } else if (draftText != null && draftText.isNotEmpty) {
      body = Text.rich(
        TextSpan(children: [
          TextSpan(text: 'Черновик: ', style: TextStyle(color: c.dialogsDraftFg)),
          TextSpan(text: draftText.replaceAll('\n', ' ')),
        ]),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: gray,
      );
    } else if (sender != null) {
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(sender, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, color: c.windowFg, height: 1.25)),
        messageLine(1),
      ]);
    } else {
      body = messageLine(2);
    }

    return InkWell(
      onTap: onTap ?? () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: id))),
      onLongPress: () => _chatMenu(context, chat),
      child: SizedBox(
        height: 80,
        child: Row(children: [
          if (selected != null)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Icon(selected! ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: selected! ? c.windowActiveTextFg : c.menuIconFg),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Stack(clipBehavior: Clip.none, children: [
              Avatar(id: id, title: chat['title'] as String? ?? '', photo: chat['photo'] as TdObject?, radius: 30, saved: saved),
              if (online)
                Positioned(
                  right: 1,
                  bottom: 1,
                  child: Container(
                    width: 15,
                    height: 15,
                    decoration: BoxDecoration(color: c.online, shape: BoxShape.circle, border: Border.all(color: c.windowBg, width: 2.5)),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.inputBorderFg, width: 0.5))),
              padding: const EdgeInsets.only(right: 14, top: 7, bottom: 7),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Row(children: [
                  Expanded(
                    child: Row(children: [
                      Flexible(
                        child: Text(saved ? 'Избранное' : chat['title'] as String? ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: c.windowFg)),
                      ),
                      if (svc.isVerified(chat)) const VerifiedBadge(size: 16),
                      if (muted)
                        Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.volume_off, size: 15, color: c.dialogsTextFg)),
                    ]),
                  ),
                  if (outgoing)
                    Padding(
                      padding: const EdgeInsets.only(right: 3, left: 4),
                      child: Icon(read ? Icons.done_all : Icons.done, size: 17, color: c.dialogsSentIconFg),
                    ),
                  if (last != null) Text(chatListTime(last['date'] as int), style: TextStyle(fontSize: 14.5, color: c.dialogsDateFg)),
                ]),
                const SizedBox(height: 3),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(child: body),
                  if (mentions > 0) _Badge(text: '@', color: c.dialogsUnreadBg),
                  if (unread > 0 || markedUnread)
                    _Badge(text: unread > 0 ? compactCount(unread) : '', color: muted ? c.dialogsUnreadBgMuted : c.dialogsUnreadBg)
                  else if (svc.isPinned(chat))
                    Padding(
                      padding: const EdgeInsets.only(left: 6, bottom: 2),
                      child: Transform.rotate(angle: 0.75, child: Icon(Icons.push_pin, size: 17, color: c.dialogsTextFg)),
                    ),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  static Future<void> _chatMenu(BuildContext context, TdObject chat) async {
    final svc = TdService.instance;
    final id = chat['id'] as int;
    final pinned = svc.isPinned(chat);
    final muted = svc.isMuted(chat);
    final archived = (chat['positions'] as List? ?? []).any((p) => (p['list'] as TdObject)['@type'] == 'chatListArchive');
    final unread = (chat['unread_count'] as int? ?? 0) > 0 || chat['is_marked_as_unread'] == true;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(unread ? Icons.mark_chat_read_outlined : Icons.mark_chat_unread_outlined),
            title: Text(unread ? 'Прочитать' : 'Пометить непрочитанным'),
            onTap: () => Navigator.pop(ctx, 'read'),
          ),
          ListTile(
            leading: Icon(pinned ? Icons.push_pin_outlined : Icons.push_pin),
            title: Text(pinned ? 'Открепить' : 'Закрепить'),
            onTap: () => Navigator.pop(ctx, 'pin'),
          ),
          ListTile(
            leading: Icon(muted ? Icons.volume_up_outlined : Icons.volume_off_outlined),
            title: Text(muted ? 'Включить звук' : 'Выключить звук'),
            onTap: () => Navigator.pop(ctx, 'mute'),
          ),
          ListTile(
            leading: Icon(archived ? Icons.unarchive_outlined : Icons.archive_outlined),
            title: Text(archived ? 'Вернуть из архива' : 'В архив'),
            onTap: () => Navigator.pop(ctx, 'archive'),
          ),
        ]),
      ),
    );
    switch (action) {
      case 'read':
        if (unread) {
          final last = (chat['last_message'] as TdObject?)?['id'];
          if (last != null) svc.viewMessages(id, [last as int], force: true);
          svc.td.fire({'@type': 'toggleChatIsMarkedAsUnread', 'chat_id': id, 'is_marked_as_unread': false});
        } else {
          svc.td.fire({'@type': 'toggleChatIsMarkedAsUnread', 'chat_id': id, 'is_marked_as_unread': true});
        }
      case 'pin':
        svc.td.fire({
          '@type': 'toggleChatIsPinned',
          'chat_list': {'@type': archived ? 'chatListArchive' : 'chatListMain'},
          'chat_id': id,
          'is_pinned': !pinned,
        });
      case 'mute':
        svc.setMuted(chat, !muted);
      case 'archive':
        svc.td.fire({
          '@type': 'addChatToList',
          'chat_id': id,
          'chat_list': {'@type': archived ? 'chatListMain' : 'chatListArchive'},
        });
    }
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(left: 6, bottom: 1),
        constraints: const BoxConstraints(minWidth: 22),
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(11)),
        child: Text(text,
            textScaler: TextScaler.noScaling,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
      );
}

/// Строка «Архив чатов».
class _ArchiveRow extends StatelessWidget {
  const _ArchiveRow({required this.chats});
  final List<TdObject> chats;

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    final unreadChats = chats.where((x) => (x['unread_count'] as int? ?? 0) > 0).length;
    final titles = chats.take(6).map((x) => x['title'] as String? ?? '').join(', ');
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ArchiveScreen())),
      child: SizedBox(
        height: 80,
        child: Row(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xff72d5fd), Color(0xff2a9ef1)],
                ),
              ),
              child: const Icon(Icons.archive, color: Colors.white, size: 28),
            ),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.inputBorderFg, width: 0.5))),
              padding: const EdgeInsets.only(right: 14, top: 7, bottom: 7),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('Архив чатов', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: c.windowFg)),
                const SizedBox(height: 3),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: Text(titles,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, color: c.windowFg, height: 1.25)),
                  ),
                  if (unreadChats > 0) _Badge(text: '$unreadChats', color: c.dialogsUnreadBgMuted),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class ArchiveScreen extends StatelessWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = TdService.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Архив')),
      body: ValueListenableBuilder<int>(
        valueListenable: svc.chatListVersion,
        builder: (context, _, _) {
          final chats = svc.chatList('chatListArchive');
          return ListView.builder(itemCount: chats.length, itemBuilder: (context, i) => ChatRow(chat: chats[i]));
        },
      ),
    );
  }
}

// =============================================================================
// Поиск: чаты, @юзернеймы, глобальный поиск и поиск по номеру телефона
// =============================================================================

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.newMessage = false});

  /// Открыто кнопкой «Новое сообщение» — без запроса показываем контакты.
  final bool newMessage;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _Result {
  _Result({required this.title, required this.subtitle, required this.avatarId, this.photo, this.chatId, this.userId});
  final String title;
  final String subtitle;
  final int avatarId;
  final TdObject? photo;
  final int? chatId;
  final int? userId;
}

class _SearchScreenState extends State<SearchScreen> {
  final _svc = TdService.instance;
  final _ctl = TextEditingController();
  List<_Result> _local = [];
  List<_Result> _global = [];
  _Result? _phone;
  List<_Result> _contacts = [];
  bool _searching = false;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    if (widget.newMessage) _loadContacts();
  }

  Future<void> _loadContacts() async {
    try {
      final r = await _svc.td.send({'@type': 'getContacts'});
      final ids = (r['user_ids'] as List? ?? []).cast<int>();
      final list = <_Result>[];
      for (final id in ids) {
        final u = _svc.users[id] ?? await _svc.td.send({'@type': 'getUser', 'user_id': id});
        _svc.users[id] = u;
        list.add(_Result(
          title: _svc.userName(id),
          subtitle: userStatus(u),
          avatarId: id,
          photo: u['profile_photo'] as TdObject?,
          userId: id,
        ));
      }
      list.sort((a, b) => a.title.compareTo(b.title));
      if (mounted) setState(() => _contacts = list);
    } catch (_) {}
  }

  String? _usernameOf(TdObject chat) {
    final owner = _svc.privateUser(chat) ?? _svc.supergroupOf(chat);
    return ((owner?['usernames'] as TdObject?)?['active_usernames'] as List?)?.cast<String>().firstOrNull;
  }

  _Result _fromChat(TdObject chat) {
    final username = _usernameOf(chat);
    final n = _svc.memberCount(chat);
    final user = _svc.privateUser(chat);
    final channel = _svc.isChannel(chat);
    final sub = username != null
        ? '@$username'
        : user != null
            ? userStatus(user)
            : n != null
                ? '${formatThousands(n)} ${channel ? plural(n, 'подписчик', 'подписчика', 'подписчиков') : plural(n, 'участник', 'участника', 'участников')}'
                : '';
    return _Result(
      title: chat['title'] as String? ?? '',
      subtitle: sub,
      avatarId: chat['id'] as int,
      photo: chat['photo'] as TdObject?,
      chatId: chat['id'] as int,
    );
  }

  Future<void> _search(String raw) async {
    final gen = ++_gen;
    final q = raw.trim();
    if (q.isEmpty) {
      setState(() {
        _local = [];
        _global = [];
        _phone = null;
        _searching = false;
      });
      return;
    }
    await Future.delayed(const Duration(milliseconds: 250));
    if (gen != _gen) return;
    setState(() => _searching = true);

    final query = q.startsWith('@') ? q.substring(1) : q;
    final lower = query.toLowerCase();

    // 1. Свои чаты: по названию и @юзернейму + searchChats TDLib.
    final local = <int, _Result>{};
    for (final chat in _svc.chats.values) {
      final title = (chat['title'] as String? ?? '').toLowerCase();
      final username = _usernameOf(chat)?.toLowerCase();
      if (lower.isNotEmpty && (title.contains(lower) || (username != null && username.contains(lower)))) {
        local[chat['id'] as int] = _fromChat(chat);
      }
    }
    try {
      final r = await _svc.td.send({'@type': 'searchChats', 'query': query, 'limit': 30});
      for (final id in (r['chat_ids'] as List? ?? []).cast<int>()) {
        final chat = _svc.chats[id];
        if (chat != null) local[id] = _fromChat(chat);
      }
    } catch (_) {}

    // 2. Глобальный поиск: точный @юзернейм и публичные чаты.
    final global = <int, _Result>{};
    if (RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{3,31}$').hasMatch(query)) {
      try {
        final chat = await _svc.td.send({'@type': 'searchPublicChat', 'username': query});
        final id = chat['id'] as int;
        _svc.chats.putIfAbsent(id, () => chat);
        if (!local.containsKey(id)) global[id] = _fromChat(_svc.chats[id]!);
      } catch (_) {}
      try {
        final r = await _svc.td.send({'@type': 'searchPublicChats', 'query': query});
        for (final id in (r['chat_ids'] as List? ?? []).cast<int>()) {
          final chat = _svc.chats[id];
          if (chat != null && !local.containsKey(id)) global[id] = _fromChat(chat);
        }
      } catch (_) {}
    }

    // 3. Номер телефона.
    _Result? phone;
    final digits = q.replaceAll(RegExp(r'[^0-9]'), '');
    if (RegExp(r'^\+?[0-9 ()\-]+$').hasMatch(q) && digits.length >= 7) {
      try {
        final u = await _svc.td.send({'@type': 'searchUserByPhoneNumber', 'phone_number': digits, 'only_local': false});
        final id = u['id'] as int;
        _svc.users[id] = u;
        phone = _Result(
          title: _svc.userName(id),
          subtitle: Countries.formatFull(u['phone_number'] as String? ?? digits),
          avatarId: id,
          photo: u['profile_photo'] as TdObject?,
          userId: id,
        );
      } catch (_) {}
    }

    if (gen != _gen || !mounted) return;
    setState(() {
      _local = local.values.toList();
      _global = global.values.toList();
      _phone = phone;
      _searching = false;
    });
  }

  Future<void> _open(_Result r) async {
    var chatId = r.chatId;
    if (chatId == null && r.userId != null) {
      try {
        final chat = await _svc.td.send({'@type': 'createPrivateChat', 'user_id': r.userId, 'force': false});
        chatId = chat['id'] as int;
        _svc.chats.putIfAbsent(chatId, () => chat);
      } catch (_) {}
    }
    if (chatId == null || !mounted) return;
    final id = chatId;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: id)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    final q = _ctl.text.trim();
    Widget section(String title, List<_Result> items) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: c.dividerBg,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Text(title.toUpperCase(), style: TextStyle(fontSize: 13, color: c.windowSubTextFg, fontWeight: FontWeight.w600)),
          ),
          for (final r in items)
            InkWell(
              onTap: () => _open(r),
              child: SizedBox(
                height: 58,
                child: Row(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Avatar(id: r.avatarId, title: r.title, photo: r.photo, radius: 21),
                  ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(r.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: c.windowFg)),
                      if (r.subtitle.isNotEmpty)
                        Text(r.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              color: r.subtitle.startsWith('@') ? c.windowActiveTextFg : c.windowSubTextFg,
                            )),
                    ]),
                  ),
                ]),
              ),
            ),
        ]);

    final empty = q.isNotEmpty && !_searching && _local.isEmpty && _global.isEmpty && _phone == null;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(children: [
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(color: c.filterInputBg, borderRadius: BorderRadius.circular(20)),
                  child: TextField(
                    controller: _ctl,
                    autofocus: true,
                    onChanged: (v) {
                      setState(() {});
                      _search(v);
                    },
                    style: TextStyle(fontSize: 16, color: c.windowFg),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 11),
                      prefixIcon: Icon(Icons.search, color: c.placeholderFg),
                      hintText: widget.newMessage ? 'Имя, @юзернейм или номер' : 'Чаты, @юзернейм, номер',
                      hintStyle: TextStyle(color: c.placeholderFg, fontSize: 16),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
            ]),
          ),
          if (_searching) LinearProgressIndicator(minHeight: 2, color: c.windowActiveTextFg, backgroundColor: Colors.transparent),
          Expanded(
            child: empty
                ? Center(child: Text('Ничего не найдено', style: TextStyle(color: c.windowSubTextFg, fontSize: 15)))
                : ListView(children: [
                    if (q.isEmpty && _contacts.isNotEmpty) section('Контакты', _contacts),
                    if (q.isEmpty && !widget.newMessage)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text('Ищите чаты по названию, людей — по @юзернейму или номеру телефона.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c.windowSubTextFg, fontSize: 14.5, height: 1.4)),
                      ),
                    if (_phone != null) section('По номеру телефона', [_phone!]),
                    if (_local.isNotEmpty) section('Чаты и контакты', _local),
                    if (_global.isNotEmpty) section('Глобальный поиск', _global),
                  ]),
          ),
        ]),
      ),
    );
  }
}

// =============================================================================
// Контакты и звонки
// =============================================================================

class ContactsTab extends StatefulWidget {
  const ContactsTab({super.key});

  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab> {
  final _svc = TdService.instance;
  List<int>? _ids;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _svc.td.send({'@type': 'getContacts'});
      final ids = (r['user_ids'] as List? ?? []).cast<int>();
      for (final id in ids) {
        if (!_svc.users.containsKey(id)) {
          try {
            _svc.users[id] = await _svc.td.send({'@type': 'getUser', 'user_id': id});
          } catch (_) {}
        }
      }
      int rank(int id) => switch ((_svc.users[id]?['status'] as TdObject?)?['@type']) {
            'userStatusOnline' => 2000000000,
            'userStatusOffline' => (_svc.users[id]!['status'] as TdObject)['was_online'] as int? ?? 0,
            'userStatusRecently' => 3,
            'userStatusLastWeek' => 2,
            'userStatusLastMonth' => 1,
            _ => 0,
          };
      ids.sort((a, b) => rank(b).compareTo(rank(a)));
      if (mounted) setState(() => _ids = ids);
    } catch (_) {
      if (mounted) setState(() => _ids = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    final ids = _ids;
    return SafeArea(
      bottom: false,
      child: Column(children: [
        SizedBox(
          height: 56,
          child: Center(child: Text('Контакты', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.windowFg))),
        ),
        Expanded(
          child: ids == null
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 110),
                    itemCount: ids.length,
                    itemBuilder: (context, i) {
                      final id = ids[i];
                      final u = _svc.users[id];
                      final online = (u?['status'] as TdObject?)?['@type'] == 'userStatusOnline';
                      return InkWell(
                        onTap: () async {
                          final chat = await _svc.td.send({'@type': 'createPrivateChat', 'user_id': id, 'force': false});
                          if (context.mounted) {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: chat['id'] as int)));
                          }
                        },
                        child: SizedBox(
                          height: 58,
                          child: Row(children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Avatar(id: id, title: _svc.userName(id), photo: u?['profile_photo'] as TdObject?, radius: 21),
                            ),
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.inputBorderFg, width: 0.5))),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(_svc.userName(id), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.windowFg)),
                                    Text(userStatus(u),
                                        style: TextStyle(fontSize: 14, color: online ? c.windowActiveTextFg : c.windowSubTextFg)),
                                  ],
                                ),
                              ),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ]),
    );
  }
}

class CallsTab extends StatefulWidget {
  const CallsTab({super.key});

  @override
  State<CallsTab> createState() => _CallsTabState();
}

class _CallsTabState extends State<CallsTab> {
  final _svc = TdService.instance;
  List<TdObject>? _calls;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _svc.td.send({'@type': 'searchCallMessages', 'offset': '', 'limit': 100, 'only_missed': false});
      if (mounted) setState(() => _calls = (r['messages'] as List? ?? []).cast<TdObject>());
    } catch (_) {
      if (mounted) setState(() => _calls = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    final calls = _calls;
    return SafeArea(
      bottom: false,
      child: Column(children: [
        SizedBox(
          height: 56,
          child: Center(child: Text('Звонки', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.windowFg))),
        ),
        Expanded(
          child: calls == null
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : calls.isEmpty
                  ? Center(child: Text('Звонков пока нет', style: TextStyle(color: c.windowSubTextFg)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 110),
                        itemCount: calls.length,
                        itemBuilder: (context, i) {
                          final m = calls[i];
                          final chat = _svc.chats[m['chat_id']];
                          final content = m['content'] as TdObject;
                          final out = m['is_outgoing'] == true;
                          final reason = (content['discard_reason'] as TdObject?)?['@type'];
                          final missed = !out && (reason == 'callDiscardReasonMissed' || reason == 'callDiscardReasonDeclined');
                          final dur = content['duration'] as int? ?? 0;
                          final video = content['is_video'] == true;
                          final kind = missed ? 'Пропущенный' : out ? 'Исходящий' : 'Входящий';
                          return InkWell(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => ChatScreen(chatId: m['chat_id'] as int)),
                            ),
                            child: SizedBox(
                              height: 60,
                              child: Row(children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Avatar(
                                    id: m['chat_id'] as int,
                                    title: chat?['title'] as String? ?? '',
                                    photo: chat?['photo'] as TdObject?,
                                    radius: 21,
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(chat?['title'] as String? ?? '',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: missed ? c.attentionFg : c.windowFg,
                                          )),
                                      Row(children: [
                                        Icon(out ? Icons.call_made : Icons.call_received, size: 14, color: c.windowSubTextFg),
                                        const SizedBox(width: 4),
                                        Text('$kind${video ? ' видео' : ''}${dur > 0 ? ' (${duration(dur)})' : ''}',
                                            style: TextStyle(fontSize: 14, color: c.windowSubTextFg)),
                                      ]),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(right: 14),
                                  child: Text(chatListTime(m['date'] as int), style: TextStyle(fontSize: 14, color: c.dialogsDateFg)),
                                ),
                              ]),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ]),
    );
  }
}
