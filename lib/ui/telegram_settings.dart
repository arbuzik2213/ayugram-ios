import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ayu/ayu_settings.dart';
import '../td/td_client.dart';
import '../td/td_service.dart';
import 'ayu_theme.dart';
import 'chat_screen.dart';
import 'countries.dart';
import 'format.dart';
import 'settings_screen.dart';
import 'widgets.dart';

// Порт разделов Telegram/SourceFiles/settings/sections/* из AyuGram Desktop на TDLib.

TdClient get _td => TdService.instance.td;

void _toast(BuildContext context, String text) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));

Future<bool> _confirm(BuildContext context, String title, String action, {bool danger = false, String? text}) async {
  final c = context.ayu;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: text == null ? null : Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action, style: danger ? TextStyle(color: c.attentionFg) : null),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Выбор из вариантов (радиокнопки), как Ui::BoxContent с Radiobutton.
Future<T?> _choose<T>(BuildContext context, String title, List<(T, String)> options, T current) {
  final c = context.ayu;
  return showDialog<T>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      contentPadding: const EdgeInsets.only(top: 12, bottom: 4),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final (value, label) in options)
          InkWell(
            onTap: () => Navigator.pop(ctx, value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
              child: Row(children: [
                Icon(value == current ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: value == current ? c.activeLineFg : c.menuIconFg, size: 22),
                const SizedBox(width: 14),
                Text(label, style: TextStyle(fontSize: 15, color: c.windowFg)),
              ]),
            ),
          ),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена'))],
    ),
  );
}

Future<String?> _editText(BuildContext context, String title, String value, {String? label, int? maxLength, String? about}) {
  final ctl = TextEditingController(text: value);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(controller: ctl, autofocus: true, maxLength: maxLength, decoration: InputDecoration(labelText: label)),
        if (about != null) Text(about, style: TextStyle(fontSize: 13, color: ctx.ayu.windowSubTextFg)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
        TextButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Сохранить')),
      ],
    ),
  );
}

Future<void> _push(BuildContext context, Widget screen) => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));

// =============================================================================
// Главный экран настроек (settings_main.cpp)
// =============================================================================

class TelegramSettingsScreen extends StatefulWidget {
  const TelegramSettingsScreen({super.key, this.embedded = false});

  /// Вкладка главного экрана (без кнопки «назад», с отступом под панель вкладок).
  final bool embedded;

  @override
  State<TelegramSettingsScreen> createState() => _TelegramSettingsScreenState();
}

