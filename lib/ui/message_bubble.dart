import 'package:flutter/material.dart';

import '../ayu/ayu_settings.dart';
import '../td/td_client.dart';
import '../td/td_service.dart';
import 'ayu_theme.dart';
import 'format.dart';
import 'widgets.dart';

/// Плашка по центру истории (дата, служебное сообщение).
class ServicePill extends StatelessWidget {
  const ServicePill(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 40),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(color: context.ayu.msgServiceBg, borderRadius: BorderRadius.circular(12)),
          child: Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600)),
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
    this.avatarSlot = false,
    this.replyTo,
    this.onLongPress,
  });

  final TdObject message;
  final TdObject chat;
  final bool isDeleted;
  final bool isEdited;
  final bool showSender;
  final bool tail;

  /// В группах слева от входящих оставляем место под аватарку (сама аватарка — у последнего в серии).
  final bool avatarSlot;
  final TdObject? replyTo;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    final s = AyuSettings.instance;
    final svc = TdService.instance;
    final channel = svc.isChannel(chat);
    final out = message['is_outgoing'] == true && !channel;
    final content = message['content'] as TdObject?;

    if (isServiceMessage(content)) {
      final who = svc.senderName(message['sender_id'] as TdObject?);
      return GestureDetector(onLongPress: onLongPress, child: ServicePill('$who: ${contentPreview(content)}'));
    }

    final type = content?['@type'];
    final isSticker = type == 'messageSticker' || type == 'messageVideoNote';
    final isMedia = type == 'messagePhoto' || type == 'messageVideo' || type == 'messageAnimation';
    final hasText = contentText(content).isNotEmpty;
    final timeColor = out ? c.msgOutDateFg : c.msgInDateFg;
    final senderId = message['sender_id'] as TdObject?;
    final senderKey = (senderId?['user_id'] ?? senderId?['chat_id'] ?? 0) as int;
    final reactions = _reactions(message);

    // --- время, просмотры, галочки ---
    final sending = message['sending_state'] as TdObject?;
    final lastRead = chat['last_read_outbox_message_id'] as int? ?? 0;
    final views = (message['interaction_info'] as TdObject?)?['view_count'] as int?;
    final marks = [
      if (isDeleted) s.deletedMark,
      if (isEdited || (message['edit_date'] as int? ?? 0) != 0) s.editedMark,
    ].join(' ');
    Widget timeRow(Color color) => Row(mainAxisSize: MainAxisSize.min, children: [
          if (views != null && channel) ...[
            Icon(Icons.visibility_outlined, size: 13, color: color),
            const SizedBox(width: 3),
            Text(compactCount(views), style: TextStyle(fontSize: 12, color: color)),
            const SizedBox(width: 6),
          ],
          if (marks.isNotEmpty) Text('$marks ', style: TextStyle(fontSize: 12, color: color, fontStyle: FontStyle.italic)),
          Text(messageTime(message['date'] as int), style: TextStyle(fontSize: 12, color: color)),
          if (out) ...[
            const SizedBox(width: 3),
            if (sending?['@type'] == 'messageSendingStatePending')
              Icon(Icons.schedule, size: 13, color: color)
            else if (sending?['@type'] == 'messageSendingStateFailed')
              Icon(Icons.error, size: 14, color: c.attentionFg)
            else
              Icon((message['id'] as int) <= lastRead ? Icons.done_all : Icons.done, size: 15, color: c.historyOutIconFg),
          ],
        ]);
    final reserve = 42.0 + (out ? 20 : 0) + (marks.isEmpty ? 0 : 9.0 * marks.length) + (views != null && channel ? 52 : 0);

    // --- содержимое ---
    final children = <Widget>[];
    final inset = EdgeInsets.fromLTRB(isMedia ? 10 : 0, isMedia ? 7 : 0, isMedia ? 10 : 0, 0);

    if ((showSender || channel) && !out && !isSticker) {
      final name = channel ? chat['title'] as String? ?? '' : svc.senderName(senderId);
      children.add(Padding(
        padding: inset.copyWith(bottom: 2),
        child: Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: peerColor(context, channel ? chat['id'] as int : senderKey))),
      ));
    }
    final fwd = message['forward_info'] as TdObject?;
    if (fwd != null) {
      children.add(Padding(
        padding: inset.copyWith(bottom: 3),
        child: Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Переслано от '),
            TextSpan(text: _originName(fwd['origin'] as TdObject?), style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
          style: TextStyle(fontSize: 13.5, color: out ? c.msgOutServiceFg : c.msgInServiceFg),
        ),
      ));
    }
    if ((message['reply_to'] as TdObject?)?['@type'] == 'messageReplyToMessage') {
      final r = replyTo;
      final rKey = r == null ? 0 : (((r['sender_id'] as TdObject?)?['user_id'] ?? (r['sender_id'] as TdObject?)?['chat_id'] ?? 0) as int);
      final barColor = r == null || out ? (out ? c.msgOutReplyBarColor : c.msgInReplyBarColor) : peerColor(context, rKey);
      children.add(Container(
        margin: inset.copyWith(bottom: 4, top: isMedia ? 7 : 2),
        padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
        decoration: BoxDecoration(
          color: barColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(5),
          border: Border(left: BorderSide(color: barColor, width: 3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r == null ? 'Сообщение' : svc.senderName(r['sender_id'] as TdObject?),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: barColor)),
          Text(r == null ? '…' : contentPreview(r['content'] as TdObject?).replaceAll('\n', ' '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, color: out ? c.historyTextOutFg : c.historyTextInFg)),
        ]),
      ));
    }

    final textColor = out ? c.historyTextOutFg : c.historyTextInFg;
    children.addAll(_media(context, content, textColor, out));
    if (hasText) {
      children.add(Padding(
        padding: inset,
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: contentText(content)),
            if (reactions.isEmpty) WidgetSpan(child: SizedBox(width: reserve, height: 12)),
          ]),
          style: TextStyle(fontSize: 15, color: textColor, height: 1.3),
        ),
      ));
    } else if (!isMedia && !isSticker && reactions.isEmpty) {
      children.add(SizedBox(width: reserve, height: 14));
    }
    if (reactions.isNotEmpty) {
      children.add(Padding(
        padding: EdgeInsets.fromLTRB(isMedia ? 10 : 0, 6, reserve, isMedia ? 8 : 0),
        child: Wrap(spacing: 5, runSpacing: 5, children: [
          for (final r in reactions)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: r.chosen
                    ? (out ? c.historyOutIconFg : c.windowActiveTextFg)
                    : (out ? c.msgOutReplyBarColor : c.msgInReplyBarColor).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('${r.emoji} ${compactCount(r.count)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: r.chosen ? c.windowBg : (out ? c.msgOutServiceFg : c.msgInServiceFg),
                  )),
            ),
        ]),
      ));
    }

    final onMedia = (isMedia && !hasText && reactions.isEmpty) || isSticker;
    final time = Positioned(
      right: onMedia ? 6 : 9,
      bottom: onMedia ? 6 : 5,
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
        padding: onMedia
            ? EdgeInsets.zero
            : isMedia
                ? const EdgeInsets.only(bottom: 22)
                : const EdgeInsets.fromLTRB(11, 7, 11, 7),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
      ),
      time,
    ]);

    final screen = MediaQuery.sizeOf(context).width;
    final maxW = (screen - (avatarSlot ? 44 : 0)) * (isMedia ? 0.78 : 0.82);
    Widget bubble = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW, minWidth: 64),
      child: isSticker
          ? body
          : CustomPaint(
              painter: _BubblePainter(color: out ? c.msgOutBg : c.msgInBg, out: out, tail: tail),
              child: ClipRRect(borderRadius: BorderRadius.circular(_BubblePainter.radius), child: body),
            ),
    );
    if (isDeleted && s.semiTransparentDeletedMessages) bubble = Opacity(opacity: 0.55, child: bubble);

    return GestureDetector(
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.fromLTRB(out ? 50 : (avatarSlot ? 0 : 10), 1, out ? 10 : 40, tail ? 6 : 1),
        child: Align(alignment: out ? Alignment.centerRight : Alignment.centerLeft, child: bubble),
      ),
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

  static List<({String emoji, int count, bool chosen})> _reactions(TdObject m) {
    final list = ((m['interaction_info'] as TdObject?)?['reactions'] as TdObject?)?['reactions'] as List?;
    if (list == null) return const [];
    return [
      for (final r in list.cast<TdObject>())
        (
          emoji: ((r['type'] as TdObject?)?['emoji'] as String?) ??
              ((r['type'] as TdObject?)?['@type'] == 'reactionTypePaid' ? '⭐' : '❤'),
          count: r['total_count'] as int? ?? 0,
          chosen: r['is_chosen'] == true,
        ),
    ];
  }

  List<Widget> _media(BuildContext context, TdObject? content, Color textColor, bool out) {
    final c = context.ayu;
    final accent = out ? c.msgFileOutBg : c.msgFileInBg;
    final sub = out ? c.msgOutDateFg : c.msgInDateFg;
    switch (content?['@type']) {
      case 'messagePhoto':
        final sizes = ((content!['photo'] as TdObject)['sizes'] as List).cast<TdObject>();
        if (sizes.isEmpty) return [];
        final best = sizes.lastWhere((s) => (s['width'] as int) <= 1280, orElse: () => sizes.last);
        final w = (best['width'] as int).toDouble();
        final h = (best['height'] as int).toDouble();
        return [AspectRatio(aspectRatio: h == 0 ? 1 : (w / h).clamp(0.6, 1.8), child: TdImage(best['photo'] as TdObject))];
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
              width: 46,
              height: 46,
              decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 30),
            ),
          ),
          Positioned(
            left: 7,
            top: 7,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                for (var i = 0; i < 26; i++)
                  Container(
                    width: 2.5,
                    height: 4.0 + ((i * 7 + dur) % 13),
                    margin: const EdgeInsets.only(right: 1.5),
                    decoration: BoxDecoration(color: accent.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(1)),
                  ),
              ]),
              const SizedBox(height: 3),
              Text(duration(dur), style: TextStyle(fontSize: 12.5, color: sub)),
            ]),
          ]),
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
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              child: Icon(content['@type'] == 'messageAudio' ? Icons.music_note : Icons.insert_drive_file_outlined,
                  color: Colors.white, size: 22),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
                const SizedBox(height: 2),
                Text(_size(size), style: TextStyle(fontSize: 12.5, color: sub)),
              ]),
            ),
          ]),
        ];
      case 'messageText':
      case null:
        return [];
      default:
        if (contentText(content).isNotEmpty) return [];
        return [Text(contentPreview(content), style: TextStyle(fontSize: 15, color: textColor))];
    }
  }

  static String _size(int b) {
    if (b < 1024) return '$b B';
    if (b < 1 << 20) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
  }
}

