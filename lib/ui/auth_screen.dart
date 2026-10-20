import 'dart:io';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../ayu/ayu_settings.dart';
import '../td/td_client.dart';
import '../td/td_service.dart';
import 'ayu_theme.dart';
import 'countries.dart';
import 'widgets.dart';

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

/// Вход в стиле Intro::Widget из AyuGram Desktop.
class _AuthScreenState extends State<AuthScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _editPhone = false;

  Country? _country;
  final _codeField = TextEditingController(text: '+');

  @override
  void initState() {
    super.initState();
    _initCountries();
  }

  Future<void> _initCountries() async {
    await Countries.load();
    final locale = Platform.localeName.split(RegExp('[_-]'));
    final iso = locale.length > 1 ? locale[1] : 'UA';
    if (!mounted) return;
    setState(() => _setCountry(Countries.byIso(iso) ?? Countries.byIso('UA')));
    await Countries.localize();
    if (mounted) setState(() {});
  }

  void _setCountry(Country? c) {
    _country = c;
    if (c != null) _codeField.text = '+${c.code}';
    _reformatPhone();
  }

  void _reformatPhone() {
    final digits = _phone.text.replaceAll(RegExp(r'[^0-9]'), '');
    final f = _country?.format(digits) ?? digits;
    if (f != _phone.text) {
      _phone.value = TextEditingValue(text: f, selection: TextSelection.collapsed(offset: f.length));
    }
  }

  @override
  void didUpdateWidget(AuthScreen old) {
    super.didUpdateWidget(old);
    if (old.state['@type'] != widget.state['@type']) {
      Countries.localize().then((_) {
        if (mounted) setState(() {});
      });
      _error = null;
      _editPhone = false;
      _code.clear();
      _password.clear();
    }
  }

  String get _type => _editPhone ? 'authorizationStateWaitPhoneNumber' : widget.state['@type'] as String;

  Future<void> _run(TdObject request) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await TdService.instance.td.send(request);
      if (mounted) setState(() => _editPhone = false);
    } on TdError catch (e) {
      if (mounted) setState(() => _error = _humanError(e.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _humanError(String m) => switch (m) {
        'PHONE_NUMBER_INVALID' => 'Неверный номер телефона.',
        'PHONE_CODE_INVALID' => 'Неверный код. Попробуйте ещё раз.',
        'PASSWORD_HASH_INVALID' => 'Неверный пароль.',
        'PHONE_CODE_EXPIRED' => 'Код устарел. Запросите новый.',
        _ when m.startsWith('FLOOD_WAIT') => 'Слишком много попыток. Попробуйте позже.',
        _ => m,
      };

  void _submit() {
    switch (_type) {
      case 'authorizationStateWaitPhoneNumber':
        final digits = (_codeField.text + _phone.text).replaceAll(RegExp(r'[^0-9]'), '');
        _run({'@type': 'setAuthenticationPhoneNumber', 'phone_number': digits});
      case 'authorizationStateWaitCode':
        _run({'@type': 'checkAuthenticationCode', 'code': _code.text.trim()});
      case 'authorizationStateWaitPassword':
        _run({'@type': 'checkAuthenticationPassword', 'password': _password.text});
      case 'authorizationStateWaitEmailAddress':
        _run({'@type': 'setAuthenticationEmailAddress', 'email_address': _email.text.trim()});
      case 'authorizationStateWaitEmailCode':
        _run({
          '@type': 'checkAuthenticationEmailCode',
          'code': {'@type': 'emailAddressAuthenticationCode', 'code': _code.text.trim()},
        });
      case 'authorizationStateWaitRegistration':
        _run({'@type': 'registerUser', 'first_name': _first.text.trim(), 'last_name': _last.text.trim()});
    }
  }

  Future<void> _pickCountry() async {
    final picked = await showDialog<Country>(context: context, builder: (_) => const _CountryDialog());
    if (picked != null) setState(() => _setCountry(picked));
  }

  void _onCodeChanged(String v) {
    var digits = v.replaceAll(RegExp(r'[^0-9]'), '');
    // Код вставили вместе с номером — разбираем, как Telegram.
    final c = Countries.byPrefix(digits);
    if (c != null && digits.length > c.code.length) {
      _phone.text = digits.substring(c.code.length) + _phone.text;
      digits = c.code;
    }
    _codeField.value = TextEditingValue(text: '+$digits', selection: TextSelection.collapsed(offset: digits.length + 1));
    setState(() {
      if (_country?.code != digits) {
        final same = Countries.list.where((x) => x.code == digits).toList();
        // Для общих кодов (+7, +1) берём основную страну, как Telegram.
        _country = same.where((x) => const {'RU', 'US'}.contains(x.iso)).firstOrNull ?? same.firstOrNull;
      }
      _reformatPhone();
    });
  }

  void _onPhoneChanged(String v) {
    // Вставили номер целиком с «+» — переносим код страны в своё поле.
    if (v.trim().startsWith('+')) {
      final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
      final c = Countries.byPrefix(digits);
      if (c != null) {
        _phone.text = digits.substring(c.code.length);
        setState(() => _setCountry(c));
        return;
      }
    }
    setState(_reformatPhone);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    final type = _type;
    final waiting = !type.startsWith('authorizationStateWait') || type == 'authorizationStateWaitTdlibParameters';
    final canGoBack = !waiting && type != 'authorizationStateWaitPhoneNumber';

    return Scaffold(
      backgroundColor: c.windowBg,
      body: SafeArea(
        child: Column(children: [
          SizedBox(
            height: 48,
            child: Row(children: [
              if (canGoBack)
                IconButton(
                  icon: Icon(Icons.arrow_back, color: c.menuIconFg),
                  onPressed: () => setState(() {
                    _editPhone = true;
                    _error = null;
                  }),
                ),
              const Spacer(),
            ]),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 36),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: waiting ? const CircularProgressIndicator(strokeWidth: 2) : _step(context, type),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('AyuGram iOS v1.0', style: TextStyle(fontSize: 11.5, color: c.windowSubTextFg)),
          ),
        ]),
      ),
    );
  }

  Widget _title(BuildContext context, String title, Widget description) {
    final c = context.ayu;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.windowBoldFg)),
      const SizedBox(height: 8),
      DefaultTextStyle.merge(style: TextStyle(fontSize: 13.5, color: c.windowSubTextFg, height: 1.45), child: description),
      const SizedBox(height: 26),
    ]);
  }

  InputDecoration _underline(BuildContext context, {String? hint, String? label}) {
    final c = context.ayu;
    return InputDecoration(
      isDense: true,
      hintText: hint,
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelStyle: TextStyle(color: c.windowActiveTextFg, fontSize: 15),
      hintStyle: TextStyle(color: c.placeholderFg, letterSpacing: 1.5),
      contentPadding: const EdgeInsets.symmetric(vertical: 10),
      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.inputBorderFg)),
      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.activeLineFg, width: 2)),
    );
  }

  Widget _errorText(BuildContext context) => _error == null
      ? const SizedBox(height: 16)
      : Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(_error!, style: TextStyle(color: context.ayu.attentionFg, fontSize: 13.5)),
        );

  Widget _step(BuildContext context, String type) {
    final c = context.ayu;
    final field = TextStyle(fontSize: 16, color: c.windowFg);
    switch (type) {
      case 'authorizationStateWaitPhoneNumber':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _title(context, 'Ваш номер телефона', const Text('Проверьте код страны и введите\nсвой номер телефона.')),
          InkWell(
            onTap: _pickCountry,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.inputBorderFg))),
              child: Row(children: [
                if (_country != null) Padding(padding: const EdgeInsets.only(right: 10), child: Text(_country!.flag, style: const TextStyle(fontSize: 20))),
                Expanded(
                  child: Text(_country?.name ?? 'Неверный код страны',
                      style: field.copyWith(color: _country == null ? c.windowSubTextFg : null)),
                ),
                Icon(Icons.keyboard_arrow_down, color: c.menuIconFg),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            SizedBox(
              width: 70,
              child: TextField(
                controller: _codeField,
                keyboardType: TextInputType.phone,
                style: field,
                onChanged: _onCodeChanged,
                decoration: _underline(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const ValueKey('phone'),
                controller: _phone,
                autofocus: true,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumberNational],
                style: field.copyWith(letterSpacing: 0.5),
                onChanged: _onPhoneChanged,
                decoration: _underline(context, hint: _country?.hint ?? '--- --- ----'),
                onSubmitted: (_) => _submit(),
              ),
            ),
          ]),
          _errorText(context),
          const SizedBox(height: 24),
          AyuButton(text: 'Далее', busy: _busy, onPressed: _submit),
          const SizedBox(height: 26),
          Center(
            child: GestureDetector(
              onTap: () => _run({'@type': 'requestQrCodeAuthentication', 'other_user_ids': []}),
              child: Text('Быстрый вход по QR-коду', style: TextStyle(color: c.lightButtonFg, fontSize: 13.5)),
            ),
          ),
        ]);

      case 'authorizationStateWaitOtherDeviceConfirmation':
        final link = widget.state['link'] as String? ?? '';
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: QrImageView(data: link, size: 200, backgroundColor: Colors.white),
            ),
          ),
          const SizedBox(height: 24),
          Text('Вход по QR-коду',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.windowBoldFg)),
          const SizedBox(height: 12),
          Text(
            '1. Откройте Telegram на телефоне\n'
            '2. Настройки → Устройства → Подключить устройство\n'
            '3. Наведите камеру на этот код',
            style: TextStyle(fontSize: 13.5, color: c.windowSubTextFg, height: 1.6),
          ),
          const SizedBox(height: 22),
          Center(
            child: GestureDetector(
              onTap: () => setState(() => _editPhone = true),
              child: Text('Войти по номеру телефона', style: TextStyle(color: c.lightButtonFg, fontSize: 13.5)),
            ),
          ),
        ]);

      case 'authorizationStateWaitCode':
        final info = widget.state['code_info'] as TdObject?;
        final codeType = info?['type'] as TdObject?;
        final length = codeType?['length'] as int? ?? 5;
        final phone = info?['phone_number'] as String? ?? '';
        final viaTelegram = codeType?['@type'] == 'authenticationCodeTypeTelegramMessage';
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _title(
            context,
            phone.isEmpty ? 'Код' : _formatPhone(phone),
            viaTelegram
                ? Text.rich(TextSpan(children: [
                    const TextSpan(text: 'Код отправлен '),
                    TextSpan(text: 'через Telegram', style: TextStyle(fontWeight: FontWeight.w600, color: c.windowFg)),
                    const TextSpan(text: ' на другие ваши устройства, если они подключены.'),
                  ]))
                : Text(_codeHint(codeType)),
          ),
          _CodeBoxes(controller: _code, length: length, onCompleted: _submit),
          if (info?['next_type'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: GestureDetector(
                onTap: () => _run({'@type': 'resendAuthenticationCode', 'reason': null}),
                child: Text(_resendLabel(info!['next_type'] as TdObject), style: TextStyle(color: c.lightButtonFg, fontSize: 13.5)),
              ),
            ),
          _errorText(context),
          const SizedBox(height: 24),
          AyuButton(text: 'Далее', busy: _busy, onPressed: _submit),
        ]);

      case 'authorizationStateWaitPassword':
        final hint = widget.state['password_hint'] as String? ?? '';
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _title(context, 'Проверка облачного пароля', const Text('Введите ваш облачный пароль.')),
          TextField(
            // Новый ключ на каждом шаге: iOS не меняет тип уже открытой клавиатуры.
            key: const ValueKey('password'),
            controller: _password,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.text,
            autocorrect: false,
            enableSuggestions: false,
            style: field,
            decoration: _underline(context, label: 'Ваш облачный пароль'),
            onSubmitted: (_) => _submit(),
          ),
          if (hint.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text('Подсказка: $hint', style: TextStyle(fontSize: 13.5, color: c.windowFg)),
            ),
          _errorText(context),
          const SizedBox(height: 24),
          AyuButton(text: 'Отправить', busy: _busy, onPressed: _submit),
        ]);

      case 'authorizationStateWaitEmailAddress':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _title(context, 'Почта', const Text('Telegram просит привязать e-mail для входа.')),
          TextField(
            key: const ValueKey('email'),
            controller: _email,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            style: field,
            decoration: _underline(context, label: 'E-mail'),
          ),
          _errorText(context),
          const SizedBox(height: 24),
          AyuButton(text: 'Далее', busy: _busy, onPressed: _submit),
        ]);

      case 'authorizationStateWaitEmailCode':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _title(context, 'Проверьте почту', const Text('Мы отправили код на вашу почту.')),
          _CodeBoxes(controller: _code, length: 6, onCompleted: _submit),
          _errorText(context),
          const SizedBox(height: 24),
          AyuButton(text: 'Далее', busy: _busy, onPressed: _submit),
        ]);

      case 'authorizationStateWaitRegistration':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _title(context, 'Ваше имя', const Text('Укажите имя и (по желанию) фамилию.')),
          TextField(key: const ValueKey('first'), controller: _first, style: field, decoration: _underline(context, label: 'Имя')),
          const SizedBox(height: 14),
          TextField(controller: _last, style: field, decoration: _underline(context, label: 'Фамилия')),
          _errorText(context),
          const SizedBox(height: 24),
          AyuButton(text: 'Зарегистрироваться', busy: _busy, onPressed: _submit),
        ]);
    }
    return Text(type, style: TextStyle(color: c.windowSubTextFg));
  }

  String _formatPhone(String digits) => Countries.formatFull(digits);

  String _codeHint(TdObject? t) => switch (t?['@type']) {
        'authenticationCodeTypeSms' => 'Мы отправили SMS с кодом.',
        'authenticationCodeTypeCall' => 'Вам позвонят и продиктуют код.',
        'authenticationCodeTypeFragment' => 'Код отправлен через Fragment.',
        _ => 'Введите код подтверждения.',
      };

  String _resendLabel(TdObject next) => switch (next['@type']) {
        'authenticationCodeTypeSms' => 'Отправить код по SMS',
        'authenticationCodeTypeCall' => 'Позвонить мне',
        _ => 'Отправить код ещё раз',
      };
}