class _TelegramSettingsScreenState extends State<TelegramSettingsScreen> {
  final _svc = TdService.instance;

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    final s = AyuSettings.instance;
    final me = _svc.users[_svc.myId] ?? const {};
    final name = _svc.myId == null ? '' : _svc.userName(_svc.myId!);
    final phone = me['phone_number'] as String? ?? '';
    final username = ((me['usernames'] as TdObject?)?['active_usernames'] as List?)?.cast<String>().firstOrNull;
    final verified = (me['verification_status'] as TdObject?)?['is_verified'] == true;

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки'), automaticallyImplyLeading: !widget.embedded, centerTitle: widget.embedded),
      body: ListenableBuilder(
        listenable: Listenable.merge([s, _svc]),
        builder: (context, _) => ListView(padding: EdgeInsets.only(bottom: widget.embedded ? 110 : 0), children: [
          // Обложка профиля (Settings::Cover).
          InkWell(
            onTap: () => _push(context, const InformationScreen()).then((_) => setState(() {})),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Row(children: [
                Avatar(id: _svc.myId ?? 0, title: name, photo: me['profile_photo'] as TdObject?, radius: 38),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(
                        child: Text(s.streamerMode ? 'Скрыто' : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.windowBoldFg)),
                      ),
                      if (verified) const VerifiedBadge(),
                    ]),
                    const SizedBox(height: 4),
                    if (phone.isNotEmpty && !s.streamerMode)
                      Text(Countries.formatFull(phone), style: TextStyle(fontSize: 14, color: c.windowSubTextFg)),
                    if (username != null && !s.streamerMode)
                      Text('@$username', style: TextStyle(fontSize: 14, color: c.windowActiveTextFg)),
                  ]),
                ),
              ]),
            ),
          ),
          Container(height: 8, color: c.dividerBg),
          // Аккаунты (как в Telegram для iOS): переключение и добавление.
          for (final acc in _svc.accounts)
            if (acc != _svc.currentAccount)
              _AccountRow(account: acc, onTap: () {
                Navigator.popUntil(context, (r) => r.isFirst);
                _svc.switchAccount(acc);
              }),
          TextCell(
            title: 'Добавить аккаунт',
            icon: Icons.person_add_alt,
            color: c.windowActiveTextFg,
            onTap: () async {
              if (_svc.accounts.length >= 5) {
                _toast(context, 'Можно добавить до 5 аккаунтов');
                return;
              }
              Navigator.popUntil(context, (r) => r.isFirst);
              _svc.addAccount();
            },
          ),
          Container(height: 8, color: c.dividerBg),
          const SizedBox(height: 6),
          TextCell(
            title: 'Избранное',
            icon: CupertinoIcons.bookmark,
            onTap: () async {
              final id = _svc.myId;
              if (id == null) return;
              final chat = await _td.send({'@type': 'createPrivateChat', 'user_id': id, 'force': false});
              if (context.mounted) _push(context, ChatScreen(chatId: chat['id'] as int));
            },
          ),
          CheckCell(
            icon: CupertinoIcons.tv,
            title: 'Режим стримера',
            subtitle: 'Скрывает номер, аватарки и превью сообщений',
            value: s.streamerMode,
            onChanged: (v) {
              s.streamerMode = v;
              s.save();
            },
          ),
          Container(height: 8, color: c.dividerBg),
          const SizedBox(height: 6),
          TextCell(title: 'Мой аккаунт', icon: Icons.person_outline,
              onTap: () => _push(context, const InformationScreen()).then((_) => setState(() {}))),
          TextCell(title: 'Уведомления и звуки', icon: Icons.notifications_none,
              onTap: () => _push(context, const NotificationsScreen())),
          TextCell(title: 'Конфиденциальность', icon: Icons.lock_outline,
              onTap: () => _push(context, const PrivacyScreen())),
          TextCell(title: 'Настройки чатов', icon: Icons.chat_bubble_outline,
              onTap: () => _push(context, const ChatSettingsScreen())),
          TextCell(title: 'Папки', icon: Icons.folder_outlined, onTap: () => _push(context, const FoldersScreen())),
          TextCell(title: 'Продвинутые настройки', icon: Icons.tune, onTap: () => _push(context, const AdvancedScreen())),
          TextCell(title: 'Устройства', icon: Icons.devices_outlined, onTap: () => _push(context, const SessionsScreen())),
          TextCell(title: 'Язык', icon: Icons.translate, value: 'Русский', onTap: () => _toast(context, 'Пока доступен только русский')),
          const SizedBox(height: 6),
          Container(height: 8, color: c.dividerBg),
          const SizedBox(height: 6),
          TextCell(title: 'Настройки AyuGram', icon: Icons.visibility_off_outlined,
              onTap: () => _push(context, const SettingsScreen())),
          _ScaleCell(),
          const SizedBox(height: 6),
          Container(height: 8, color: c.dividerBg),
          const SizedBox(height: 6),
          TextCell(title: 'Вопросы о Telegram', icon: Icons.help_outline,
              onTap: () => launchUrl(Uri.parse('https://telegram.org/faq'), mode: LaunchMode.externalApplication)),
          TextCell(title: 'Возможности Telegram', icon: Icons.lightbulb_outline,
              onTap: () => launchUrl(Uri.parse('https://t.me/TelegramTips'), mode: LaunchMode.externalApplication)),
          TextCell(
            title: 'Выйти',
            icon: Icons.logout,
            color: c.attentionFg,
            onTap: () async {
              if (!await _confirm(context, 'Вы точно хотите выйти?', 'Выйти', danger: true)) return;
              await _svc.logOut();
              if (context.mounted) Navigator.popUntil(context, (r) => r.isFirst);
            },
          ),
          const SizedBox(height: 30),
        ]),
      ),
    );
  }
}

