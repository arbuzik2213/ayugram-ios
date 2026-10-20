import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ayu/ayu_settings.dart';
import '../td/td_client.dart';
import '../td/td_service.dart';
import 'ayu_theme.dart';
import 'format.dart';
import 'links.dart';
import 'voice.dart';
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
              style: const TextStyle(fontSize: 13.5, color: Colors.white, fontWeight: FontWeight.w600)),
        ),
      );
}

/// Сообщение в стиле Telegram для iOS (ChatMessageBubbleItemNode).
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
    this.onComments,
    this.onForward,
  });

  final TdObject message;
  final TdObject chat;
  final bool isDeleted;
  final bool isEdited;
  final bool showSender;
  final bool tail;
  final bool avatarSlot;
  final TdObject? replyTo;
  final VoidCallback? onLongPress;
  final VoidCallback? onComments;
  final VoidCallback? onForward;

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
    final formatted = (content?['text'] ?? content?['caption']) as TdObject?;
    final hasText = contentText(content).isNotEmpty;
    final timeColor = out ? c.msgOutDateFg : c.msgInDateFg;
    final linkColor = out ? c.historyLinkOutFg : c.historyLinkInFg;
    final textColor = out ? c.historyTextOutFg : c.historyTextInFg;
    final senderId = message['sender_id'] as TdObject?;
    final senderKey = (senderId?['user_id'] ?? senderId?['chat_id'] ?? 0) as int;
    final reactions = _reactions(message);
    final replyInfo = (message['interaction_info'] as TdObject?)?['reply_info'] as TdObject?;
    final comments = channel && replyInfo != null && onComments != null;

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
            Icon(CupertinoIcons.eye, size: 13, color: color),
            const SizedBox(width: 2),
            Text(compactCount(views), style: TextStyle(fontSize: 12, color: color)),
            const SizedBox(width: 5),
          ],
          if (marks.isNotEmpty) Text('$marks ', style: TextStyle(fontSize: 12, color: color)),
          Text(messageTime(message['date'] as int), style: TextStyle(fontSize: 12, color: color)),
          if (out) ...[
            const SizedBox(width: 2),
            if (sending?['@type'] == 'messageSendingStatePending')
              Icon(CupertinoIcons.clock, size: 12, color: color)
            else if (sending?['@type'] == 'messageSendingStateFailed')
              Icon(CupertinoIcons.exclamationmark_circle_fill, size: 14, color: c.attentionFg)
            else
              DoubleCheck(read: (message['id'] as int) <= lastRead, color: c.historyOutIconFg),
          ],
        ]);
    final reserve = 40.0 + (out ? 22 : 0) + (marks.isEmpty ? 0 : 8.0 * marks.length) + (views != null && channel ? 46 : 0);

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
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: peerColor(context, channel ? chat['id'] as int : senderKey),
            )),
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
          style: TextStyle(fontSize: 14, color: out ? c.msgOutServiceFg : c.msgInServiceFg),
        ),
      ));
    }
    if ((message['reply_to'] as TdObject?)?['@type'] == 'messageReplyToMessage') {
      final r = replyTo;
      final rSender = r?['sender_id'] as TdObject?;
      final rKey = (rSender?['user_id'] ?? rSender?['chat_id'] ?? 0) as int;
      final bar = r == null || out ? (out ? c.msgOutReplyBarColor : c.msgInReplyBarColor) : peerColor(context, rKey);
      children.add(Container(
        margin: inset.copyWith(bottom: 5, top: isMedia ? 7 : 2),
        padding: const EdgeInsets.fromLTRB(9, 4, 9, 4),
        decoration: BoxDecoration(
          color: bar.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(6),
          border: Border(left: BorderSide(color: bar, width: 3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r == null ? 'Сообщение' : svc.senderName(rSender),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: bar)),
          Text(r == null ? '…' : contentPreview(r['content'] as TdObject?).replaceAll('\n', ' '),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, color: textColor)),
        ]),
      ));
    }

    children.addAll(_media(context, content, textColor, out));
    if (hasText) {
      children.add(Padding(
        padding: inset,
        child: Text.rich(
          TextSpan(children: [
            ...RichMessageText.spans(context, formatted, linkColor: linkColor, textColor: textColor),
            if (reactions.isEmpty && content?['link_preview'] == null) WidgetSpan(child: SizedBox(width: reserve, height: 12)),
          ]),
          style: TextStyle(fontSize: 17, color: textColor, height: 1.28),
        ),
      ));
    } else if (!isMedia && !isSticker && reactions.isEmpty && type != 'messageVoiceNote') {
      children.add(SizedBox(width: reserve, height: 14));
    }
    final preview = content?['link_preview'] as TdObject?;
    if (preview != null) children.add(_LinkPreview(preview: preview, out: out));
    if (type == 'messageVoiceNote' && reactions.isEmpty) children.add(const SizedBox(height: 14));

    if (reactions.isNotEmpty) {
      children.add(Padding(
        padding: EdgeInsets.fromLTRB(isMedia ? 10 : 0, 6, reserve, isMedia ? 8 : 0),
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final r in reactions)
            Container(
              padding: const EdgeInsets.fromLTRB(7, 4, 9, 4),
              decoration: BoxDecoration(
                color: r.chosen
                    ? (out ? c.historyOutIconFg : c.windowActiveTextFg)
                    : (out ? c.msgOutReplyBarColor : c.windowActiveTextFg).withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(r.emoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 4),
                Text(compactCount(r.count),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: r.chosen ? Colors.white : (out ? c.msgOutServiceFg : c.windowActiveTextFg),
                    )),
              ]),
            ),
        ]),
      ));
    }

    final onMedia = (isMedia && !hasText && reactions.isEmpty) || isSticker;
    final time = Positioned(
      right: onMedia ? 6 : 10,
      bottom: onMedia ? 6 : 6,
      child: onMedia
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(10)),
              child: timeRow(Colors.white),
            )
          : timeRow(timeColor),
    );

    Widget body = Stack(children: [
      Padding(
        padding: onMedia
            ? EdgeInsets.zero
            : isMedia
                ? const EdgeInsets.only(bottom: 24)
                : const EdgeInsets.fromLTRB(12, 7, 12, 7),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
      ),
      time,
    ]);

    if (comments) {
      final count = replyInfo['reply_count'] as int? ?? 0;
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        body,
        Container(height: 0.5, color: c.inputBorderFg),
        InkWell(
          onTap: onComments,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Row(children: [
              Icon(CupertinoIcons.chat_bubble, size: 22, color: c.windowActiveTextFg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  count == 0 ? 'Прокомментировать' : '$count ${plural(count, 'комментарий', 'комментария', 'комментариев')}',
                  style: TextStyle(fontSize: 16, color: c.windowActiveTextFg, fontWeight: FontWeight.w500),
                ),
              ),
              Icon(CupertinoIcons.chevron_right, size: 18, color: c.windowActiveTextFg),
            ]),
          ),
        ),
      ]);
    }

    final screen = MediaQuery.sizeOf(context).width;
    final maxW = (screen - (avatarSlot ? 44 : 0) - (onForward != null ? 44 : 0)) * (isMedia || comments ? 0.86 : 0.8);
    Widget bubble = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW, minWidth: comments ? maxW : 70),
      child: isSticker
          ? body
          : CustomPaint(
              painter: _BubblePainter(color: out ? c.msgOutBg : c.msgInBg, out: out, tail: tail),
              child: ClipRRect(borderRadius: BorderRadius.circular(_BubblePainter.radius), child: body),
            ),
    );
    if (isDeleted && s.semiTransparentDeletedMessages) bubble = Opacity(opacity: 0.55, child: bubble);

    final row = Row(
      mainAxisAlignment: out ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(child: bubble),
        if (onForward != null)
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 4),
            child: GestureDetector(
              onTap: onForward,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: c.msgServiceBg, shape: BoxShape.circle),
                child: const Icon(CupertinoIcons.arrowshape_turn_up_right_fill, color: Colors.white, size: 17),
              ),
            ),
          ),
      ],
    );

    return GestureDetector(
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.fromLTRB(out ? 50 : (avatarSlot ? 0 : 10), 1, out ? 10 : 30, tail ? 6 : 1),
        child: row,
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
              ((r['type'] as TdObject?)?['@type'] == 'reactionTypePaid' ? '⭐' : '❤️'),
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
        final size = ((media['video'] ?? media['animation']) as TdObject?)?['size'] as int?;
        final player = Stack(fit: StackFit.expand, children: [
          if (thumb != null) TdImage(thumb) else const ColoredBox(color: Colors.black26),
          Center(
            child: Container(
              width: 50,
              height: 50,
              decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
              child: const Icon(CupertinoIcons.play_fill, color: Colors.white, size: 24),
            ),
          ),
          Positioned(
            left: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(9)),
              child: Text(
                content['@type'] == 'messageAnimation'
                    ? 'GIF'
                    : '${duration(dur)}${size != null ? '\n${(size / (1 << 20)).toStringAsFixed(1)} МБ' : ''}',
                style: const TextStyle(color: Colors.white, fontSize: 12.5, height: 1.25),
              ),
            ),
          ),
        ]);
        if (note) return [ClipOval(child: SizedBox(width: 220, height: 220, child: player))];
        return [AspectRatio(aspectRatio: h == 0 ? 16 / 9 : (w / h).clamp(0.6, 1.8), child: player)];
      case 'messageVoiceNote':
        return [
          VoiceNoteView(
            voice: content!['voice_note'] as TdObject,
            accent: accent,
            inactive: accent.withValues(alpha: 0.35),
            timeColor: sub,
          ),
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
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              child: Icon(content['@type'] == 'messageAudio' ? CupertinoIcons.music_note_2 : CupertinoIcons.doc_fill,
                  color: Colors.white, size: 22),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textColor)),
                const SizedBox(height: 2),
                Text(_size(size), style: TextStyle(fontSize: 13, color: sub)),
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
        return [Text(contentPreview(content), style: TextStyle(fontSize: 17, color: textColor))];
    }
  }

  static String _size(int b) {
    if (b < 1024) return '$b Б';
    if (b < 1 << 20) return '${(b / 1024).toStringAsFixed(1)} КБ';
    return '${(b / (1 << 20)).toStringAsFixed(1)} МБ';
  }
}

