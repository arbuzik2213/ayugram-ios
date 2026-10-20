import 'package:flutter/material.dart';

import 'ayu/ayu_settings.dart';
import 'ayu/message_store.dart';
import 'td/td_service.dart';
import 'ui/auth_screen.dart';
import 'ui/chat_list_screen.dart';
import 'ui/ayu_theme.dart';
import 'ui/countries.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AyuSettings.instance.load();
  await MessageStore.instance.open();
  await Countries.load();
  runApp(const AyuApp());
}

class AyuApp extends StatefulWidget {
  const AyuApp({super.key});

  @override
  State<AyuApp> createState() => _AyuAppState();
}

class _AyuAppState extends State<AyuApp> with WidgetsBindingObserver {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _maybeStart();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // inactive — это шторка/пункт управления поверх приложения, оно всё ещё на экране.
    TdService.instance.setAppActive(state == AppLifecycleState.resumed || state == AppLifecycleState.inactive);
  }

  void _maybeStart() {
    final s = AyuSettings.instance;
    if (_started || s.apiId == null || s.apiHash == null) return;
    _started = true;
    TdService.instance.start();
    if (s.notificationsEnabled) TdService.instance.initNotifications();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AyuSettings.instance,
      builder: (context, _) => MaterialApp(
        title: 'AyuGram',
        debugShowCheckedModeBanner: false,
        theme: buildAyuTheme(AyuSettings.instance.nightMode),
        // «Масштаб интерфейса» из настроек.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(AyuSettings.instance.interfaceScale)),
          child: child!,
        ),
        home: !_started
            ? ApiKeysScreen(onDone: () => setState(_maybeStart))
            : ListenableBuilder(
                listenable: TdService.instance,
                builder: (context, _) {
                  final state = TdService.instance.authState;
                  if (state?['@type'] == 'authorizationStateReady') return const ChatListScreen();
                  return AuthScreen(state: state ?? {'@type': 'authorizationStateWaitTdlibParameters'});
                },
              ),
      ),
    );
  }
}