/// Неактивный аккаунт в списке.
class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.account, required this.onTap});
  final int account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    final info = TdService.instance.accountInfo[account] ?? const {};
    final name = (info['name'] as String?)?.isNotEmpty == true ? info['name'] as String : 'Аккаунт ${account + 1}';
    final phone = info['phone'] as String? ?? '';
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 52,
        child: Row(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Avatar(id: info['id'] as int? ?? account, title: name, radius: 16),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(name, style: TextStyle(fontSize: 15, color: c.windowFg)),
              if (phone.isNotEmpty && !AyuSettings.instance.streamerMode)
                Text(Countries.formatFull(phone), style: TextStyle(fontSize: 13, color: c.windowSubTextFg)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// «Масштаб интерфейса» (Settings::SetupInterfaceScale).
class _ScaleCell extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    final s = AyuSettings.instance;
    const steps = [0.85, 1.0, 1.1, 1.25, 1.4];
    final idx = steps.indexWhere((x) => (x - s.interfaceScale).abs() < 0.01).clamp(0, steps.length - 1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.zoom_in, color: c.menuIconFg, size: 22),
          const SizedBox(width: 22),
          Expanded(child: Text('Масштаб интерфейса', style: TextStyle(fontSize: 15, color: c.windowFg))),
          Text('${(s.interfaceScale * 100).round()}%', style: TextStyle(fontSize: 15, color: c.lightButtonFg)),
        ]),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: c.activeLineFg,
            inactiveTrackColor: c.inputBorderFg,
            thumbColor: c.activeLineFg,
            trackHeight: 2,
            overlayShape: SliderComponentShape.noOverlay,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(44, 10, 4, 10),
            child: Slider(
              value: idx.toDouble(),
              max: steps.length - 1,
              divisions: steps.length - 1,
              onChanged: (v) {
                s.interfaceScale = steps[v.round()];
                s.save();
              },
            ),
          ),
        ),
      ]),
    );
  }
}

// =============================================================================
// Мой аккаунт (settings_information.cpp)
// =============================================================================

class InformationScreen extends StatefulWidget {
  const InformationScreen({super.key});

  @override
  State<InformationScreen> createState() => _InformationScreenState();
}

class _InformationScreenState extends State<InformationScreen> {
  final _svc = TdService.instance;
  String _bio = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final full = await _td.send({'@type': 'getUserFullInfo', 'user_id': _svc.myId});
      _bio = (full['bio'] as TdObject?)?['text'] as String? ?? '';
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _refreshMe() async {
    try {
      _svc.users[_svc.myId!] = await _td.send({'@type': 'getUser', 'user_id': _svc.myId});
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    final me = _svc.users[_svc.myId] ?? const {};
    final first = me['first_name'] as String? ?? '';
    final last = me['last_name'] as String? ?? '';
    final phone = me['phone_number'] as String? ?? '';
    final username = ((me['usernames'] as TdObject?)?['active_usernames'] as List?)?.cast<String>().firstOrNull;

    Widget row(String label, String value, VoidCallback? onTap, {IconData? icon}) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 22, 10),
            child: Row(children: [
              Icon(icon, color: c.menuIconFg, size: 22),
              const SizedBox(width: 22),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(value.isEmpty ? 'Не указано' : value,
                      style: TextStyle(fontSize: 15, color: value.isEmpty ? c.windowSubTextFg : c.windowFg)),
                  const SizedBox(height: 2),
                  Text(label, style: TextStyle(fontSize: 13, color: c.windowSubTextFg)),
                ]),
              ),
            ]),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Мой аккаунт')),
      body: ListView(children: [
        const SizedBox(height: 18),
        Center(
          child: Avatar(id: _svc.myId ?? 0, title: '$first $last', photo: me['profile_photo'] as TdObject?, radius: 46),
        ),
        const SizedBox(height: 18),
        Container(height: 8, color: c.dividerBg),
        const SizedBox(height: 6),
        row('Имя', '$first $last'.trim(), icon: Icons.person_outline, () async {
          final f = await _editText(context, 'Изменить имя', first, label: 'Имя', maxLength: 64);
          if (f == null || !context.mounted) return;
          final l = await _editText(context, 'Изменить фамилию', last, label: 'Фамилия', maxLength: 64);
          if (l == null || f.isEmpty) return;
          try {
            await _td.send({'@type': 'setName', 'first_name': f, 'last_name': l});
            await _refreshMe();
          } on TdError catch (e) {
            if (context.mounted) _toast(context, e.message);
          }
        }),
        row('Телефон', phone.isEmpty ? '' : Countries.formatFull(phone), icon: Icons.phone_outlined, null),
        row('Имя пользователя', username == null ? '' : '@$username', icon: Icons.alternate_email, () async {
          final u = await _editText(context, 'Имя пользователя', username ?? '',
              label: 'Имя пользователя', maxLength: 32, about: 'Можно использовать a–z, 0–9 и подчёркивание. Минимум 5 символов.');
          if (u == null) return;
          try {
            await _td.send({'@type': 'setUsername', 'username': u});
            await _refreshMe();
          } on TdError catch (e) {
            if (context.mounted) _toast(context, e.message == 'USERNAME_OCCUPIED' ? 'Это имя уже занято' : e.message);
          }
        }),
        row('О себе', _bio, icon: Icons.info_outline, () async {
          final b = await _editText(context, 'О себе', _bio, label: 'О себе', maxLength: 70);
          if (b == null) return;
          try {
            await _td.send({'@type': 'setBio', 'bio': b});
            setState(() => _bio = b);
          } on TdError catch (e) {
            if (context.mounted) _toast(context, e.message);
          }
        }),
      ]),
    );
  }
}

