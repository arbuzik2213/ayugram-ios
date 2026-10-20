// Скриншоты экранов с тестовыми данными: flutter test test/preview_test.dart --update-goldens
import 'dart:io';

import 'package:ayugram_ios/ayu/ayu_settings.dart';
import 'package:ayugram_ios/td/td_service.dart';
import 'package:ayugram_ios/ui/auth_screen.dart';
import 'package:ayugram_ios/ui/ayu_theme.dart';
import 'package:ayugram_ios/ui/chat_list_screen.dart';
import 'package:ayugram_ios/ui/countries.dart';
import 'package:ayugram_ios/ui/message_bubble.dart';
import 'package:ayugram_ios/ui/settings_screen.dart';
import 'package:ayugram_ios/ui/telegram_settings.dart';
import 'package:ayugram_ios/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _font(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await l.load();
}

int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

Map<String, dynamic> _chat(int id, String title, String text,
    {int unread = 0, bool out = false, String type = 'chatTypePrivate', int order = 1, bool muted = false, bool channel = false}) {
  return {
    'id': id,
    'title': title,
    'type': {'@type': type, 'user_id': id, 'supergroup_id': id, 'basic_group_id': id, 'is_channel': channel},
    'positions': [
      {'list': {'@type': 'chatListMain'}, 'order': '$order', 'is_pinned': false}
    ],
    'unread_count': unread,
    'last_read_outbox_message_id': out ? 10 : 0,
    'notification_settings': {'mute_for': muted ? 1000 : 0},
    'last_message': {
      'id': 10,
      'date': _now() - (1000 - order) * 60,
      'is_outgoing': out,
      'sender_id': {'@type': 'messageSenderUser', 'user_id': 77},
      'content': {'@type': 'messageText', 'text': {'text': text}},
    },
  };
}

Map<String, dynamic> _msg(int id, String text, {bool out = false, int user = 77, int edit = 0, int? views, List? reactions, int? reply}) => {
      'id': id,
      'chat_id': 1,
      'date': _now() - (100 - id) * 60,
      'edit_date': edit,
      'is_outgoing': out,
      'sender_id': {'@type': 'messageSenderUser', 'user_id': user},
      'content': {'@type': 'messageText', 'text': {'text': text}},
      if (reply != null) 'reply_to': {'@type': 'messageReplyToMessage', 'message_id': reply},
      'interaction_info': {
        'view_count': ?views,
        if (reactions != null) 'reactions': {'reactions': reactions},
      },
    };

