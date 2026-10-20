import 'package:flutter/material.dart';

import '../ayu/ayu_settings.dart';
import '../td/td_client.dart';
import '../td/td_service.dart';
import 'ayu_theme.dart';
import 'chat_screen.dart';
import 'format.dart';
import 'settings_screen.dart';
import 'telegram_settings.dart';
import 'widgets.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _svc = TdService.instance;
  final _search = TextEditingController();
  final _scaffold = GlobalKey<ScaffoldState>();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    return Scaffold(
      key: _scaffold,
      drawer: const AyuDrawer(),
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          // Шапка как в AyuGram Desktop: меню + поле поиска.
          SizedBox(
            height: 54,
            child: Row(children: [
              IconButton(
                icon: ListenableBuilder(
                  listenable: AyuSettings.instance,
                  builder: (context, _) => Stack(clipBehavior: Clip.none, children: [
                    Icon(Icons.menu, color: c.menuIconFg),
                    if (AyuSettings.instance.isGhostModeActive)
                      Positioned(
                        right: -3,
                        top: -2,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: c.windowActiveTextFg, shape: BoxShape.circle),
                        ),
                      ),
                  ]),
                ),
                onPressed: () => _scaffold.currentState?.openDrawer(),
              ),
              Expanded(
                child: Container(
                  height: 34,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(color: c.filterInputBg, borderRadius: BorderRadius.circular(17)),
                  child: TextField(
                    controller: _search,
                    onChanged: (v) => setState(() => _query = v.toLowerCase()),
                    style: TextStyle(fontSize: 14, color: c.windowFg),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      contentPadding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
                      border: InputBorder.none,
                      hintText: 'Поиск',
                      hintStyle: TextStyle(color: c.placeholderFg, fontSize: 14),
                      suffixIcon: _query.isEmpty
                          ? null
                          : GestureDetector(
                              onTap: () => setState(() {
                                _search.clear();
                                _query = '';
                              }),
                              child: Icon(Icons.close, size: 18, color: c.menuIconFg),
                            ),
                      suffixIconConstraints: const BoxConstraints(minWidth: 32),
                    ),
                  ),
                ),
              ),
            ]),
          ),
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: _svc.chatListVersion,
              builder: (context, _, _) {
                var chats = _svc.mainChatList();
                if (_query.isNotEmpty) {
                  chats = chats.where((c) => (c['title'] as String? ?? '').toLowerCase().contains(_query)).toList();
                }
                if (chats.isEmpty && _query.isEmpty) {
                  return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                }
                return ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: chats.length,
                  itemBuilder: (context, i) => _ChatRow(chat: chats[i]),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

/// Строка диалога (Dialogs::Ui::RowPainter).
class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.chat});
  final TdObject chat;

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    final svc = TdService.instance;
    final streamer = AyuSettings.instance.streamerMode;
    final id = chat['id'] as int;
    final last = chat['last_message'] as TdObject?;
    final unread = chat['unread_count'] as int? ?? 0;
    final mentions = chat['unread_mention_count'] as int? ?? 0;
    final muted = svc.isMuted(chat);
    final isGroup = svc.isGroup(chat);
    final isChannel = svc.isChannel(chat);
    final saved = id == svc.myId;
    final online = ((svc.privateUser(chat)?['status'] as TdObject?)?['@type'] == 'userStatusOnline') && !saved;

    final content = last?['content'] as TdObject?;
    String? prefix;
    if (last != null && !isServiceMessage(content)) {
      if (last['is_outgoing'] == true && isGroup) {
        prefix = 'Вы';
      } else if (isGroup) {
        prefix = svc.senderName(last['sender_id'] as TdObject?).split(' ').first;
      }
    }
    final draft = chat['draft_message'] as TdObject?;
    final draftText = ((draft?['input_message_text'] as TdObject?)?['text'] as TdObject?)?['text'] as String?;
    final outgoing = last?['is_outgoing'] == true && !isChannel && !saved;
    final read = outgoing && (last!['id'] as int) <= (chat['last_read_outbox_message_id'] as int? ?? 0);

    final msgStyle = TextStyle(fontSize: 14, color: c.dialogsTextFg);
    Widget message;
    if (streamer) {
      message = Text('•••', style: msgStyle);
    } else if (draftText != null && draftText.isNotEmpty) {
      message = Text.rich(
        TextSpan(children: [
          TextSpan(text: 'Черновик: ', style: TextStyle(color: c.dialogsDraftFg)),
          TextSpan(text: draftText.replaceAll('\n', ' ')),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: msgStyle,
      );
    } else {
      final isText = content?['@type'] == 'messageText';
      message = Text.rich(
        TextSpan(children: [
          if (prefix != null) TextSpan(text: '$prefix: ', style: TextStyle(color: c.dialogsTextFgService)),
          TextSpan(
            text: contentPreview(content).replaceAll('\n', ' '),
            style: isServiceMessage(content) || !isText ? TextStyle(color: c.dialogsTextFgService) : null,
          ),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: msgStyle,
      );
    }

    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: id))),
      child: SizedBox(
        height: 62,
        child: Row(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
            child: Stack(clipBehavior: Clip.none, children: [
              Avatar(
                id: id,
                title: chat['title'] as String? ?? '',
                photo: chat['photo'] as TdObject?,
                radius: 23,
                saved: saved,
              ),
              if (online)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: c.online,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.windowBg, width: 2),
                    ),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Row(children: [
                  Expanded(
                    child: Row(children: [
                      if (isGroup || isChannel)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(isChannel ? Icons.campaign_outlined : Icons.people_outline,
                              size: 16, color: c.windowFg),
                        ),
                      Flexible(
                        child: Text(saved ? 'Избранное' : chat['title'] as String? ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: c.windowFg)),
                      ),
                      if (svc.isVerified(chat)) const VerifiedBadge(size: 15),
                      if (muted)
                        Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.volume_off, size: 14, color: c.menuIconFg)),
                    ]),
                  ),
                  if (outgoing)
                    Padding(
                      padding: const EdgeInsets.only(right: 3, left: 4),
                      child: Icon(read ? Icons.done_all : Icons.done, size: 16, color: c.dialogsSentIconFg),
                    ),
                  if (last != null)
                    Text(chatListTime(last['date'] as int), style: TextStyle(fontSize: 12.5, color: c.dialogsDateFg)),
                ]),
                const SizedBox(height: 5),
                Row(children: [
                  Expanded(child: message),
                  if (mentions > 0) _Badge(text: '@', color: c.dialogsUnreadBg),
                  if (unread > 0)
                    _Badge(text: '$unread', color: muted ? c.dialogsUnreadBgMuted : c.dialogsUnreadBg)
                  else if (svc.isPinned(chat))
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Transform.rotate(angle: 0.75, child: Icon(Icons.push_pin_outlined, size: 16, color: c.menuIconFg)),
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
        constraints: const BoxConstraints(minWidth: 20),
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

/// Главное меню AyuGram Desktop (Window::MainMenu).
class AyuDrawer extends StatelessWidget {
  const AyuDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    final svc = TdService.instance;
    final s = AyuSettings.instance;
    final me = svc.users[svc.myId];
    final name = svc.myId == null ? '' : svc.userName(svc.myId!);
    final verified = (me?['verification_status'] as TdObject?)?['is_verified'] == true;

    Widget item(IconData icon, String title, VoidCallback onTap, {bool? toggle, ValueChanged<bool>? onToggle}) => InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Row(children: [
              Padding(padding: const EdgeInsets.only(left: 20, right: 22), child: Icon(icon, color: c.menuIconFg, size: 22)),
              Expanded(child: Text(title, style: TextStyle(fontSize: 14.5, color: c.windowFg))),
              if (toggle != null)
                Padding(padding: const EdgeInsets.only(right: 16), child: AyuToggle(value: toggle, onChanged: onToggle)),
            ]),
          ),
        );

    void open(Widget screen) {
      Navigator.pop(context);
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    }

    return Drawer(
      backgroundColor: c.windowBg,
      width: 290,
      shape: const RoundedRectangleBorder(),
      child: ListenableBuilder(
        listenable: s,
        builder: (context, _) => Column(children: [
          Expanded(
            child: ListView(padding: EdgeInsets.zero, children: [
              Padding(
                padding: EdgeInsets.fromLTRB(22, MediaQuery.paddingOf(context).top + 18, 16, 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Avatar(id: svc.myId ?? 0, title: name, photo: me?['profile_photo'] as TdObject?, radius: 24),
                  const SizedBox(height: 14),
                  Row(children: [
                    Flexible(
                      child: Text(s.streamerMode ? 'Скрыто' : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: c.windowBoldFg, fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                    if (verified) const VerifiedBadge(size: 16),
                  ]),
                  const SizedBox(height: 3),
                  GestureDetector(
                    onTap: () => open(const SettingsScreen()),
                    child: Text('Настройки AyuGram', style: TextStyle(color: c.lightButtonFg, fontSize: 13.5)),
                  ),
                ]),
              ),
              Divider(height: 1, thickness: 1, color: c.dividerBg),
              const SizedBox(height: 6),
              item(Icons.account_circle_outlined, 'Мой профиль', () => open(const InformationScreen())),
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
              item(Icons.mark_email_read_outlined, 'Читать на сервере', () {
                s.sendReadMessages = !s.sendReadMessages;
                s.save();
              }, toggle: s.sendReadMessages, onToggle: (v) {
                s.sendReadMessages = v;
                s.save();
              }),
              item(Icons.settings_outlined, 'Настройки', () => open(const TelegramSettingsScreen())),
              item(Icons.dark_mode_outlined, 'Ночной режим', () {
                s.nightMode = !s.nightMode;
                s.save();
              }, toggle: s.nightMode, onToggle: (v) {
                s.nightMode = v;
                s.save();
              }),
              item(Icons.visibility_off_outlined, 'Режим призрака', () => s.setGhostModeEnabled(!s.isGhostModeActive),
                  toggle: s.isGhostModeActive, onToggle: s.setGhostModeEnabled),
            ]),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(22, 8, 22, MediaQuery.paddingOf(context).bottom + 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: 'AyuGram iOS\n', style: TextStyle(color: c.windowSubTextFg, fontWeight: FontWeight.w600)),
                  TextSpan(text: 'Версия 1.0 – ', style: TextStyle(color: c.windowSubTextFg)),
                  TextSpan(text: 'О программе', style: TextStyle(color: c.lightButtonFg)),
                ]),
                style: const TextStyle(fontSize: 12.5, height: 1.5),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