// =============================================================================
// Уведомления и звуки (settings_notifications.cpp)
// =============================================================================

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const _scopes = [
    ('notificationSettingsScopePrivateChats', 'Личные чаты', Icons.person_outline),
    ('notificationSettingsScopeGroupChats', 'Группы', Icons.people_outline),
    ('notificationSettingsScopeChannelChats', 'Каналы', Icons.campaign_outlined),
  ];
  final _settings = <String, TdObject>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final s in _scopes) {
      try {
        _settings[s.$1] = await _td.send({'@type': 'getScopeNotificationSettings', 'scope': {'@type': s.$1}});
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  void _update(String scope, void Function(TdObject) change) {
    final ns = Map<String, dynamic>.from(_settings[scope] ?? {});
    ns['@type'] = 'scopeNotificationSettings';
    change(ns);
    setState(() => _settings[scope] = ns);
    _td.fire({'@type': 'setScopeNotificationSettings', 'scope': {'@type': scope}, 'notification_settings': ns});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    return Scaffold(
      appBar: AppBar(title: const Text('Уведомления и звуки')),
      body: ListView(children: [
        SettingsSection(
          title: 'AyuGram',
          footer: 'Уведомления показываются, пока AyuGram открыт или недавно свёрнут. '
              'Настоящие push-уведомления требуют подписи приложения сертификатом Apple с APNs.',
          children: [
            ListenableBuilder(
              listenable: AyuSettings.instance,
              builder: (context, _) => CheckCell(
                icon: CupertinoIcons.bell,
                title: 'Уведомления AyuGram',
                subtitle: 'О новых сообщениях в чатах со звуком',
                value: AyuSettings.instance.notificationsEnabled,
                onChanged: (v) async {
                  final s = AyuSettings.instance;
                  if (v) {
                    final ok = await TdService.instance.requestNotificationPermission();
                    if (!ok) {
                      if (context.mounted) {
                        _toast(context, 'Разрешите уведомления: Настройки iPhone → AyuGram → Уведомления');
                      }
                      return;
                    }
                  }
                  s.notificationsEnabled = v;
                  s.save();
                },
              ),
            ),
          ],
        ),
        for (final (scope, label, icon) in _scopes)
          SettingsSection(title: label, children: [
            CheckCell(
              icon: icon,
              title: 'Уведомления',
              value: ((_settings[scope]?['mute_for'] as int?) ?? 0) == 0,
              onChanged: (v) => _update(scope, (ns) => ns['mute_for'] = v ? 0 : 2147483647),
            ),
            CheckCell(
              icon: Icons.visibility_outlined,
              title: 'Показывать текст',
              value: _settings[scope]?['show_preview'] != false,
              onChanged: (v) => _update(scope, (ns) => ns['show_preview'] = v),
            ),
            CheckCell(
              icon: Icons.push_pin_outlined,
              title: 'Закреплённые сообщения',
              value: _settings[scope]?['disable_pinned_message_notifications'] != true,
              onChanged: (v) => _update(scope, (ns) => ns['disable_pinned_message_notifications'] = !v),
            ),
          ]),
        SettingsSection(
          divider: false,
          children: [
            TextCell(
              title: 'Сбросить все уведомления',
              icon: Icons.restart_alt,
              color: c.attentionFg,
              onTap: () async {
                if (!await _confirm(context, 'Сбросить настройки уведомлений для всех чатов?', 'Сбросить', danger: true)) return;
                _td.fire({'@type': 'resetAllNotificationSettings'});
                _load();
              },
            ),
          ],
          footer: 'Push-уведомления на iPhone требуют подписи приложения Apple-сертификатом с поддержкой APNs, '
              'поэтому сейчас эти настройки действуют на сервере и в других клиентах.',
        ),
      ]),
    );
  }
}

// =============================================================================
// Конфиденциальность (settings_privacy_security.cpp)
// =============================================================================

enum _Who { everybody, contacts, nobody }

String _whoLabel(_Who? w) => switch (w) {
      _Who.everybody => 'Все',
      _Who.contacts => 'Мои контакты',
      _Who.nobody => 'Никто',
      null => '…',
    };

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  static const _items = [
    ('userPrivacySettingShowPhoneNumber', 'Номер телефона', Icons.phone_outlined),
    ('userPrivacySettingShowStatus', 'Время захода', Icons.access_time),
    ('userPrivacySettingShowProfilePhoto', 'Фотографии профиля', Icons.account_circle_outlined),
    ('userPrivacySettingShowBio', 'О себе', Icons.info_outline),
    ('userPrivacySettingShowBirthdate', 'Дата рождения', Icons.cake_outlined),
    ('userPrivacySettingShowLinkInForwardedMessages', 'Пересылка сообщений', Icons.shortcut),
    ('userPrivacySettingAllowCalls', 'Звонки', Icons.call_outlined),
    ('userPrivacySettingAllowChatInvites', 'Приглашения', Icons.group_add_outlined),
  ];

  final _rules = <String, List<TdObject>>{};
  int _blocked = 0;
  bool? _hasPassword;
  int _autoDelete = 0;
  int _ttlDays = 0;
  int _sessions = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final it in _items) {
      try {
        final r = await _td.send({'@type': 'getUserPrivacySettingRules', 'setting': {'@type': it.$1}});
        _rules[it.$1] = (r['rules'] as List? ?? []).cast<TdObject>();
        if (mounted) setState(() {});
      } catch (_) {}
    }
    try {
      final b = await _td.send({
        '@type': 'getBlockedMessageSenders',
        'block_list': {'@type': 'blockListMain'},
        'offset': 0,
        'limit': 1,
      });
      _blocked = b['total_count'] as int? ?? 0;
    } catch (_) {}
    try {
      _hasPassword = (await _td.send({'@type': 'getPasswordState'}))['has_password'] == true;
    } catch (_) {}
    try {
      _autoDelete = (await _td.send({'@type': 'getDefaultMessageAutoDeleteTime'}))['time'] as int? ?? 0;
    } catch (_) {}
    try {
      _ttlDays = (await _td.send({'@type': 'getAccountTtl'}))['days'] as int? ?? 0;
    } catch (_) {}
    try {
      _sessions = ((await _td.send({'@type': 'getActiveSessions'}))['sessions'] as List? ?? []).length;
    } catch (_) {}
    if (mounted) setState(() {});
  }

  _Who? _who(String setting) {
    final rules = _rules[setting];
    if (rules == null) return null;
    final types = rules.map((r) => r['@type']).toSet();
    if (types.contains('userPrivacySettingRuleAllowAll')) return _Who.everybody;
    if (types.contains('userPrivacySettingRuleAllowContacts')) return _Who.contacts;
    return _Who.nobody;
  }

  Future<void> _change(String setting, String title) async {
    final current = _who(setting);
    final picked = await _choose(context, title, [
      (_Who.everybody, 'Все'),
      (_Who.contacts, 'Мои контакты'),
      (_Who.nobody, 'Никто'),
    ], current);
    if (picked == null || picked == current) return;
    // Исключения (конкретные пользователи и чаты) сохраняем, меняем только основное правило.
    const base = {
      'userPrivacySettingRuleAllowAll',
      'userPrivacySettingRuleAllowContacts',
      'userPrivacySettingRuleRestrictAll',
      'userPrivacySettingRuleRestrictContacts',
    };
    final exceptions = (_rules[setting] ?? []).where((r) => !base.contains(r['@type'])).toList();
    final rules = [
      ...exceptions,
      {
        '@type': switch (picked) {
          _Who.everybody => 'userPrivacySettingRuleAllowAll',
          _Who.contacts => 'userPrivacySettingRuleAllowContacts',
          _Who.nobody => 'userPrivacySettingRuleRestrictAll',
        },
      },
    ];
    try {
      await _td.send({
        '@type': 'setUserPrivacySettingRules',
        'setting': {'@type': setting},
        'rules': {'@type': 'userPrivacySettingRules', 'rules': rules},
      });
      setState(() => _rules[setting] = rules.cast<TdObject>());
    } on TdError catch (e) {
      if (mounted) _toast(context, e.message);
    }
  }

  String _autoDeleteLabel(int t) => switch (t) {
        0 => 'Выкл.',
        86400 => '1 день',
        604800 => '1 неделя',
        2678400 => '1 месяц',
        _ => '${t ~/ 86400} дн.',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Конфиденциальность')),
      body: ListView(children: [
        SettingsSection(title: 'Безопасность', children: [
          TextCell(
            title: 'Заблокированные',
            icon: Icons.block,
            value: '$_blocked',
            onTap: () => _push(context, const BlockedScreen()).then((_) => _load()),
          ),
          TextCell(
            title: 'Облачный пароль',
            icon: Icons.key_outlined,
            value: _hasPassword == null ? '…' : (_hasPassword! ? 'Вкл.' : 'Выкл.'),
            onTap: () => _toast(context, 'Изменить облачный пароль можно в официальном приложении'),
          ),
          TextCell(
            title: 'Автоудаление сообщений',
            icon: Icons.timer_outlined,
            value: _autoDeleteLabel(_autoDelete),
            onTap: () async {
              final t = await _choose(context, 'Автоудаление в новых чатах',
                  [(0, 'Выкл.'), (86400, '1 день'), (604800, '1 неделя'), (2678400, '1 месяц')], _autoDelete);
              if (t == null) return;
              _td.fire({
                '@type': 'setDefaultMessageAutoDeleteTime',
                'message_auto_delete_time': {'@type': 'messageAutoDeleteTime', 'time': t},
              });
              setState(() => _autoDelete = t);
            },
          ),
          TextCell(
            title: 'Активные сеансы',
            icon: Icons.devices_outlined,
            value: '$_sessions',
            onTap: () => _push(context, const SessionsScreen()).then((_) => _load()),
          ),
        ]),
        SettingsSection(title: 'Конфиденциальность', children: [
          for (final (setting, label, icon) in _items)
            TextCell(title: label, icon: icon, value: _whoLabel(_who(setting)), onTap: () => _change(setting, label)),
        ]),
        SettingsSection(
          title: 'Удаление аккаунта',
          divider: false,
          footer: 'Если вы не будете заходить в аккаунт в течение этого срока, он будет удалён вместе со всеми сообщениями и контактами.',
          children: [
            TextCell(
              title: 'Если я не захожу',
              icon: Icons.delete_outline,
              value: _ttlDays == 0 ? '…' : '${(_ttlDays / 30).round()} мес.',
              onTap: () async {
                final d = await _choose(context, 'Если я не захожу',
                    [(30, '1 месяц'), (90, '3 месяца'), (180, '6 месяцев'), (365, '12 месяцев')], _ttlDays);
                if (d == null) return;
                _td.fire({'@type': 'setAccountTtl', 'ttl': {'@type': 'accountTtl', 'days': d}});
                setState(() => _ttlDays = d);
              },
            ),
          ],
        ),
      ]),
    );
  }
}