/// 5400 → «5,4K», как в Telegram.
String compactCount(int n) {
  String f(double v) => v.toStringAsFixed(v < 10 ? 1 : 0).replaceAll('.0', '').replaceAll('.', ',');
  if (n < 1000) return '$n';
  if (n < 1000000) return '${f(n / 1000)}K';
  return '${f(n / 1e6)}M';
}

/// Пузырь tdesktop: скругление и маленький «хвостик» у последнего сообщения серии.
class _BubblePainter extends CustomPainter {
  _BubblePainter({required this.color, required this.out, required this.tail});
  final Color color;
  final bool out;
  final bool tail;

  static const radius = 14.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    const r = radius;
    final small = tail ? 0.0 : r;
    final path = Path();
    if (out) {
      path.addRRect(RRect.fromLTRBAndCorners(0, 0, w, h,
          topLeft: const Radius.circular(r), topRight: const Radius.circular(r),
          bottomLeft: const Radius.circular(r), bottomRight: Radius.circular(small)));
      if (tail) {
        path.moveTo(w, h - 10);
        path.quadraticBezierTo(w + 1, h - 1, w + 7, h);
        path.lineTo(w, h);
        path.close();
      }
    } else {
      path.addRRect(RRect.fromLTRBAndCorners(0, 0, w, h,
          topLeft: const Radius.circular(r), topRight: const Radius.circular(r),
          bottomLeft: Radius.circular(small), bottomRight: const Radius.circular(r)));
      if (tail) {
        path.moveTo(0, h - 10);
        path.quadraticBezierTo(-1, h - 1, -7, h);
        path.lineTo(0, h);
        path.close();
      }
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BubblePainter old) => old.color != color || old.out != out || old.tail != tail;
}
