import 'dart:math';

import 'package:flutter/material.dart';

import '../ayu/ayu_settings.dart';
import '../ayu/message_store.dart';
import '../td/td_service.dart';
import 'widgets.dart';

/// Настройки AyuGram — повторяют разделы ayu/ui/settings/settings_ayu.cpp.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AyuSettings.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки AyuGram')),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          Widget sw(String title, bool value, void Function(bool) set, {String? sub}) => SwitchListTile(
                title: Text(title),
                subtitle: sub == null ? null : Text(sub),
                value: value,
                onChanged: (v) {
                  set(v);
                  s.save();
                },
              );

          return ListView(children: [
            const SectionHeader('Режим призрака'),
            SwitchListTile(
              secondary: const Icon(Icons.visibility_off),
              title: const Text('Режим призрака', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Выключает все пакеты ниже разом'),
              value: s.isGhostModeActive,
              onChanged: s.setGhostModeEnabled,
            ),
            sw('Отправлять прочтение', s.sendReadMessages, (v) => s.sendReadMessages = v,
                sub: 'Собеседник увидит ✓✓, когда вы откроете чат'),
            sw('Отправлять «в сети»', s.sendOnlinePackets, (v) => s.sendOnlinePackets = v),
            sw('Отправлять «печатает…»', s.sendUploadProgress, (v) => s.sendUploadProgress = v),
            sw('Офлайн после отправки', s.sendOfflinePacketAfterOnline, (v) => s.sendOfflinePacketAfterOnline = v,
                sub: 'Сразу сбрасывать «в сети» после своего сообщения'),
            sw('Читать после действия', s.markReadAfterAction, (v) => s.markReadAfterAction = v,
                sub: 'Отмечать чат прочитанным, когда вы в нём пишете'),
            sw('Отложенная отправка', s.useScheduledMessages, (v) => s.useScheduledMessages = v,
                sub: 'В режиме призрака сообщения уходят через ~20 с, чтобы не светить «в сети»'),
            ListTile(
              title: const Text('Отправлять без звука'),
              trailing: DropdownButton<SendWithoutSound>(
                value: s.sendWithoutSound,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: SendWithoutSound.never, child: Text('Никогда')),
                  DropdownMenuItem(value: SendWithoutSound.inGhostMode, child: Text('В призраке')),
                  DropdownMenuItem(value: SendWithoutSound.always, child: Text('Всегда')),
                ],
                onChanged: (v) {
                  s.sendWithoutSound = v!;
                  s.save();
                },
              ),
            ),
            const SectionHeader('Шпионские функции'),
            sw('Сохранять удалённые', s.saveDeletedMessages, (v) => s.saveDeletedMessages = v),
            sw('Сохранять историю правок', s.saveMessagesHistory, (v) => s.saveMessagesHistory = v),
            sw('Сохранять в чатах с ботами', s.saveForBots, (v) => s.saveForBots = v),
            const _StorageTile(),
            const SectionHeader('Фильтры'),
            sw('Включить фильтры', s.filtersEnabled, (v) => s.filtersEnabled = v),
            sw('Фильтры в группах и личке', s.filtersEnabledInChats, (v) => s.filtersEnabledInChats = v,
                sub: 'По умолчанию — только в каналах'),
            sw('Скрывать от заблокированных', s.hideFromBlocked, (v) => s.hideFromBlocked = v),
            ListTile(
              leading: const Icon(Icons.filter_alt_outlined),
              title: const Text('Регулярные выражения'),
              subtitle: Text('${s.filters.length} шт.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FiltersScreen())),
            ),
            const SectionHeader('Внешний вид'),
            sw('Полупрозрачные удалённые', s.semiTransparentDeletedMessages, (v) => s.semiTransparentDeletedMessages = v),
            ListTile(
              title: const Text('Метка удалённых'),
              trailing: Text(s.deletedMark),
              onTap: () => _editText(context, 'Метка удалённых', s.deletedMark, (v) => s.deletedMark = v),
            ),
            ListTile(
              title: const Text('Метка изменённых'),
              trailing: Text(s.editedMark),
              onTap: () => _editText(context, 'Метка изменённых', s.editedMark, (v) => s.editedMark = v),
            ),
            sw('Показывать ID', s.showPeerId, (v) => s.showPeerId = v),
            sw('Секунды во времени', s.showMessageSeconds, (v) => s.showMessageSeconds = v),
            sw('Убирать «залго»', s.filterZalgo, (v) => s.filterZalgo = v),
            sw('Режим стримера', s.streamerMode, (v) => s.streamerMode = v, sub: 'Скрывает аватарки и превью в списке'),
            const SectionHeader('Аккаунт'),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text('Выйти', style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Выйти из аккаунта?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Выйти')),
                    ],
                  ),
                );
                if (ok == true) {
                  await TdService.instance.logOut();
                  if (context.mounted) Navigator.popUntil(context, (r) => r.isFirst);
                }
              },
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Неофициальный порт функций AyuGram (© Radolyn, github.com/AyuGram) на iOS. '
                'Основан на TDLib. Использование нарушает ToS Telegram — на свой риск.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ]);
        },
      ),
    );
  }

  Future<void> _editText(BuildContext context, String title, String value, void Function(String) set) async {
    final c = TextEditingController(text: value);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('OK'))],
      ),
    );
    if (res != null) {
      set(res);
      AyuSettings.instance.save();
    }
  }
}