/// Заблокированные пользователи (settings_blocked_peers.cpp).
class BlockedScreen extends StatefulWidget {
  const BlockedScreen({super.key});

  @override
  State<BlockedScreen> createState() => _BlockedScreenState();
}

class _BlockedScreenState extends State<BlockedScreen> {
  final _svc = TdService.instance;
  List<TdObject>? _senders;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _td.send({
        '@type': 'getBlockedMessageSenders',
        'block_list': {'@type': 'blockListMain'},
        'offset': 0,
        'limit': 100,
      });
      final list = (r['senders'] as List? ?? []).cast<TdObject>();
      for (final s in list) {
        final id = s['user_id'];
        if (id != null && !_svc.users.containsKey(id)) {
          try {
            _svc.users[id as int] = await _td.send({'@type': 'getUser', 'user_id': id});
          } catch (_) {}
        }
      }
      if (mounted) setState(() => _senders = list);
    } catch (_) {
      if (mounted) setState(() => _senders = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    final list = _senders;
    return Scaffold(
      appBar: AppBar(title: const Text('Заблокированные')),
      body: list == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : list.isEmpty
              ? Center(child: Text('Список пуст', style: TextStyle(color: c.windowSubTextFg)))
              : ListView(children: [
                  for (final s in list)
                    Builder(builder: (context) {
                      final id = (s['user_id'] ?? s['chat_id']) as int;
                      final name = s['@type'] == 'messageSenderUser' ? _svc.userName(id) : _svc.chats[id]?['title'] as String? ?? '$id';
                      final photo = s['@type'] == 'messageSenderUser'
                          ? (_svc.users[id]?['profile_photo'] as TdObject?)
                          : (_svc.chats[id]?['photo'] as TdObject?);
                      return SizedBox(
                        height: 58,
                        child: Row(children: [
                          Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Avatar(id: id, title: name, photo: photo, radius: 21)),
                          Expanded(child: Text(name, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: c.windowFg))),
                          TextButton(
                            onPressed: () async {
                              await _td.send({'@type': 'setMessageSenderBlockList', 'sender_id': s, 'block_list': null});
                              _svc.blockedUsers.remove(id);
                              _load();
                            },
                            child: const Text('Разблокировать'),
                          ),
                        ]),
                      );
                    }),
                ]),
    );
  }
}

