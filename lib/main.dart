import 'package:flutter/material.dart';

import 'ayu/ayu_settings.dart';
import 'ayu/message_store.dart';
import 'td/td_service.dart';
import 'ui/auth_screen.dart';
import 'ui/chat_list_screen.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AyuSettings.instance.load();
  await MessageStore.instance.open();
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
    TdService.instance.setAppActive(state == AppLifecycleState.resumed);
  }

  void _maybeStart() {
    final s = AyuSettings.instance;
    if (_started || s.apiId == null || s.apiHash == null) return;
    _started = true;
    TdService.instance.start();
  }

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: ayuAccent, brightness: b),
          useMaterial3: true,
        );
    return MaterialApp(
      title: 'AyuGram',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
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
    );
  }
}
