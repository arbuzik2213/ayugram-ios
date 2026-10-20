// Скриншоты экранов с тестовыми данными: flutter test test/preview_test.dart
import 'dart:io';

import 'package:ayugram_ios/ayu/ayu_settings.dart';
import 'package:ayugram_ios/td/td_service.dart';
import 'package:ayugram_ios/ui/auth_screen.dart';
import 'package:ayugram_ios/ui/ayu_theme.dart';
import 'package:ayugram_ios/ui/chat_list_screen.dart';
import 'package:ayugram_ios/ui/message_bubble.dart';
import 'package:ayugram_ios/ui/settings_screen.dart';
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
    'type': {'@type': type, 'user_id': id, 'is_channel': channel},
    'positions': [
      {'list': {'@type': 'chatListMain'}, 'order': '$order', 'is_pinned': order > 900}
    ],
    'unread_count': unread,
    'last_read_outbox_message_id': out ? 10 : 0,
    'notification_settings': {'mute_for': muted ? 1000 : 0},
    'last_message': {
      'id': 10,
      'date': _now() - order * 60,
      'is_outgoing': out,
      'sender_id': {'@type': 'messageSenderUser', 'user_id': 77},
      'content': {'@type': 'messageText', 'text': {'text': text}},
    },
  };
}

Map<String, dynamic> _msg(int id, String text, {bool out = false, int user = 77, int edit = 0}) => {
      'id': id,
      'chat_id': 1,
      'date': _now() - (100 - id) * 60,
      'edit_date': edit,
      'is_outgoing': out,
      'sender_id': {'@type': 'messageSenderUser', 'user_id': user},
      'content': {'@type': 'messageText', 'text': {'text': text}},
    };

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AyuSettings.instance.load();
    const fonts = 'assets/fonts';
    await _font('Roboto', ['$fonts/Roboto-Regular.ttf', '$fonts/Roboto-Medium.ttf', '$fonts/Roboto-Bold.ttf']);
    await _font('MaterialIcons', ['${Platform.environment['HOME']}/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
    final svc = TdService.instance;
    svc.users[77] = {'id': 77, 'first_name': 'Аня', 'last_name': 'К', 'type': {'@type': 'userTypeRegular'}, 'status': {'@type': 'userStatusOnline'}};
    for (final c in [
      _chat(1, 'Аня К', 'Ну что, завтра идём?', unread: 2, order: 990),
      _chat(2, 'Дима', 'Скинь фотки плиз', out: true, order: 50),
      _chat(3, 'Рабочий чат', 'Созвон в 15:00', unread: 14, type: 'chatTypeBasicGroup', order: 40, muted: true),
      _chat(4, 'Новости', 'Главное за день: ...', unread: 120, type: 'chatTypeSupergroup', order: 30, channel: true),
      _chat(5, 'Мама', 'Позвони как сможешь', order: 20),
      _chat(6, 'Сергей', 'ок', out: true, order: 10),
    ]) {
      svc.chats[c['id'] as int] = c;
    }
  });

  Future<void> shot(WidgetTester t, Widget w, String name, {Brightness b = Brightness.light}) async {
    t.view.physicalSize = const Size(1179, 2556);
    t.view.devicePixelRatio = 3;
    await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: buildAyuTheme(b), home: w));
    await t.pump(const Duration(milliseconds: 200));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('previews/$name.png'));
  }

  testWidgets('chat list', (t) async {
    TdService.instance.chatListVersion.value++;
    await shot(t, const ChatListScreen(), 'chat_list');
  });

  testWidgets('chat', (t) async {
    final chat = TdService.instance.chats[1]!;
    final msgs = [
      _msg(1, 'Привет! Как дела?'),
      _msg(2, 'Привет, норм. Ты как?', out: true),
      _msg(3, 'Тоже хорошо 🙂 Завтра идём в кино?'),
      _msg(4, 'Давай, во сколько?', out: true),
      _msg(5, 'Это сообщение удалили, но AyuGram его сохранил'),
      _msg(6, 'Ну что, завтра идём?', edit: 1),
    ];
    await shot(
      t,
      Builder(builder: (context) {
        return Scaffold(
          appBar: AppBar(title: const Text('Аня К')),
          body: AyuWallpaper(
            child: ListView(children: [
              const ServicePill('20 октября'),
              for (var i = 0; i < msgs.length; i++)
                MessageBubble(
                  message: msgs[i],
                  chat: {...chat, 'last_read_outbox_message_id': 2},
                  isDeleted: msgs[i]['id'] == 5,
                  isEdited: msgs[i]['id'] == 6,
                  showSender: false,
                  tail: i == msgs.length - 1 || msgs[i]['is_outgoing'] != msgs[i + 1]['is_outgoing'] || i == 4,
                ),
            ]),
          ),
        );
      }),
      'chat',
    );
  });

  testWidgets('settings', (t) async {
    await shot(t, const SettingsScreen(), 'settings');
  });

  testWidgets('password', (t) async {
    await shot(t, const AuthScreen(state: {'@type': 'authorizationStateWaitPassword', 'password_hint': 'кот'}), 'password');
  });
}