// =============================================================================
// Устройства (settings_active_sessions.cpp)
// =============================================================================

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  List<TdObject>? _sessions;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _td.send({'@type': 'getActiveSessions'});
      if (mounted) setState(() => _sessions = (r['sessions'] as List? ?? []).cast<TdObject>());
    } catch (_) {
      if (mounted) setState(() => _sessions = []);
    }
  }

  IconData _icon(TdObject s) => switch ((s['type'] as TdObject?)?['@type']) {
        'sessionTypeIphone' || 'sessionTypeIpad' => Icons.phone_iphone,
        'sessionTypeAndroid' => Icons.phone_android,
        'sessionTypeMac' || 'sessionTypeWindows' || 'sessionTypeLinux' || 'sessionTypeUbuntu' => Icons.laptop,
        'sessionTypeChrome' || 'sessionTypeFirefox' || 'sessionTypeSafari' || 'sessionTypeEdge' || 'sessionTypeOpera' ||
        'sessionTypeBrave' || 'sessionTypeVivaldi' => Icons.language,
        _ => Icons.devices_other,
      };

  Widget _row(BuildContext context, TdObject s, {bool current = false}) {
    final c = context.ayu;
    final title = '${s['application_name'] ?? ''} ${s['application_version'] ?? ''}'.trim();
    final device = [s['device_model'], s['platform'], s['system_version']].whereType<String>().where((x) => x.isNotEmpty).join(', ');
    final where = [s['location'], s['country']].whereType<String>().where((x) => x.isNotEmpty).join(', ');
    final when = current ? 'в сети' : fullDate(s['last_active_date'] as int? ?? 0);
    return InkWell(
      onTap: current
          ? null
          : () async {
              if (!await _confirm(context, 'Завершить сеанс?', 'Завершить', danger: true, text: '$title\n$device')) return;
              try {
                await _td.send({'@type': 'terminateSession', 'session_id': s['id']});
                _load();
              } on TdError catch (e) {
                if (context.mounted) _toast(context, e.message);
              }
            },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: c.windowBgOver, borderRadius: BorderRadius.circular(10)),
            child: Icon(_icon(s), color: c.windowActiveTextFg),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(device.isEmpty ? title : device, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: c.windowFg)),
              const SizedBox(height: 2),
              Text(title, style: TextStyle(fontSize: 13.5, color: c.windowFg)),
              Text([where, when].where((x) => x.isNotEmpty).join(' • '),
                  style: TextStyle(fontSize: 13, color: current ? c.windowActiveTextFg : c.windowSubTextFg)),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    final list = _sessions;
    final current = list?.where((s) => s['is_current'] == true).toList() ?? [];
    final others = list?.where((s) => s['is_current'] != true).toList() ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('Устройства')),
      body: list == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(children: [
              SettingsSection(title: 'Текущий сеанс', children: [
                for (final s in current) _row(context, s, current: true),
                if (others.isNotEmpty)
                  TextCell(
                    title: 'Завершить все другие сеансы',
                    icon: Icons.front_hand_outlined,
                    color: c.attentionFg,
                    onTap: () async {
                      if (!await _confirm(context, 'Завершить все другие сеансы?', 'Завершить', danger: true)) return;
                      try {
                        await _td.send({'@type': 'terminateAllOtherSessions'});
                        _load();
                      } on TdError catch (e) {
                        if (context.mounted) _toast(context, e.message);
                      }
                    },
                  ),
              ]),
              if (others.isNotEmpty)
                SettingsSection(
                  title: 'Активные сеансы',
                  divider: false,
                  footer: 'Нажмите на сеанс, чтобы завершить его.',
                  children: [for (final s in others) _row(context, s)],
                ),
            ]),
    );
  }
}