Map<String, dynamic> _r(String e, int n, [bool chosen = false]) =>
    {'type': {'@type': 'reactionTypeEmoji', 'emoji': e}, 'total_count': n, 'is_chosen': chosen};

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AyuSettings.instance.load();
    await Countries.load();
    const fonts = 'assets/fonts';
    await _font('OpenSans', ['$fonts/OpenSans-Regular.ttf', '$fonts/OpenSans-Semibold.ttf', '$fonts/OpenSans-Bold.ttf']);
    await _font('MaterialIcons', ['${Platform.environment['HOME']}/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
    final svc = TdService.instance;
    svc.myId = 1;
    svc.users[1] = {'id': 1, 'first_name': 'Иван', 'phone_number': '380501234567', 'usernames': {'active_usernames': ['ivan_test']}, 'type': {'@type': 'userTypeRegular'}, 'verification_status': {'is_verified': true}};
    svc.users[77] = {'id': 77, 'first_name': 'Дашко', 'type': {'@type': 'userTypeRegular'}, 'status': {'@type': 'userStatusOnline'}};
    svc.users[78] = {'id': 78, 'first_name': 'Andrii', 'type': {'@type': 'userTypeRegular'}, 'status': {'@type': 'userStatusRecently'}};
    svc.supergroups[3] = {'id': 3, 'member_count': 6005, 'status': {'@type': 'chatMemberStatusMember'}};
    svc.supergroups[4] = {'id': 4, 'member_count': 669295, 'status': {'@type': 'chatMemberStatusMember'}, 'verification_status': {'is_verified': true}};
    for (final c in [
      _chat(2, 'флудилка, Гладенко', 'Нифига текстик', unread: 24491, type: 'chatTypeBasicGroup', order: 999),
      _chat(3, 'Труха⚡Київ Chat', '777: ИДИ СЮДА', unread: 5310, type: 'chatTypeSupergroup', order: 998),
      _chat(5, 'Telegram', 'Аниме', out: true, order: 997),
      _chat(6, 'НЕПТУН', 'Вінниччина: БПЛА на Вендичани/Хмельниччина', unread: 4741, type: 'chatTypeSupergroup', channel: true, order: 996),
      _chat(4, 'ППО - News🇺🇦Новини', 'На трасі «Київ-Одеса» після атаки…', unread: 1203, type: 'chatTypeSupergroup', channel: true, order: 995, muted: true),
      _chat(7, 'Київ Головне', 'Троє загиблих і четверо поранених', unread: 76, type: 'chatTypeSupergroup', channel: true, order: 994, muted: true),
    ]) {
      svc.chats[c['id'] as int] = c;
    }
  });

  Future<void> shot(WidgetTester t, Widget w, String name, {bool night = true}) async {
    t.view.physicalSize = const Size(1179, 2556);
    t.view.devicePixelRatio = 3;
    AyuSettings.instance.nightMode = night;
    await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: buildAyuTheme(night), home: w));
    await t.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('previews/$name.png'));
  }

  Widget chatMock(Map<String, dynamic> chat, List<Widget> rows) => Builder(
        builder: (context) => Scaffold(
          backgroundColor: context.ayu.historyBg,
          appBar: AppBar(
            titleSpacing: 0,
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(chat['title'] as String),
              Text('6 005 участников', style: TextStyle(fontSize: 13, color: context.ayu.windowSubTextFg, fontWeight: FontWeight.normal)),
            ]),
            actions: const [Icon(Icons.more_vert), SizedBox(width: 12)],
          ),
          body: AyuWallpaper(child: ListView(children: rows)),
        ),
      );

  testWidgets('chat list night', (t) async {
    TdService.instance.chatListVersion.value++;
    await shot(t, const ChatListScreen(), 'chat_list_night');
  });

  testWidgets('chat list day', (t) async {
    TdService.instance.chatListVersion.value++;
    await shot(t, const ChatListScreen(), 'chat_list_day', night: false);
  });

  testWidgets('drawer', (t) async {
    await shot(t, const Scaffold(body: AyuDrawer()), 'drawer');
  });

  for (final night in [true, false]) {
    testWidgets('chat ${night ? 'night' : 'day'}', (t) async {
      final chat = TdService.instance.chats[3]!;
      final msgs = [
        _msg(1, 'Привет всем! Кто знает, свет завтра будет?'),
        _msg(2, 'Говорят, графики с 8 утра', user: 78, reactions: [_r('👍', 12), _r('🙏', 3)]),
        _msg(3, 'Спасибо!', out: true, reply: 2),
        _msg(4, 'Это сообщение удалили, но AyuGram его сохранил', user: 78),
        _msg(5, 'Ну что, завтра идём?', edit: 1),
      ];
      Widget row(int i) {
        final m = msgs[i];
        final incoming = m['is_outgoing'] != true;
        final last = i == msgs.length - 1 || msgs[i + 1]['sender_id'].toString() != m['sender_id'].toString() || msgs[i + 1]['is_outgoing'] != m['is_outgoing'];
        final first = i == 0 || msgs[i - 1]['sender_id'].toString() != m['sender_id'].toString() || msgs[i - 1]['is_outgoing'] != m['is_outgoing'];
        Widget b = MessageBubble(
          message: m,
          chat: {...chat, 'last_read_outbox_message_id': 3},
          isDeleted: m['id'] == 4,
          isEdited: m['id'] == 5,
          showSender: first,
          tail: last,
          avatarSlot: incoming,
          replyTo: m['id'] == 3 ? msgs[1] : null,
        );
        if (incoming) {
          final uid = (m['sender_id'] as Map)['user_id'] as int;
          b = Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, last ? 6 : 1),
              child: last ? Avatar(id: uid, title: TdService.instance.userName(uid), radius: 16) : const SizedBox(width: 32),
            ),
            Expanded(child: b),
          ]);
        }
        return b;
      }

      await shot(t, chatMock(chat, [const ServicePill('20 октября'), for (var i = 0; i < msgs.length; i++) row(i)]),
          'chat_${night ? 'night' : 'day'}', night: night);
    });
  }

  testWidgets('channel', (t) async {
    final chat = TdService.instance.chats[4]!;
    await shot(
      t,
      chatMock(chat, [
        MessageBubble(
          message: _msg(1, 'Друзі, 10 секунд виділіть для допомоги Захисникам. Воїни 4 ОВМБр потребують радіостанції',
              views: 95400, reactions: [_r('🙏', 149), _r('👍', 30), _r('❤', 26)]),
          chat: chat,
          isDeleted: false,
          isEdited: false,
          showSender: true,
        ),
        MessageBubble(
          message: _msg(2, 'Перша в історії: українка Ярослава Магучіх стала першою у світі абсолютною чемпіонкою',
              views: 92900, reactions: [_r('❤', 1604), _r('🔥', 240)]),
          chat: chat,
          isDeleted: false,
          isEdited: false,
          showSender: true,
        ),
      ]),
      'channel',
    );
  });

  testWidgets('telegram settings', (t) async {
    await shot(t, const TelegramSettingsScreen(), 'tg_settings');
  });

  testWidgets('country picker', (t) async {
    await shot(t, const AuthScreen(state: {'@type': 'authorizationStateWaitPhoneNumber'}), 'auth_phone2');
    await t.tap(find.byIcon(Icons.keyboard_arrow_down));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('previews/country_picker.png'));
  });

  testWidgets('settings', (t) async {
    await shot(t, const SettingsScreen(), 'settings');
  });

  for (final (name, state) in [
    ('phone', {'@type': 'authorizationStateWaitPhoneNumber'}),
    ('code', {
      '@type': 'authorizationStateWaitCode',
      'code_info': {
        'phone_number': '380501234567',
        'type': {'@type': 'authenticationCodeTypeTelegramMessage', 'length': 5},
        'next_type': {'@type': 'authenticationCodeTypeSms'},
      },
    }),
    ('password', {'@type': 'authorizationStateWaitPassword', 'password_hint': 'любимый фильм'}),
  ]) {
    testWidgets('auth $name', (t) async {
      await shot(t, AuthScreen(state: state), 'auth_$name');
    });
  }
}