/// Ячейки для ввода кода, как в AyuGram Desktop.
class _CodeBoxes extends StatefulWidget {
  const _CodeBoxes({required this.controller, required this.length, required this.onCompleted});
  final TextEditingController controller;
  final int length;
  final VoidCallback onCompleted;

  @override
  State<_CodeBoxes> createState() => _CodeBoxesState();
}

class _CodeBoxesState extends State<_CodeBoxes> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    return GestureDetector(
      onTap: () => _focus.requestFocus(),
      child: Stack(children: [
        // Невидимое поле принимает ввод (и автоподстановку кода из SMS).
        Opacity(
          opacity: 0,
          child: TextField(
            key: const ValueKey('code'),
            controller: widget.controller,
            focusNode: _focus,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            maxLength: widget.length,
            onChanged: (v) {
              setState(() {});
              if (v.length == widget.length) widget.onCompleted();
            },
          ),
        ),
        ListenableBuilder(
          listenable: Listenable.merge([widget.controller, _focus]),
          builder: (context, _) {
            final text = widget.controller.text;
            return Row(children: [
              for (var i = 0; i < widget.length; i++)
                Container(
                  width: 40,
                  height: 50,
                  margin: const EdgeInsets.only(right: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.windowBgOver,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _focus.hasFocus && i == text.length.clamp(0, widget.length - 1)
                          ? c.activeLineFg
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Text(i < text.length ? text[i] : '',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: c.windowFg)),
                ),
            ]);
          },
        ),
      ]),
    );
  }
}