// =============================================================================
// Настройки чатов (settings_chat.cpp)
// =============================================================================

class ChatSettingsScreen extends StatelessWidget {
  const ChatSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AyuSettings.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки чатов')),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) => ListView(children: [
          SettingsSection(title: 'Тема', children: [
            CheckCell(icon: Icons.dark_mode_outlined, title: 'Ночной режим', value: s.nightMode, onChanged: (v) {
              s.nightMode = v;
              s.save();
            }),
          ]),
          SettingsSection(title: 'Сообщения', children: [
            CheckCell(icon: Icons.schedule, title: 'Секунды во времени сообщений', value: s.showMessageSeconds, onChanged: (v) {
              s.showMessageSeconds = v;
              s.save();
            }),
            CheckCell(icon: Icons.tag, title: 'Показывать ID', value: s.showPeerId, onChanged: (v) {
              s.showPeerId = v;
              s.save();
            }),
          ]),
          SettingsSection(
            title: 'Масштаб',
            divider: false,
            children: [_ScaleCell()],
          ),
        ]),
      ),
    );
  }
}

// =============================================================================
// Папки (settings_folders.cpp)
// =============================================================================

class FoldersScreen extends StatelessWidget {
  const FoldersScreen({super.key});

  static String folderName(TdObject f) {
    final name = f['name'] as TdObject?;
    final text = (name?['text'] as TdObject?)?['text'] as String?;
    return text ?? f['title'] as String? ?? 'Папка';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    final folders = TdService.instance.chatFolders;
    return Scaffold(
      appBar: AppBar(title: const Text('Папки')),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 10),
          child: Text('Создавайте папки для разных групп чатов и быстро переключайтесь между ними.',
              style: TextStyle(fontSize: 14, color: c.windowSubTextFg, height: 1.4)),
        ),
        SettingsSection(
          title: 'Мои папки',
          divider: false,
          footer: folders.isEmpty ? 'Папок пока нет. Создать их можно в официальном приложении.' : null,
          children: [for (final f in folders) TextCell(title: folderName(f), icon: Icons.folder_outlined)],
        ),
      ]),
    );
  }
}

