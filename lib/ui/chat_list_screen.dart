import 'package:flutter/material.dart';

import '../ayu/ayu_settings.dart';
import '../td/td_client.dart';
import '../td/td_service.dart';
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
  final _settings = AyuSettings.instance;
  String _query = '';
  bool _searching = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Поиск', border: InputBorder.none),
                onChanged: (v) => setState(() => _query = v.toLowerCase()),
              )
            : const Text('AyuGram'),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              _query = '';
            }),
          ),
          ListenableBuilder(
            listenable: _settings,
            builder: (context, _) {
              final ghost = _settings.isGhostModeActive;
              return IconButton(
                tooltip: 'Режим призрака',
                icon: Icon(ghost ? Icons.visibility_off : Icons.visibility_outlined, color: ghost ? ayuAccent : null),
                onPressed: () {
                  _settings.setGhostModeEnabled(!ghost);
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(
                      content: Text(!ghost ? 'Режим призрака включён' : 'Режим призрака выключен'),
                      duration: const Duration(seconds: 1),
                    ));
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: _svc.chatListVersion,
        builder: (context, _, __) {
          var chats = _svc.mainChatList();
          if (_query.isNotEmpty) {
            chats = chats.where((c) => (c['title'] as String? ?? '').toLowerCase().contains(_query)).toList();
          }
          if (chats.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView.separated(
            itemCount: chats.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 80),
            itemBuilder: (context, i) => _ChatTile(chat: chats[i]),
          );
        },
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({required this.chat});
  final TdObject chat;

  @override
  Widget build(BuildContext context) {
    final svc = TdService.instance;
    final streamer = AyuSettings.instance.streamerMode;
    final last = chat['last_message'] as TdObject?;
    final unread = chat['unread_count'] as int? ?? 0;
    final muted = ((chat['notification_settings'] as TdObject?)?['mute_for'] as int? ?? 0) > 0;
    final type = (chat['type'] as TdObject?)?['@type'];
    final isGroup = type == 'chatTypeBasicGroup' ||
        (type == 'chatTypeSupergroup' && (chat['type'] as TdObject)['is_channel'] != true);

    var preview = contentPreview(last?['content'] as TdObject?);
    if (last != null && isGroup && !isServiceMessage(last['content'] as TdObject?)) {
      final name = last['is_outgoing'] == true ? 'Вы' : svc.senderName(last['sender_id'] as TdObject?).split(' ').first;
      preview = '$name: $preview';
    }
    final draft = chat['draft_message'] as TdObject?;
    final draftText = ((draft?['input_message_text'] as TdObject?)?['text'] as TdObject?)?['text'] as String?;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      leading: Avatar(id: chat['id'] as int, title: chat['title'] as String? ?? '', photo: chat['photo'] as TdObject?),
      title: Row(
        children: [
          Expanded(
            child: Text(chat['title'] as String? ?? '',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (muted) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.volume_off, size: 14, color: Colors.grey)),
          if (last != null)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(chatListTime(last['date'] as int), style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
            ),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: draftText != null && draftText.isNotEmpty
                ? Text.rich(TextSpan(children: [
                    const TextSpan(text: 'Черновик: ', style: TextStyle(color: Colors.redAccent)),
                    TextSpan(text: draftText),
                  ]), maxLines: 2, overflow: TextOverflow.ellipsis)
                : Text(streamer ? '•••' : preview, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          if (unread > 0)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: muted ? Colors.grey : ayuAccent, borderRadius: BorderRadius.circular(12)),
              child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 12)),
            )
          else if (svc.isPinned(chat))
            const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.push_pin, size: 16, color: Colors.grey)),
        ],
      ),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: chat['id'] as int))),
    );
  }
}
