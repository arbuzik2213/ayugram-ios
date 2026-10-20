import 'package:flutter/material.dart';

import '../ayu/ayu_settings.dart';
import '../td/td_client.dart';
import '../td/td_service.dart';
import 'ayu_theme.dart';

/// Экран, если api_id/api_hash не были вшиты при сборке (--dart-define).
class ApiKeysScreen extends StatefulWidget {
  const ApiKeysScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<ApiKeysScreen> createState() => _ApiKeysScreenState();
}

class _ApiKeysScreenState extends State<ApiKeysScreen> {
  final _id = TextEditingController();
  final _hash = TextEditingController();
  String? _error;

  Future<void> _save() async {
    final id = int.tryParse(_id.text.trim());
    final hash = _hash.text.trim();
    if (id == null || hash.length != 32) {
      setState(() => _error = 'api_id — число, api_hash — 32 символа');
      return;
    }
    await AyuSettings.instance.setApiKeys(id, hash);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ключи Telegram API')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Получите api_id и api_hash на my.telegram.org → API development tools. '
              'Они хранятся только на этом устройстве.'),
          const SizedBox(height: 16),
          TextField(controller: _id, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'api_id')),
          TextField(controller: _hash, autocorrect: false, decoration: const InputDecoration(labelText: 'api_hash')),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('Продолжить')),
        ],
      ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.state});
  final TdObject state;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _input = TextEditingController();
  final _first = TextEditingController();
  final _last = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void didUpdateWidget(AuthScreen old) {
    super.didUpdateWidget(old);
    if (old.state['@type'] != widget.state['@type']) {
      _input.clear();
      _error = null;
    }
  }

  Future<void> _submit() async {
    final value = _input.text.trim();
    final td = TdService.instance.td;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      switch (widget.state['@type']) {
        case 'authorizationStateWaitPhoneNumber':
          await td.send({'@type': 'setAuthenticationPhoneNumber', 'phone_number': value});
        case 'authorizationStateWaitCode':
          await td.send({'@type': 'checkAuthenticationCode', 'code': value});
        case 'authorizationStateWaitPassword':
          await td.send({'@type': 'checkAuthenticationPassword', 'password': value});
        case 'authorizationStateWaitEmailAddress':
          await td.send({'@type': 'setAuthenticationEmailAddress', 'email_address': value});
        case 'authorizationStateWaitEmailCode':
          await td.send({
            '@type': 'checkAuthenticationEmailCode',
            'code': {'@type': 'emailAddressAuthenticationCode', 'code': value},
          });
        case 'authorizationStateWaitRegistration':
          await td.send({'@type': 'registerUser', 'first_name': _first.text.trim(), 'last_name': _last.text.trim()});
      }
    } on TdError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    final type = widget.state['@type'] as String;
    final (title, hint, label, keyboard, obscure) = switch (type) {
      'authorizationStateWaitPhoneNumber' => ('Ваш телефон', 'Проверьте код страны и введите свой номер телефона.', '+7 900 000 00 00', TextInputType.phone, false),
      'authorizationStateWaitCode' => ('Введите код', _codeHint(), 'Код', TextInputType.number, false),
      'authorizationStateWaitPassword' => ('Облачный пароль', _passwordHint(), 'Пароль', TextInputType.text, true),
      'authorizationStateWaitEmailAddress' => ('Почта', 'Telegram просит привязать e-mail.', 'E-mail', TextInputType.emailAddress, false),
      'authorizationStateWaitEmailCode' => ('Проверьте почту', 'Мы отправили код на вашу почту.', 'Код', TextInputType.number, false),
      'authorizationStateWaitRegistration' => ('Ваше имя', 'Укажите имя и (по желанию) фамилию.', '', TextInputType.name, false),
      _ => ('AyuGram', 'Подключение…', '', TextInputType.text, false),
    };
    final waiting = !type.startsWith('authorizationStateWait') || type == 'authorizationStateWaitTdlibParameters';

    InputDecoration deco(String l) => InputDecoration(
          hintText: l,
          hintStyle: TextStyle(color: c.panelHint),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.divider)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.blueText, width: 2)),
        );

    return Scaffold(
      backgroundColor: c.windowBg,
      floatingActionButton: waiting
          ? null
          : FloatingActionButton(
              backgroundColor: c.fab,
              foregroundColor: Colors.white,
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Icon(Icons.arrow_forward),
            ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          children: [
            Center(child: Image.asset('assets/logo.png', width: 110, height: 110)),
            const SizedBox(height: 24),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: c.text)),
            const SizedBox(height: 10),
            Text(hint, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: c.grayText, height: 1.35)),
            const SizedBox(height: 28),
            if (waiting)
              Center(child: CircularProgressIndicator(color: c.blueText))
            else if (type == 'authorizationStateWaitRegistration') ...[
              TextField(controller: _first, decoration: deco('Имя')),
              TextField(controller: _last, decoration: deco('Фамилия (необязательно)')),
            ] else
              TextField(
                // Новый ключ на каждом шаге: иначе iOS не меняет тип уже открытой клавиатуры.
                key: ValueKey(type),
                controller: _input,
                autofocus: true,
                keyboardType: keyboard,
                obscureText: obscure,
                autocorrect: false,
                enableSuggestions: !obscure,
                textAlign: obscure ? TextAlign.start : TextAlign.center,
                style: TextStyle(fontSize: 20, color: c.text, letterSpacing: keyboard == TextInputType.number ? 6 : 0.5),
                decoration: deco(label),
                onSubmitted: (_) => _submit(),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xffe56555))),
              ),
          ],
        ),
      ),
    );
  }

  String _codeHint() {
    final info = widget.state['code_info'] as TdObject?;
    final t = (info?['type'] as TdObject?)?['@type'];
    return switch (t) {
      'authenticationCodeTypeTelegramMessage' => 'Код отправлен в Telegram на другом устройстве',
      'authenticationCodeTypeSms' => 'Код отправлен по SMS',
      'authenticationCodeTypeCall' => 'Вам позвонят и продиктуют код',
      _ => 'Введите код подтверждения',
    };
  }

  String _passwordHint() {
    final h = widget.state['password_hint'] as String? ?? '';
    return h.isEmpty ? 'Включена двухэтапная проверка' : 'Подсказка: $h';
  }
}