// =============================================================================
// Продвинутые настройки → Данные и память (settings_advanced.cpp, settings_local_storage.cpp)
// =============================================================================

class AdvancedScreen extends StatefulWidget {
  const AdvancedScreen({super.key});

  @override
  State<AdvancedScreen> createState() => _AdvancedScreenState();
}

class _AdvancedScreenState extends State<AdvancedScreen> {
  TdObject? _stats;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _stats = await _td.send({'@type': 'getStorageStatisticsFast'});
      final v = await _td.send({'@type': 'getOption', 'name': 'version'});
      _version = '${v['value'] ?? ''}';
    } catch (_) {}
    if (mounted) setState(() {});
  }

  static String _mb(int? b) => b == null ? '…' : '${(b / (1 << 20)).toStringAsFixed(1)} МБ';

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    return Scaffold(
      appBar: AppBar(title: const Text('Продвинутые настройки')),
      body: ListView(children: [
        SettingsSection(title: 'Данные и память', children: [
          TextCell(title: 'Файлы и медиа', icon: Icons.perm_media_outlined, value: _mb(_stats?['files_size'] as int?)),
          TextCell(title: 'База данных', icon: Icons.storage, value: _mb(_stats?['database_size'] as int?)),
          TextCell(
            title: 'Очистить кэш',
            icon: Icons.cleaning_services_outlined,
            color: c.attentionFg,
            onTap: () async {
              if (!await _confirm(context, 'Удалить загруженные файлы с устройства?', 'Очистить',
                  danger: true, text: 'Сообщения останутся, файлы можно будет скачать снова.')) {
                return;
              }
              try {
                await _td.send({
                  '@type': 'optimizeStorage',
                  'size': 0,
                  'ttl': 0,
                  'count': 0,
                  'immunity_delay': 0,
                  'file_types': null,
                  'chat_ids': [],
                  'exclude_chat_ids': [],
                  'return_deleted_file_statistics': false,
                  'chat_limit': 0,
                });
                if (context.mounted) _toast(context, 'Кэш очищен');
                _load();
              } on TdError catch (e) {
                if (context.mounted) _toast(context, e.message);
              }
            },
          ),
        ]),
        SettingsSection(
          title: 'Версия',
          divider: false,
          children: [
            TextCell(title: 'AyuGram iOS', icon: Icons.info_outline, value: '1.0'),
            TextCell(
              title: 'TDLib',
              icon: Icons.code,
              value: _version,
              onTap: () => Clipboard.setData(ClipboardData(text: 'AyuGram iOS 1.0, TDLib $_version')),
            ),
          ],
        ),
      ]),
    );
  }
}