class _StorageTile extends StatefulWidget {
  const _StorageTile();

  @override
  State<_StorageTile> createState() => _StorageTileState();
}

class _StorageTileState extends State<_StorageTile> {
  late Future<(int, int)> _stats = MessageStore.instance.stats();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(int, int)>(
      future: _stats,
      builder: (context, snap) {
        final (d, e) = snap.data ?? (0, 0);
        return ListTile(
          leading: const Icon(Icons.storage),
          title: const Text('Очистить базу AyuGram'),
          subtitle: Text('Удалённых: $d · правок: $e'),
          onTap: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Удалить все сохранённые удалённые сообщения и правки?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
                  TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Очистить')),
                ],
              ),
            );
            if (ok == true) {
              await MessageStore.instance.clearAll();
              setState(() => _stats = MessageStore.instance.stats());
            }
          },
        );
      },
    );
  }
}

class FiltersScreen extends StatefulWidget {
  const FiltersScreen({super.key});

  @override
  State<FiltersScreen> createState() => _FiltersScreenState();
}

class _FiltersScreenState extends State<FiltersScreen> {
  final s = AyuSettings.instance;

  Future<void> _edit([RegexFilter? f]) async {
    final text = TextEditingController(text: f?.text ?? '');
    var reversed = f?.reversed ?? false;
    var ci = f?.caseInsensitive ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(f == null ? 'Новый фильтр' : 'Фильтр'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: text, autofocus: true, decoration: const InputDecoration(labelText: 'Регулярное выражение')),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Без учёта регистра'),
              value: ci,
              onChanged: (v) => set(() => ci = v!),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Инвертировать'),
              subtitle: const Text('Скрывать всё, что НЕ совпадает'),
              value: reversed,
              onChanged: (v) => set(() => reversed = v!),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
          ],
        ),
      ),
    );
    if (ok != true || text.text.isEmpty) return;
    try {
      RegExp(text.text);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Неверное регулярное выражение')));
      }
      return;
    }
    setState(() {
      if (f == null) {
        s.filters.add(RegexFilter(
          id: '${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(9999)}',
          text: text.text,
          reversed: reversed,
          caseInsensitive: ci,
        ));
      } else {
        f
          ..text = text.text
          ..reversed = reversed
          ..caseInsensitive = ci
          ..invalidate();
      }
    });
    s.save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Фильтры')),
      floatingActionButton: FloatingActionButton(onPressed: _edit, child: const Icon(Icons.add)),
      body: s.filters.isEmpty
          ? const Center(child: Text('Нет фильтров.\nНапример: (?i)реклама|промокод', textAlign: TextAlign.center))
          : ListView(children: [
              for (final f in s.filters)
                Dismissible(
                  key: ValueKey(f.id),
                  onDismissed: (_) {
                    setState(() => s.filters.remove(f));
                    s.save();
                  },
                  background: Container(color: Colors.red),
                  child: SwitchListTile(
                    title: Text(f.text, style: const TextStyle(fontFamily: 'Menlo')),
                    subtitle: Text([if (f.caseInsensitive) 'без регистра', if (f.reversed) 'инверсия'].join(', ')),
                    value: f.enabled,
                    onChanged: (v) {
                      setState(() => f.enabled = v);
                      s.save();
                    },
                    secondary: IconButton(icon: const Icon(Icons.edit), onPressed: () => _edit(f)),
                  ),
                ),
            ]),
    );
  }
}
