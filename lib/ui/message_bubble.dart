import 'package:flutter/material.dart';

import '../ayu/ayu_settings.dart';
import '../td/td_client.dart';
import '../td/td_service.dart';
import 'ayu_theme.dart';
import 'format.dart';
import 'widgets.dart';

/// Плашка по центру чата (дата, служебное сообщение) — ChatActionCell.
class ServicePill extends StatelessWidget {
  const ServicePill(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 40),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(color: context.ayu.serviceBg, borderRadius: BorderRadius.circular(12)),
          child: Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500)),
        ),
      );
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.chat,
    required this.isDeleted,
    required this.isEdited,
    required this.showSender,
    this.tail = true,
    this.replyTo,
    this.onLongPress,
  });

  final TdObject message;
  final TdObject chat;
  final bool isDeleted;
  final bool isEdited;
  final bool showSender;
  final bool tail;
  final TdObject? replyTo;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    final s = AyuSettings.instance;
    final svc = TdService.instance;
    final out = message['is_outgoing'] == true &&
        !((chat['type'] as TdObject?)?['@type'] == 'chatTypeSupergroup' && (chat['type'] as TdObject)['is_channel'] == true);
    final content = message['content'] as TdObject?;

    if (isServiceMessage(content)) {
      final who = svc.senderName(message['sender_id'] as TdObject?);
      return GestureDetector(onLongPress: onLongPress, child: ServicePill('$who: ${contentPreview(content)}'));
    }

    final type = content?['@type'];
    final isSticker = type == 'messageSticker' || type == 'messageVideoNote';
    final isMedia = type == 'messagePhoto' || type == 'messageVideo' || type == 'messageAnimation';
    final hasText = contentText(content).isNotEmpty;
    final timeColor = out ? c.outTime : c.inTime;
    final senderId = message['sender_id'] as TdObject?;
    final senderKey = (senderId?['user_id'] ?? senderId?['chat_id'] ?? 0) as int;

    // --- время и галочки ---
    final sending = message['sending_state'] as TdObject?;
    final lastRead = chat['last_read_outbox_message_id'] as int? ?? 0;
    final views = (message['interaction_info'] as TdObject?)?['view_count'] as int?;
    final marks = [
      if (isDeleted) s.deletedMark,
      if (isEdited || (message['edit_date'] as int? ?? 0) != 0) s.editedMark,
    ].join(' ');
    Widget timeRow(Color color) => Row(mainAxisSize: MainAxisSize.min, children: [
          if (views != null && !out) ...[
            Icon(Icons.visibility_outlined, size: 13, color: color),
            const SizedBox(width: 2),
            Text(_compact(views), style: TextStyle(fontSize: 12, color: color)),
            const SizedBox(width: 6),
          ],
          if (marks.isNotEmpty) Text('$marks ', style: TextStyle(fontSize: 12, color: color, fontStyle: FontStyle.italic)),
          Text(messageTime(message['date'] as int), style: TextStyle(fontSize: 12, color: color)),
          if (out) ...[
            const SizedBox(width: 3),
            if (sending?['@type'] == 'messageSendingStatePending')
              Icon(Icons.schedule, size: 14, color: color)
            else if (sending?['@type'] == 'messageSendingStateFailed')
              const Icon(Icons.error, size: 14, color: Colors.redAccent)
            else
              Icon((message['id'] as int) <= lastRead ? Icons.done_all : Icons.done,
                  size: 16, color: out ? c.outCheck : color),
          ],
        ]);
    // Ширина места под время, чтобы текст обтекал его, как в Telegram.
    final reserve = 48.0 + (out ? 20 : 0) + (marks.isEmpty ? 0 : 8.0 * marks.length) + (views != null && !out ? 50 : 0);

    // --- содержимое ---
    final children = <Widget>[];
    final pad = isMedia && !hasText ? EdgeInsets.zero : const EdgeInsets.fromLTRB(9, 6, 9, 0);

    if (showSender && !out && !isSticker) {
      children.add(Padding(
        padding: EdgeInsets.fromLTRB(isMedia ? 9 : 0, isMedia ? 6 : 0, 0, 2),
        child: Text(svc.senderName(senderId),
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: peerColor(senderKey))),
      ));
    }
    final fwd = message['forward_info'] as TdObject?;
    if (fwd != null) {
      children.add(Padding(
        padding: EdgeInsets.fromLTRB(isMedia ? 9 : 0, isMedia ? 6 : 0, 0, 3),
        child: Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Переслано от\n'),
            TextSpan(text: _originName(fwd['origin'] as TdObject?), style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
          style: TextStyle(fontSize: 14, color: out ? c.outForwardName : c.inForwardName),
        ),
      ));
    }
    if (replyTo != null || (message['reply_to'] as TdObject?)?['@type'] == 'messageReplyToMessage') {
      final r = replyTo;
      children.add(Container(
        margin: EdgeInsets.fromLTRB(isMedia ? 9 : 0, isMedia ? 6 : 2, isMedia ? 9 : 0, 4),
        padding: const EdgeInsets.fromLTRB(8, 2, 6, 2),
        decoration: BoxDecoration(
          color: (out ? c.outReplyLine : c.inReplyLine).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border(left: BorderSide(color: out ? c.outReplyLine : c.inReplyLine, width: 3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r == null ? 'Сообщение' : svc.senderName(r['sender_id'] as TdObject?),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: out ? c.outReplyName : c.inReplyName)),
          Text(r == null ? '…' : contentPreview(r['content'] as TdObject?).replaceAll('\n', ' '),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: out ? c.textOut : c.textIn)),
        ]),
      ));
    }

    final textColor = out ? c.textOut : c.textIn;
    final textSpan = hasText
        ? Text.rich(
            TextSpan(children: [
              TextSpan(text: contentText(content)),
              WidgetSpan(child: SizedBox(width: reserve, height: 14)),
            ]),
            style: TextStyle(fontSize: 16, color: textColor, height: 1.25),
          )
        : null;

    children.addAll(_media(context, content, textColor));
    if (textSpan != null) {
      children.add(Padding(padding: EdgeInsets.fromLTRB(isMedia ? 9 : 0, isMedia ? 6 : 0, isMedia ? 9 : 0, 0), child: textSpan));
    } else if (!isMedia && !isSticker) {
      children.add(SizedBox(width: reserve, height: 16));
    }

    // Время: поверх медиа — в тёмной плашке, иначе в правом нижнем углу пузыря.
    final onMedia = (isMedia && !hasText) || isSticker;
    final time = Positioned(
      right: onMedia ? 6 : 8,
      bottom: onMedia ? 6 : 4,
      child: onMedia
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(10)),
              child: timeRow(Colors.white),
            )
          : timeRow(timeColor),
    );

    final body = Stack(children: [
      Padding(
        padding: onMedia ? EdgeInsets.zero : pad.copyWith(bottom: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
      ),
      time,
    ]);

    final maxW = MediaQuery.sizeOf(context).width * (isMedia ? 0.72 : 0.8);
    Widget bubble = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW, minWidth: 60),
      child: isSticker
          ? body
          : CustomPaint(
              painter: _BubblePainter(color: out ? c.outBubble : c.inBubble, out: out, tail: tail),
              child: ClipRRect(borderRadius: BorderRadius.circular(_BubblePainter.radius), child: body),
            ),
    );
    if (isDeleted && s.semiTransparentDeletedMessages) bubble = Opacity(opacity: 0.55, child: bubble);

    return GestureDetector(
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.fromLTRB(out ? 56 : 8, tail ? 2 : 1, out ? 8 : 56, tail ? 4 : 1),
        child: Align(alignment: out ? Alignment.centerRight : Alignment.centerLeft, child: bubble),
      ),
    );
  }

  static String _compact(int n) => n < 1000 ? '$n' : n < 1000000 ? '${(n / 1000).toStringAsFixed(1)}K' : '${(n / 1e6).toStringAsFixed(1)}M';

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

  List<Widget> _media(BuildContext context, TdObject? content, Color textColor) {
    final c = context.ayu;
    final out = message['is_outgoing'] == true;
    switch (content?['@type']) {
      case 'messagePhoto':
        final sizes = ((content!['photo'] as TdObject)['sizes'] as List).cast<TdObject>();
        if (sizes.isEmpty) return [];
        final best = sizes.lastWhere((s) => (s['width'] as int) <= 1280, orElse: () => sizes.last);
        final w = (best['width'] as int).toDouble();
        final h = (best['height'] as int).toDouble();
        return [
          AspectRatio(aspectRatio: h == 0 ? 1 : (w / h).clamp(0.6, 1.8), child: TdImage(best['photo'] as TdObject)),
        ];
      case 'messageSticker':
        final sticker = content!['sticker'] as TdObject;
        final format = (sticker['format'] as TdObject?)?['@type'];
        final thumb = (sticker['thumbnail'] as TdObject?)?['file'] as TdObject?;
        final file = format == 'stickerFormatWebp' ? sticker['sticker'] as TdObject : thumb;
        final emoji = Text(sticker['emoji'] as String? ?? '🙂', style: const TextStyle(fontSize: 90));
        return [
          SizedBox(
            width: 180,
            height: 180,
            child: file == null ? Center(child: emoji) : TdImage(file, fit: BoxFit.contain, placeholder: Center(child: emoji)),
          ),
        ];
      case 'messageVideo':
      case 'messageAnimation':
      case 'messageVideoNote':
        final note = content!['@type'] == 'messageVideoNote';
        final media = (content['video'] ?? content['animation'] ?? content['video_note']) as TdObject;
        final thumb = (media['thumbnail'] as TdObject?)?['file'] as TdObject?;
        final dur = media['duration'] as int? ?? 0;
        final w = (media['width'] as int? ?? 16).toDouble();
        final h = (media['height'] as int? ?? 9).toDouble();
        final player = Stack(fit: StackFit.expand, children: [
          if (thumb != null) TdImage(thumb) else const ColoredBox(color: Colors.black26),
          Center(
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 30),
            ),
          ),
          Positioned(
            left: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8)),
              child: Text(content['@type'] == 'messageAnimation' ? 'GIF' : duration(dur),
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ),
        ]);
        if (note) return [ClipOval(child: SizedBox(width: 200, height: 200, child: player))];
        return [AspectRatio(aspectRatio: h == 0 ? 16 / 9 : (w / h).clamp(0.6, 1.8), child: player)];
      case 'messageVoiceNote':
        final dur = (content!['voice_note'] as TdObject)['duration'] as int? ?? 0;
        return [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: out ? c.outTime : c.blueText, shape: BoxShape.circle),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                for (var i = 0; i < 24; i++)
                  Container(
                    width: 2.5,
                    height: 4.0 + ((i * 7 + dur) % 13),
                    margin: const EdgeInsets.only(right: 1.5),
                    decoration: BoxDecoration(
                      color: (out ? c.outTime : c.blueText).withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
              ]),
              const SizedBox(height: 3),
              Text(duration(dur), style: TextStyle(fontSize: 13, color: out ? c.outTime : c.inTime)),
            ]),
          ]),
          const SizedBox(height: 14),
        ];
      case 'messageDocument':
      case 'messageAudio':
        final doc = (content!['document'] ?? content['audio']) as TdObject;
        final file = (doc['document'] ?? doc['audio']) as TdObject?;
        final size = file?['size'] as int? ?? 0;
        final name = doc['file_name'] as String? ?? doc['title'] as String? ?? 'Файл';
        return [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: out ? c.outTime : c.blueText, shape: BoxShape.circle),
              child: Icon(content['@type'] == 'messageAudio' ? Icons.music_note : Icons.insert_drive_file,
                  color: Colors.white, size: 24),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textColor)),
                const SizedBox(height: 2),
                Text(_size(size), style: TextStyle(fontSize: 13, color: out ? c.outTime : c.inTime)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
        ];
      case 'messageText':
      case null:
        return [];
      default:
        if (contentText(content).isNotEmpty) return [];
        return [Text(contentPreview(content), style: TextStyle(fontSize: 16, color: textColor))];
    }
  }

  static String _size(int b) {
    if (b < 1024) return '$b B';
    if (b < 1 << 20) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
  }
}

