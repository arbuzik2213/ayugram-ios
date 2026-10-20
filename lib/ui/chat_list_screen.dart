import 'package:flutter/material.dart';

import '../ayu/ayu_settings.dart';
import '../td/td_client.dart';
import '../td/td_service.dart';
import 'ayu_theme.dart';
import 'chat_screen.dart';
import 'format.dart';
import 'settings_screen.dart';
import 'widgets.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _svc = TdService.instance;
  String _query = '';
  bool _searching = false;

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    return Scaffold(
      drawer: const _AyuDrawer(),
      appBar: AppBar(
        leading: _searching
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _searching = false;
                  _query = '';
                }),
              )
            : Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
        title: _searching
            ? TextField(
                autofocus: true,
                style: TextStyle(color: c.actionBarTitle, fontSize: 18),
                cursorColor: c.actionBarTitle,
                decoration: InputDecoration(
                  hintText: 'Поиск',
                  hintStyle: TextStyle(color: c.actionBarSubtitle),
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _query = v.toLowerCase()),
              )
            : ListenableBuilder(
                listenable: AyuSettings.instance,
                builder: (context, _) => Row(children: [
                  const Text('AyuGram'),
                  if (AyuSettings.instance.isGhostModeActive)
                    const Padding(padding: EdgeInsets.only(left: 8), child: Text('👻', style: TextStyle(fontSize: 18))),
                ]),
              ),
        actions: [
          if (!_searching)
            IconButton(icon: const Icon(Icons.search), onPressed: () => setState(() => _searching = true)),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: _svc.chatListVersion,
        builder: (context, _, _) {
          var chats = _svc.mainChatList();
          if (_query.isNotEmpty) {
            chats = chats.where((c) => (c['title'] as String? ?? '').toLowerCase().contains(_query)).toList();
          }
          if (chats.isEmpty && _query.isEmpty) {
            return Center(child: CircularProgressIndicator(color: c.blueText));
          }
          return ListView.builder(
            itemCount: chats.length,
            itemBuilder: (context, i) => _ChatCell(chat: chats[i], divider: i != chats.length - 1),
          );
        },
      ),
    );
  }
}

/// Ячейка чата как DialogCell в Telegram Android (72dp).
class _ChatCell extends StatelessWidget {
  const _ChatCell({required this.chat, required this.divider});
  final TdObject chat;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    final svc = TdService.instance;
    final streamer = AyuSettings.instance.streamerMode;
    final last = chat['last_message'] as TdObject?;
    final unread = chat['unread_count'] as int? ?? 0;
    final mentions = chat['unread_mention_count'] as int? ?? 0;
    final muted = ((chat['notification_settings'] as TdObject?)?['mute_for'] as int? ?? 0) > 0;
    final type = chat['type'] as TdObject?;
    final isGroup = type?['@type'] == 'chatTypeBasicGroup' ||
        (type?['@type'] == 'chatTypeSupergroup' && type?['is_channel'] != true);
    final isChannel = type?['@type'] == 'chatTypeSupergroup' && type?['is_channel'] == true;
    final online = type?['@type'] == 'chatTypePrivate' &&
        ((svc.users[type!['user_id']]?['status'] as TdObject?)?['@type'] == 'userStatusOnline');

    final content = last?['content'] as TdObject?;
    String? prefix;
    if (last != null && !isServiceMessage(content)) {
      if (last['is_outgoing'] == true && !isChannel && type?['@type'] != 'chatTypePrivate') {
        prefix = 'Вы';
      } else if (isGroup && last['is_outgoing'] != true) {
        prefix = svc.senderName(last['sender_id'] as TdObject?).split(' ').first;
      }
    }
    final draft = chat['draft_message'] as TdObject?;
    final draftText = ((draft?['input_message_text'] as TdObject?)?['text'] as TdObject?)?['text'] as String?;
    final outgoing = last?['is_outgoing'] == true && !isChannel;
    final read = outgoing && (last!['id'] as int) <= (chat['last_read_outbox_message_id'] as int? ?? 0);

