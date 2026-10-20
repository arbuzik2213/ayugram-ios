import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../td/td_client.dart';
import '../td/td_service.dart';
import 'ayu_theme.dart';
import 'chat_screen.dart';

/// Открытие ссылок: t.me / telegram.me / tg:// внутри приложения, остальное — в браузере.
class Links {
  static void _toast(BuildContext context, String t) =>
      ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(t)));

  static Future<void> open(BuildContext context, String raw) async {
    var url = raw.trim();
    if (!url.contains('://') && !url.startsWith('tg:')) url = 'https://$url';
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final host = uri.host.toLowerCase().replaceFirst('www.', '');
    final svc = TdService.instance;

    if (uri.scheme == 'tg') {
      final domain = uri.queryParameters['domain'];
      final invite = uri.queryParameters['invite'];
      if (domain != null) return openUsername(context, domain, post: int.tryParse(uri.queryParameters['post'] ?? ''));
      if (invite != null) return _invite(context, 'https://t.me/+$invite');
    }

    if (host == 't.me' || host == 'telegram.me' || host == 'telegram.dog') {
      final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (seg.isEmpty) return;
      final first = seg[0];
      if (first.startsWith('+') || first == 'joinchat') return _invite(context, url);
      if (first == 'c' && seg.length >= 2) {
        final id = -1000000000000 - (int.tryParse(seg[1]) ?? 0);
        try {
          await svc.td.send({'@type': 'getChat', 'chat_id': id});
          if (context.mounted) _openChat(context, id);
        } catch (_) {
          if (context.mounted) _toast(context, 'Нет доступа к этому чату');
        }
        return;
      }
      if (const {'s', 'share', 'addstickers', 'addemoji', 'proxy', 'socks', 'setlanguage', 'boost', 'addlist', 'm', 'iv'}
          .contains(first)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
      return openUsername(context, first, post: seg.length > 1 ? int.tryParse(seg[1]) : null);
    }

    if (uri.scheme == 'mailto' || uri.scheme == 'tel') {
      await launchUrl(uri);
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// @username или t.me/username.
  static Future<void> openUsername(BuildContext context, String username, {int? post}) async {
    final name = username.replaceFirst('@', '');
    try {
      final chat = await TdService.instance.td.send({'@type': 'searchPublicChat', 'username': name});
      TdService.instance.chats.putIfAbsent(chat['id'] as int, () => chat);
      if (context.mounted) _openChat(context, chat['id'] as int);
    } catch (_) {
      if (context.mounted) _toast(context, 'Пользователь @$name не найден');
    }
  }

  static void _openChat(BuildContext context, int chatId) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: chatId)));

  static Future<void> _invite(BuildContext context, String link) async {
    final td = TdService.instance.td;
    try {
      final info = await td.send({'@type': 'checkChatInviteLink', 'invite_link': link});
      final existing = info['chat_id'] as int? ?? 0;
      if (existing != 0) {
        if (context.mounted) _openChat(context, existing);
        return;
      }
      if (!context.mounted) return;
      final c = context.ayu;
      final count = info['member_count'] as int? ?? 0;
      final join = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(info['title'] as String? ?? 'Чат'),
          content: Text('$count участников', style: TextStyle(color: c.windowSubTextFg)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Вступить')),
          ],
        ),
      );
      if (join != true) return;
      final chat = await td.send({'@type': 'joinChatByInviteLink', 'invite_link': link});
      if (context.mounted) _openChat(context, chat['id'] as int);
    } on TdError catch (e) {
      if (context.mounted) _toast(context, e.message == 'INVITE_HASH_EXPIRED' ? 'Ссылка устарела' : e.message);
    }
  }
}