/// Превью ссылки (linkPreview TDLib).
class _LinkPreview extends StatelessWidget {
  const _LinkPreview({required this.preview, required this.out});
  final TdObject preview;
  final bool out;

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    final bar = out ? c.msgOutReplyBarColor : c.msgInReplyBarColor;
    final textColor = out ? c.historyTextOutFg : c.historyTextInFg;
    final type = preview['type'] as TdObject?;
    final typeName = type?['@type'] as String? ?? '';
    final site = preview['site_name'] as String? ?? '';
    final title = preview['title'] as String? ?? '';
    final desc = preview['description'] as TdObject?;
    final url = preview['url'] as String? ?? '';
    final isChat = typeName.contains('Chat') || typeName.contains('Channel') || typeName.contains('Supergroup');

    TdObject? thumbFile;
    final photo = (type?['photo'] ?? type?['chat_photo']) as TdObject?;
    final sizes = (photo?['sizes'] as List?)?.cast<TdObject>();
    if (sizes != null && sizes.isNotEmpty) thumbFile = (sizes.first['photo'] ?? sizes.first['file']) as TdObject?;
    thumbFile ??= (photo?['small']) as TdObject?;

    return GestureDetector(
      onTap: () => Links.open(context, url),
      child: Container(
        margin: const EdgeInsets.only(top: 6, bottom: 2),
        decoration: BoxDecoration(
          color: bar.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(7),
          border: Border(left: BorderSide(color: bar, width: 3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 8, 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (site.isNotEmpty) Text(site, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: bar)),
                  if (title.isNotEmpty) Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textColor)),
                  if (desc != null && (desc['text'] as String? ?? '').isNotEmpty)
                    Text.rich(
                      TextSpan(
                        children: RichMessageText.spans(context, desc,
                            linkColor: out ? c.historyLinkOutFg : c.historyLinkInFg, textColor: textColor),
                      ),
                      maxLines: 8,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, color: textColor, height: 1.25),
                    ),
                ]),
              ),
              if (thumbFile != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: TdImage(thumbFile, width: 54, height: 54),
                  ),
                ),
            ]),
          ),
          if (isChat) ...[
            Container(height: 0.5, color: bar.withValues(alpha: 0.4)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Text(typeName.contains('Channel') || (type?['type'] as TdObject?)?['is_channel'] == true ? 'ПЕРЕЙТИ В КАНАЛ' : 'ОТКРЫТЬ',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: bar, letterSpacing: 0.3)),
            ),
          ],
        ]),
      ),
    );
  }
}