/// Диалог «Выберите страну» (CountrySelectBox в tdesktop).
class _CountryDialog extends StatefulWidget {
  const _CountryDialog();

  @override
  State<_CountryDialog> createState() => _CountryDialogState();
}

class _CountryDialogState extends State<_CountryDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    final q = _q.toLowerCase().replaceAll('+', '');
    final list = Countries.list
        .where((x) => q.isEmpty || x.name.toLowerCase().contains(q) || x.iso.toLowerCase() == q || x.code.startsWith(q))
        .toList();
    return Dialog(
      backgroundColor: c.windowBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 6),
          child: Text('Выберите страну', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.windowBoldFg)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 16, 0),
          child: TextField(
            autofocus: true,
            onChanged: (v) => setState(() => _q = v),
            style: TextStyle(color: c.windowFg),
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search, color: c.menuIconFg, size: 20),
              hintText: 'Поиск',
              hintStyle: TextStyle(color: c.placeholderFg),
              border: InputBorder.none,
            ),
          ),
        ),
        Divider(height: 1, color: c.inputBorderFg),
        Expanded(
          child: list.isEmpty
              ? Center(child: Text('Страна не найдена', style: TextStyle(color: c.windowSubTextFg)))
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final x = list[i];
                    return InkWell(
                      onTap: () => Navigator.pop(context, x),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                        child: Row(children: [
                          Text(x.flag, style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(x.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.windowFg)),
                          ),
                          Text('+${x.code}', style: TextStyle(fontSize: 14, color: c.windowSubTextFg)),
                        ]),
                      ),
                    );
                  },
                ),
        ),
        Divider(height: 1, color: c.inputBorderFg),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть')),
          ),
        ),
      ]),
    );
  }
}