    final msgStyle = TextStyle(fontSize: 16, color: c.chatMessage, height: 1.2);
    Widget message;
    if (streamer) {
      message = Text('•••', style: msgStyle);
    } else if (draftText != null && draftText.isNotEmpty) {
      message = Text.rich(
        TextSpan(children: [
          const TextSpan(text: 'Черновик: ', style: TextStyle(color: Color(0xffdd4b39))),
          TextSpan(text: draftText.replaceAll('\n', ' ')),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: msgStyle,
      );
    } else {
      final preview = contentPreview(content).replaceAll('\n', ' ');
      message = Text.rich(
        TextSpan(children: [
          if (prefix != null) TextSpan(text: '$prefix: ', style: TextStyle(color: c.chatNameMessage)),
          TextSpan(
            text: preview,
            style: isServiceMessage(content) || content?['@type'] != 'messageText' ? TextStyle(color: c.blueText) : null,
          ),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: msgStyle,
      );
    }

    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: chat['id'] as int))),
      child: SizedBox(
        height: 72,
        child: Row(children: [
          Padding(
            padding: const EdgeInsets.only(left: 10, right: 12),
            child: Stack(clipBehavior: Clip.none, children: [
              Avatar(id: chat['id'] as int, title: chat['title'] as String? ?? '', photo: chat['photo'] as TdObject?, radius: 27),
              if (online)
                Positioned(
                  right: 1,
                  bottom: 1,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: c.online,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.windowBg, width: 2.5),
                    ),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: divider ? Border(bottom: BorderSide(color: c.divider, width: 0.5)) : null,
              ),
              padding: const EdgeInsets.only(right: 12),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Row(children: [
                  Expanded(
                    child: Row(children: [
                      if (isGroup || isChannel)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(isChannel ? Icons.campaign : Icons.group, size: 16, color: c.chatName),
                        ),
                      Flexible(
                        child: Text(chat['title'] as String? ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.chatName)),
                      ),
                      if (muted)
                        Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.volume_off, size: 15, color: c.pinnedIcon)),
                    ]),
                  ),
                  if (outgoing)
                    Padding(
                      padding: const EdgeInsets.only(right: 3),
                      child: Icon(read ? Icons.done_all : Icons.done, size: 17, color: c.sentCheck),
                    ),
                  if (last != null) Text(chatListTime(last['date'] as int), style: TextStyle(fontSize: 13, color: c.chatDate)),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(child: message),
                  if (mentions > 0) _Badge(text: '@', color: c.unread),
                  if (unread > 0)
                    _Badge(text: unread > 999 ? '999+' : '$unread', color: muted ? c.unreadMuted : c.unread)
                  else if (svc.isPinned(chat))
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Transform.rotate(angle: 0.75, child: Icon(Icons.push_pin, size: 18, color: c.pinnedIcon)),
                    ),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(left: 6),
        constraints: const BoxConstraints(minWidth: 23),
        height: 23,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(11.5)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      );
}

/// Боковое меню (DrawerLayoutContainer) с переключателем призрака, как в AyuGram4A.
class _AyuDrawer extends StatelessWidget {
  const _AyuDrawer();

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    final svc = TdService.instance;
    final s = AyuSettings.instance;
    final me = svc.users[svc.myId];
    final name = svc.myId == null ? '' : svc.userName(svc.myId!);
    final phone = me?['phone_number'] as String?;

    Widget item(IconData icon, String title, VoidCallback onTap, {Widget? trailing}) => InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Row(children: [
              Padding(padding: const EdgeInsets.only(left: 19, right: 26), child: Icon(icon, color: c.menuIcon)),
              Expanded(child: Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.menuText))),
              ?trailing,
            ]),
          ),
        );

    return Drawer(
      backgroundColor: c.menuBg,
      shape: const RoundedRectangleBorder(),
      child: ListenableBuilder(
        listenable: s,
        builder: (context, _) => ListView(padding: EdgeInsets.zero, children: [
          Container(
            color: c.menuTop,
            padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 16, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Avatar(
                id: svc.myId ?? 0,
                title: name,
                photo: me?['profile_photo'] as TdObject?,
                radius: 32,
              ),
              const SizedBox(height: 14),
              Text(s.streamerMode ? 'Скрыто' : name,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              if (phone != null && !s.streamerMode)
                Text('+$phone', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
            ]),
          ),
          const SizedBox(height: 6),
          item(Icons.bookmark_border, 'Избранное', () {
            Navigator.pop(context);
            final id = svc.myId;
            if (id == null) return;
            svc.td.send({'@type': 'createPrivateChat', 'user_id': id, 'force': false}).then((chat) {
              if (context.mounted) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: chat['id'] as int)));
              }
            });
          }),
          item(
            Icons.visibility_off_outlined,
            'Режим призрака',
            () => s.setGhostModeEnabled(!s.isGhostModeActive),
            trailing: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Switch(value: s.isGhostModeActive, onChanged: s.setGhostModeEnabled),
            ),
          ),
          item(
            Icons.mark_chat_read_outlined,
            'Отправлять прочтение',
            () {
              s.sendReadMessages = !s.sendReadMessages;
              s.save();
            },
            trailing: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Switch(
                value: s.sendReadMessages,
                onChanged: (v) {
                  s.sendReadMessages = v;
                  s.save();
                },
              ),
            ),
          ),
          Divider(height: 13, thickness: 0.5, color: c.divider),
          item(Icons.settings_outlined, 'Настройки AyuGram', () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
          }),
        ]),
      ),
    );
  }
}