/// 5400 → «5,4K», как в Telegram.
String compactCount(int n) {
  String f(double v) => v.toStringAsFixed(v < 10 ? 1 : 0).replaceAll('.0', '').replaceAll('.', ',');
  if (n < 1000) return '$n';
  if (n < 1000000) return '${f(n / 1000)}K';
  return '${f(n / 1e6)}M';
}

/// Пузырь iOS: большое скругление и изогнутый «хвостик» у последнего сообщения серии.
class _BubblePainter extends CustomPainter {
  _BubblePainter({required this.color, required this.out, required this.tail});
  final Color color;
  final bool out;
  final bool tail;

  static const radius = 18.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    const r = radius;
    final path = Path();
    if (!tail) {
      path.addRRect(RRect.fromLTRBR(0, 0, w, h, const Radius.circular(r)));
    } else if (out) {
      path.addRRect(RRect.fromLTRBAndCorners(0, 0, w, h,
          topLeft: const Radius.circular(r), topRight: const Radius.circular(r),
          bottomLeft: const Radius.circular(r), bottomRight: const Radius.circular(6)));
      path.moveTo(w - 8, h - 16);
      path.cubicTo(w - 6, h - 4, w + 2, h - 1, w + 7, h);
      path.cubicTo(w + 1, h + 0.5, w - 6, h, w - 12, h - 2);
      path.close();
    } else {
      path.addRRect(RRect.fromLTRBAndCorners(0, 0, w, h,
          topLeft: const Radius.circular(r), topRight: const Radius.circular(r),
          bottomLeft: const Radius.circular(6), bottomRight: const Radius.circular(r)));
      path.moveTo(8, h - 16);
      path.cubicTo(6, h - 4, -2, h - 1, -7, h);
      path.cubicTo(-1, h + 0.5, 6, h, 12, h - 2);
      path.close();
    }
    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.35), 0.6, false);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BubblePainter old) => old.color != color || old.out != out || old.tail != tail;
}