/// Пузырь с «хвостиком» снизу, как у Telegram Android.
class _BubblePainter extends CustomPainter {
  _BubblePainter({required this.color, required this.out, required this.tail});
  final Color color;
  final bool out;
  final bool tail;

  static const radius = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    const r = radius;
    final small = tail ? 4.0 : r;
    final path = Path();
    if (out) {
      path.addRRect(RRect.fromLTRBAndCorners(0, 0, w, h,
          topLeft: const Radius.circular(r), topRight: const Radius.circular(r),
          bottomLeft: const Radius.circular(r), bottomRight: Radius.circular(small)));
      if (tail) {
        path.moveTo(w - 6, h - 12);
        path.quadraticBezierTo(w - 4, h - 2, w + 7, h);
        path.lineTo(w - 6, h);
        path.close();
      }
    } else {
      path.addRRect(RRect.fromLTRBAndCorners(0, 0, w, h,
          topLeft: const Radius.circular(r), topRight: const Radius.circular(r),
          bottomLeft: Radius.circular(small), bottomRight: const Radius.circular(r)));
      if (tail) {
        path.moveTo(6, h - 12);
        path.quadraticBezierTo(4, h - 2, -7, h);
        path.lineTo(6, h);
        path.close();
      }
    }
    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.4), 0.8, false);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BubblePainter old) => old.color != color || old.out != out || old.tail != tail;
}
