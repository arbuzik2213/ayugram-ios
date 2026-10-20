import 'package:flutter/material.dart';

import '../ayu/ayu_settings.dart';
import '../td/td_client.dart';
import '../td/td_service.dart';
import 'format.dart';
import 'widgets.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.chat,
    required this.isDeleted,
    required this.isEdited,
    required this.showSender,
    this.replyPreview,
    this.onLongPress,
  });

  final TdObject message;
  final TdObject chat;
  final bool isDeleted;
  final bool isEdited;
  final bool showSender;
  final String? replyPreview;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final s = AyuSettings.instance;
    final svc = TdService.instance;
    final out = message['is_outgoing'] == true;
    final content = message['content'] as TdObject?;
    final scheme = Theme.of(context).colorScheme;

    if (isServiceMessage(content)) {
      final who = svc.senderName(message['sender_id'] as TdObject?);
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 40),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
          child: Text('$who: ${contentPreview(content)}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
        ),
      );
    }

    final bubbleColor = out ? scheme.primaryContainer : scheme.surfaceContainerHigh;
    final isSticker = content?['@type'] == 'messageSticker';
    final senderId = message['sender_id'] as TdObject?;
    final senderKey = (senderId?['user_id'] ?? senderId?['chat_id'] ?? 0) as int;

    final children = <Widget>[];
    if (showSender && !out) {
      children.add(Text(svc.senderName(senderId),
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: peerColor(senderKey))));
    }
    final fwd = message['forward_info'] as TdObject?;
    if (fwd != null) {
      children.add(Text('Переслано от ${_originName(fwd['origin'] as TdObject?)}',
          style: TextStyle(fontSize: 12, color: scheme.primary, fontStyle: FontStyle.italic)));
    }
    if (replyPreview != null) {
      children.add(Container(
        margin: const EdgeInsets.only(top: 2, bottom: 4),
        padding: const EdgeInsets.only(left: 6),
        decoration: BoxDecoration(border: Border(left: BorderSide(color: scheme.primary, width: 2))),
        child: Text(replyPreview!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
      ));
    }
    children.addAll(_content(context, content));

    final footer = <String>[
      if (isDeleted) s.deletedMark,
      if (isEdited || (message['edit_date'] as int? ?? 0) != 0) s.editedMark,
      messageTime(message['date'] as int),
    ].join(' ');
    final sending = message['sending_state'] as TdObject?;
    final lastRead = chat['last_read_outbox_message_id'] as int? ?? 0;
    final tick = !out
        ? ''
        : sending?['@type'] == 'messageSendingStatePending'
            ? ' 🕓'
            : sending?['@type'] == 'messageSendingStateFailed'
                ? ' ⚠️'
                : (message['id'] as int) <= lastRead
                    ? ' ✓✓'
                    : ' ✓';
    children.add(Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text('$footer$tick', style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
      ),
    ));

    Widget bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
      margin: EdgeInsets.fromLTRB(out ? 48 : 8, 2, out ? 8 : 48, 2),
      padding: isSticker ? EdgeInsets.zero : const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: isSticker
          ? null
          : BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(16),
              border: isDeleted ? Border.all(color: Colors.redAccent.withValues(alpha: 0.6)) : null,
            ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
    );
    if (isDeleted && s.semiTransparentDeletedMessages) bubble = Opacity(opacity: 0.55, child: bubble);

    return GestureDetector(
      onLongPress: onLongPress,
      child: Align(alignment: out ? Alignment.centerRight : Alignment.centerLeft, child: bubble),
    );
  }

  String _originName(TdObject? origin) {
    final svc = TdService.instance;
    return switch (origin?['@type']) {
      'messageOriginUser' => svc.userName(origin!['sender_user_id'] as int),
      'messageOriginHiddenUser' => origin!['sender_name'] as String? ?? 'скрыто',
      'messageOriginChat' || 'messageOriginChannel' =>
        svc.chats[origin!['sender_chat_id'] ?? origin['chat_id']]?['title'] as String? ?? 'канал',
      _ => '?',
    };
  }

  List<Widget> _content(BuildContext context, TdObject? content) {
    final text = contentText(content);
    final textWidget = text.isEmpty ? null : SelectableText(text, style: const TextStyle(fontSize: 16));
    final hint = Theme.of(context).hintColor;

    switch (content?['@type']) {
      case 'messageText':
        return [textWidget ?? const SizedBox()];
      case 'messagePhoto':
        final sizes = ((content!['photo'] as TdObject)['sizes'] as List).cast<TdObject>();
        if (sizes.isEmpty) return [if (textWidget != null) textWidget];
        final best = sizes.lastWhere((s) => (s['width'] as int) <= 1280, orElse: () => sizes.last);
        final w = (best['width'] as int).toDouble();
        final h = (best['height'] as int).toDouble();
        return [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: h == 0 ? 1 : (w / h).clamp(0.5, 2.0),
              child: TdImage(best['photo'] as TdObject),
            ),
          ),
          if (textWidget != null) Padding(padding: const EdgeInsets.only(top: 4), child: textWidget),
        ];
      case 'messageSticker':
        final sticker = content!['sticker'] as TdObject;
        final format = (sticker['format'] as TdObject?)?['@type'];
        final thumb = (sticker['thumbnail'] as TdObject?)?['file'] as TdObject?;
        final file = format == 'stickerFormatWebp' ? sticker['sticker'] as TdObject : thumb;
        if (file == null) return [Text(sticker['emoji'] as String? ?? '🙂', style: const TextStyle(fontSize: 64))];
        return [
          SizedBox(
            width: 160,
            height: 160,
            child: TdImage(file, fit: BoxFit.contain,
                placeholder: Center(child: Text(sticker['emoji'] as String? ?? '', style: const TextStyle(fontSize: 64)))),
          ),
        ];
      case 'messageVideo':
      case 'messageAnimation':
      case 'messageVideoNote':
        final media = (content!['video'] ?? content['animation'] ?? content['video_note']) as TdObject;
        final thumb = (media['thumbnail'] as TdObject?)?['file'] as TdObject?;
        final dur = media['duration'] as int? ?? 0;
        return [
          ClipRRect(
            borderRadius: BorderRadius.circular(content['@type'] == 'messageVideoNote' ? 200 : 10),
            child: SizedBox(
              width: 220,
              height: content['@type'] == 'messageVideoNote' ? 220 : 160,
              child: Stack(fit: StackFit.expand, children: [
                if (thumb != null) TdImage(thumb) else const ColoredBox(color: Colors.black26),
                const Center(child: Icon(Icons.play_circle_fill, size: 48, color: Colors.white70)),
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: Text(content['@type'] == 'messageAnimation' ? 'GIF' : duration(dur),
                      style: const TextStyle(color: Colors.white, shadows: [Shadow(blurRadius: 4)])),
                ),
              ]),
            ),
          ),
          if (textWidget != null) Padding(padding: const EdgeInsets.only(top: 4), child: textWidget),
        ];
      case 'messageVoiceNote':
        final dur = (content!['voice_note'] as TdObject)['duration'] as int? ?? 0;
        final recognized = ((content['voice_note'] as TdObject)['speech_recognition_result'] as TdObject?)?['text'] as String?;
        return [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.mic, size: 28),
            const SizedBox(width: 6),
            Text('Голосовое ${duration(dur)}'),
          ]),
          if (recognized != null) Text(recognized, style: TextStyle(color: hint)),
          if (textWidget != null) textWidget,
        ];
      case 'messageDocument':
      case 'messageAudio':
        final doc = (content!['document'] ?? content['audio']) as TdObject;
        final file = (doc['document'] ?? doc['audio']) as TdObject?;
        final size = file?['size'] as int? ?? 0;
        final name = doc['file_name'] as String? ?? doc['title'] as String? ?? 'Файл';
        return [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(content['@type'] == 'messageAudio' ? Icons.music_note : Icons.insert_drive_file, size: 32),
            const SizedBox(width: 8),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(_size(size), style: TextStyle(fontSize: 12, color: hint)),
              ]),
            ),
          ]),
          if (textWidget != null) textWidget,
        ];
      default:
        return [Text(contentPreview(content), style: const TextStyle(fontSize: 16))];
    }
  }

  static String _size(int b) {
    if (b < 1024) return '$b Б';
    if (b < 1 << 20) return '${(b / 1024).toStringAsFixed(1)} КБ';
    return '${(b / (1 << 20)).toStringAsFixed(1)} МБ';
  }
}
