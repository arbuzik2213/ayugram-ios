import 'package:flutter/material.dart';

import '../ayu/message_store.dart';
import '../td/td_client.dart';
import '../td/td_service.dart';
import 'format.dart';
import 'message_bubble.dart';

/// История правок сообщения (аналог ayu/ui/sections/edited/edited_log_section).
class EditHistoryScreen extends StatelessWidget {
  const EditHistoryScreen({super.key, required this.current});
  final TdObject current;

  @override
  Widget build(BuildContext context) {
    final chat = TdService.instance.chats[current['chat_id']] ?? {'id': current['chat_id']};
    return Scaffold(
      appBar: AppBar(title: const Text('История изменений')),
      body: FutureBuilder<List<TdObject>>(
        future: MessageStore.instance.edits(current['chat_id'] as int, current['id'] as int),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final versions = [...snap.data!, current];
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: versions.length,
            itemBuilder: (context, i) {
              final v = versions[i];
              final isLast = i == versions.length - 1;
              final date = (v['edit_date'] as int? ?? 0) != 0 ? v['edit_date'] as int : v['date'] as int;
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                  child: Text(isLast ? 'Текущая версия' : 'Версия ${i + 1} · ${fullDate(date)}',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                ),
                MessageBubble(message: v, chat: chat, isDeleted: false, isEdited: false, showSender: false),
              ]);
            },
          );
        },
      ),
    );
  }
}

/// Все сохранённые удалённые сообщения чата.
class DeletedMessagesScreen extends StatelessWidget {
  const DeletedMessagesScreen({super.key, required this.chatId});
  final int chatId;

  @override
  Widget build(BuildContext context) {
    final chat = TdService.instance.chats[chatId] ?? {'id': chatId};
    return Scaffold(
      appBar: AppBar(title: const Text('Удалённые сообщения')),
      body: FutureBuilder<List<TdObject>>(
        future: MessageStore.instance.allDeleted(chatId),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!;
          if (list.isEmpty) return const Center(child: Text('Пока ничего не удаляли'));
          return ListView.builder(
            reverse: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: list.length,
            itemBuilder: (context, i) => MessageBubble(
              message: list[i],
              chat: chat,
              isDeleted: true,
              isEdited: false,
              showSender: true,
            ),
          );
        },
      ),
    );
  }
}
