import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ayu/ayu_settings.dart';
import '../td/td_client.dart';
import '../td/td_service.dart';
import 'ayu_theme.dart';
import 'format.dart';
import 'widgets.dart';

/// Профиль чата / канала / пользователя (Info::Profile в AyuGram Desktop).
class ChatInfoScreen extends StatefulWidget {
  const ChatInfoScreen({super.key, required this.chatId});
  final int chatId;

  @override
  State<ChatInfoScreen> createState() => _ChatInfoScreenState();
}

class _ChatInfoScreenState extends State<ChatInfoScreen> {
  final _svc = TdService.instance;
  String? _about;
  String? _username;
  final _counts = <String, int>{};
  List<TdObject> _members = [];

  TdObject get _chat => _svc.chats[widget.chatId] ?? {'id': widget.chatId, 'title': ''};

  static const _filters = [
    ('searchMessagesFilterPhoto', Icons.image_outlined, 'фото', 'фото', 'фото'),
    ('searchMessagesFilterVideo', Icons.videocam_outlined, 'видео', 'видео', 'видео'),
    ('searchMessagesFilterDocument', Icons.insert_drive_file_outlined, 'файл', 'файла', 'файлов'),
    ('searchMessagesFilterUrl', Icons.link, 'ссылка', 'ссылки', 'ссылок'),
    ('searchMessagesFilterVoiceNote', Icons.mic_none, 'голосовое', 'голосовых', 'голосовых'),
    ('searchMessagesFilterAnimation', Icons.gif_box_outlined, 'GIF', 'GIF', 'GIF'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final chat = _chat;
    final td = _svc.td;
    final type = chat['type'] as TdObject?;
    try {
      switch (type?['@type']) {
        case 'chatTypePrivate':
          final full = await td.send({'@type': 'getUserFullInfo', 'user_id': type!['user_id']});
          _about = ((full['bio'] as TdObject?)?['text'] as String?);
          final u = _svc.users[type['user_id']];
          _username = ((u?['usernames'] as TdObject?)?['active_usernames'] as List?)?.cast<String>().firstOrNull;
        case 'chatTypeSupergroup':
          final full = await td.send({'@type': 'getSupergroupFullInfo', 'supergroup_id': type!['supergroup_id']});
          _about = full['description'] as String?;
          final sg = _svc.supergroups[type['supergroup_id']];
          _username = ((sg?['usernames'] as TdObject?)?['active_usernames'] as List?)?.cast<String>().firstOrNull;
          if (type['is_channel'] != true) {
            final res = await td.send({
              '@type': 'getSupergroupMembers',
              'supergroup_id': type['supergroup_id'],
              'filter': {'@type': 'supergroupMembersFilterRecent'},
              'offset': 0,
              'limit': 50,
            });
            _members = (res['members'] as List? ?? []).cast<TdObject>();
          }
        case 'chatTypeBasicGroup':
          final full = await td.send({'@type': 'getBasicGroupFullInfo', 'basic_group_id': type!['basic_group_id']});
          _about = full['description'] as String?;
          _members = (full['members'] as List? ?? []).cast<TdObject>();
      }
    } catch (_) {}
    for (final missing in _members) {
      final id = (missing['member_id'] as TdObject?)?['user_id'];
      if (id != null && !_svc.users.containsKey(id)) {
        try {
          _svc.users[id as int] = await td.send({'@type': 'getUser', 'user_id': id});
        } catch (_) {}
      }
    }
    if (mounted) setState(() {});
    for (final f in _filters) {
      try {
        final r = await td.send({
          '@type': 'getChatMessageCount',
          'chat_id': widget.chatId,
          'filter': {'@type': f.$1},
          'return_local': false,
        });
        _counts[f.$1] = r['count'] as int? ?? 0;
        if (mounted) setState(() {});
      } catch (_) {}
    }
  }

  void _toast(String t) =>
      ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(t), duration: const Duration(seconds: 1)));

  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_svc.isChannel(_chat) ? 'Покинуть канал?' : 'Покинуть группу?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Покинуть', style: TextStyle(color: context.ayu.attentionFg)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    _svc.td.fire({'@type': 'leaveChat', 'chat_id': widget.chatId});
    if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    final s = AyuSettings.instance;
    final chat = _chat;
    final user = _svc.privateUser(chat);
    final channel = _svc.isChannel(chat);
    final muted = _svc.isMuted(chat);
    final n = _svc.memberCount(chat);
    final subtitle = user != null
        ? userStatus(user)
        : n == null
            ? ''
            : '${formatThousands(n)} ${channel ? plural(n, 'подписчик', 'подписчика', 'подписчиков') : plural(n, 'участник', 'участника', 'участников')}';

    Widget action(IconData icon, String label, VoidCallback onTap) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Material(
              color: c.windowBgOver,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onTap,
                child: SizedBox(
                  height: 58,
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(icon, color: c.windowFg, size: 22),
                    const SizedBox(height: 4),
                    Text(label, style: TextStyle(fontSize: 12, color: c.windowFg)),
                  ]),
                ),
              ),
            ),
          ),
        );

    Widget infoRow(String value, String label, {bool mono = false, VoidCallback? onTap}) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value,
                  style: TextStyle(
                    fontSize: 14,
                    color: mono ? c.windowActiveTextFg : c.windowFg,
                    fontFamily: mono ? 'Menlo' : null,
                    height: 1.35,
                  )),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 13, color: c.windowSubTextFg)),
            ]),
          ),
        );

    final counts = [
      for (final f in _filters)
        if ((_counts[f.$1] ?? 0) > 0) (f.$2, '${formatThousands(_counts[f.$1]!)} ${plural(_counts[f.$1]!, f.$3, f.$4, f.$5)}'),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(user != null ? 'Информация' : channel ? 'Информация о канале' : 'Информация о группе')),
      body: ListView(children: [
        const SizedBox(height: 18),
        Center(child: Avatar(id: widget.chatId, title: chat['title'] as String? ?? '', photo: chat['photo'] as TdObject?, radius: 42)),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(
              child: Text(chat['title'] as String? ?? '',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.windowBoldFg)),
            ),
            if (_svc.isVerified(chat)) const VerifiedBadge(),
          ]),
        ),
        const SizedBox(height: 3),
        Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: c.windowSubTextFg)),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            action(muted ? Icons.notifications_off_outlined : Icons.notifications_none, muted ? 'Вкл. звук' : 'Без звука',
                () => setState(() => _svc.setMuted(chat, !muted))),
            if (user == null) action(Icons.logout, 'Покинуть', _leave),
            action(Icons.more_horiz, 'Ещё', () => _toast('Скоро')),
          ]),
        ),
        const SizedBox(height: 12),
        Container(height: 8, color: c.dividerBg),
        const SizedBox(height: 6),
        if (_username != null)
          infoRow('t.me/$_username', 'Ссылка', onTap: () {
            Clipboard.setData(ClipboardData(text: 'https://t.me/$_username'));
            _toast('Ссылка скопирована');
          }),
        if (_about != null && _about!.isNotEmpty) infoRow(_about!, user != null ? 'О себе' : 'Описание'),
        if (s.showPeerId)
          infoRow(peerIdLabel(chat), 'ID', mono: true, onTap: () {
            Clipboard.setData(ClipboardData(text: '${chat['id']}'));
            _toast('ID скопирован');
          }),
        if (counts.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(height: 8, color: c.dividerBg),
          const SizedBox(height: 6),
          for (final (icon, label) in counts) TextCell(title: label, icon: icon),
        ],
        if (_members.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(height: 8, color: c.dividerBg),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: Row(children: [
              Icon(Icons.people_outline, color: c.menuIconFg),
              const SizedBox(width: 22),
              Text('${formatThousands(n ?? _members.length)} ${plural(n ?? _members.length, 'УЧАСТНИК', 'УЧАСТНИКА', 'УЧАСТНИКОВ')}',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.windowFg)),
            ]),
          ),
          for (final m in _members) _memberRow(context, m),
        ],
        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _memberRow(BuildContext context, TdObject m) {
    final c = context.ayu;
    final id = (m['member_id'] as TdObject?)?['user_id'] as int?;
    if (id == null) return const SizedBox();
    final u = _svc.users[id];
    final status = (m['status'] as TdObject?)?['@type'];
    final role = status == 'chatMemberStatusCreator'
        ? 'владелец'
        : status == 'chatMemberStatusAdministrator'
            ? 'админ'
            : null;
    final verified = (u?['verification_status'] as TdObject?)?['is_verified'] == true;
    return SizedBox(
      height: 56,
      child: Row(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Avatar(id: id, title: _svc.userName(id), photo: u?['profile_photo'] as TdObject?, radius: 21),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Row(children: [
              Flexible(
                child: Text(_svc.userName(id),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.windowFg)),
              ),
              if (verified) const VerifiedBadge(size: 14),
            ]),
            Text(userStatus(u),
                style: TextStyle(
                  fontSize: 13,
                  color: (u?['status'] as TdObject?)?['@type'] == 'userStatusOnline' ? c.windowActiveTextFg : c.windowSubTextFg,
                )),
          ]),
        ),
        if (role != null)
          Padding(padding: const EdgeInsets.only(right: 16), child: Text(role, style: TextStyle(fontSize: 13, color: c.windowSubTextFg))),
      ]),
    );
  }
}