/// formattedText → TextSpan c жирным/курсивом/кодом/спойлерами и нажимаемыми ссылками.
class RichMessageText {
  static List<InlineSpan> spans(
    BuildContext context,
    TdObject? formatted, {
    required Color linkColor,
    required Color textColor,
  }) {
    final text = formatted?['text'] as String? ?? '';
    final entities = (formatted?['entities'] as List? ?? []).cast<TdObject>();
    if (entities.isEmpty) return [TextSpan(text: text)];

    // Смещения TDLib — в UTF-16, как и у строк Dart.
    final cuts = <int>{0, text.length};
    for (final e in entities) {
      final o = e['offset'] as int, l = e['length'] as int;
      cuts.add(o.clamp(0, text.length));
      cuts.add((o + l).clamp(0, text.length));
    }
    final points = cuts.toList()..sort();
    final out = <InlineSpan>[];
    for (var i = 0; i + 1 < points.length; i++) {
      final a = points[i], b = points[i + 1];
      if (a >= b) continue;
      final piece = text.substring(a, b);
      var style = const TextStyle();
      String? link;
      String? mention;
      var spoiler = false;
      for (final e in entities) {
        final o = e['offset'] as int, l = e['length'] as int;
        if (a < o || b > o + l) continue;
        final type = e['type'] as TdObject;
        switch (type['@type']) {
          case 'textEntityTypeBold':
            style = style.copyWith(fontWeight: FontWeight.w700);
          case 'textEntityTypeItalic':
            style = style.copyWith(fontStyle: FontStyle.italic);
          case 'textEntityTypeUnderline':
            style = style.copyWith(decoration: TextDecoration.underline);
          case 'textEntityTypeStrikethrough':
            style = style.copyWith(decoration: TextDecoration.lineThrough);
          case 'textEntityTypeCode' || 'textEntityTypePre' || 'textEntityTypePreCode':
            style = style.copyWith(fontFamily: 'Menlo', fontSize: 14.5, color: linkColor);
          case 'textEntityTypeSpoiler':
            spoiler = true;
          case 'textEntityTypeUrl':
            link = text.substring(o.clamp(0, text.length), (o + l).clamp(0, text.length));
          case 'textEntityTypeTextUrl':
            link = type['url'] as String?;
          case 'textEntityTypeEmailAddress':
            link = 'mailto:$piece';
          case 'textEntityTypePhoneNumber':
            link = 'tel:$piece';
          case 'textEntityTypeMention':
            mention = text.substring(o.clamp(0, text.length), (o + l).clamp(0, text.length));
          case 'textEntityTypeMentionName':
            mention = '#user${type['user_id']}';
          case 'textEntityTypeHashtag' || 'textEntityTypeCashtag' || 'textEntityTypeBotCommand':
            style = style.copyWith(color: linkColor);
        }
      }
      if (spoiler) {
        out.add(WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: _Spoiler(text: piece, style: style, color: textColor)));
        continue;
      }
      GestureRecognizer? rec;
      if (link != null) {
        final l = link;
        rec = TapGestureRecognizer()..onTap = () => Links.open(context, l);
        style = style.copyWith(color: linkColor);
      } else if (mention != null) {
        final m = mention;
        rec = TapGestureRecognizer()
          ..onTap = () async {
            if (m.startsWith('#user')) {
              final uid = int.parse(m.substring(5));
              final chat = await TdService.instance.td.send({'@type': 'createPrivateChat', 'user_id': uid, 'force': false});
              if (context.mounted) Links._openChat(context, chat['id'] as int);
            } else {
              Links.openUsername(context, m);
            }
          };
        style = style.copyWith(color: linkColor);
      }
      out.add(TextSpan(text: piece, style: style, recognizer: rec));
    }
    return out;
  }
}

class _Spoiler extends StatefulWidget {
  const _Spoiler({required this.text, required this.style, required this.color});
  final String text;
  final TextStyle style;
  final Color color;

  @override
  State<_Spoiler> createState() => _SpoilerState();
}

class _SpoilerState extends State<_Spoiler> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => setState(() => _shown = true),
        child: Container(
          decoration: _shown ? null : BoxDecoration(color: widget.color.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(4)),
          child: Text(widget.text, style: widget.style.copyWith(color: _shown ? null : Colors.transparent)),
        ),
      );
}

/// Скопировать текст с подсказкой.
void copyText(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(const SnackBar(content: Text('Скопировано')));
}
