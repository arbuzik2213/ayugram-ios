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
          Widget sw(String title, bool value, void Function(bool) set, {String? sub}) => CheckCell(
                title: title,
                subtitle: sub,
                value: value,
                onChanged: (v) {
                  set(v);
                  s.save();
                },
              );

          return ListView(padding: EdgeInsets.zero, children: [
            SettingsSection(title: 'Режим призрака', children: [
              CheckCell(title: 'Режим призрака', value: s.isGhostModeActive, onChanged: s.setGhostModeEnabled),
              sw('Не читать сообщения', !s.sendReadMessages, (v) => s.sendReadMessages = !v),
              sw('Не отправлять «в сети»', !s.sendOnlinePackets, (v) => s.sendOnlinePackets = !v),
              sw('Не отправлять «печатает»', !s.sendUploadProgress, (v) => s.sendUploadProgress = !v),
              sw('Офлайн после «в сети»', s.sendOfflinePacketAfterOnline, (v) => s.sendOfflinePacketAfterOnline = v),
            ]),
            SettingsSection(
              footer: 'В режиме призрака сообщения отправляются отложенными (~20 с), чтобы не показывать «в сети».',
              children: [
                sw('Читать после действия', s.markReadAfterAction, (v) => s.markReadAfterAction = v),
                sw('Отложенные сообщения', s.useScheduledMessages, (v) => s.useScheduledMessages = v),
                TextCell(
                  title: 'Отправлять без звука',
                  value: switch (s.sendWithoutSound) {
                    SendWithoutSound.never => 'Никогда',
                    SendWithoutSound.inGhostMode => 'В призраке',
                    SendWithoutSound.always => 'Всегда',
                  },
                  onTap: () {
                    s.sendWithoutSound = SendWithoutSound.values[(s.sendWithoutSound.index + 1) % 3];
                    s.save();
                  },
                ),
              ],
            ),
            SettingsSection(title: 'Шпионские функции', children: [
              sw('Сохранять удалённые', s.saveDeletedMessages, (v) => s.saveDeletedMessages = v),
              sw('Сохранять историю правок', s.saveMessagesHistory, (v) => s.saveMessagesHistory = v),
              sw('Сохранять в чатах с ботами', s.saveForBots, (v) => s.saveForBots = v),
              const _StorageTile(),
            ]),
            SettingsSection(title: 'Фильтры', children: [
              sw('Включить фильтры', s.filtersEnabled, (v) => s.filtersEnabled = v),
              sw('Фильтры в чатах', s.filtersEnabledInChats, (v) => s.filtersEnabledInChats = v,
                  sub: 'По умолчанию — только в каналах'),
              sw('Скрывать от заблокированных', s.hideFromBlocked, (v) => s.hideFromBlocked = v),
              TextCell(
                title: 'Регулярные выражения',
                value: '${s.filters.length}',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FiltersScreen())),
              ),
            ]),
            SettingsSection(title: 'Кастомизация', children: [
              sw('Ночной режим', s.nightMode, (v) => s.nightMode = v),
              TextCell(
                title: 'Метка удалённых',
                value: s.deletedMark,
                onTap: () => _editText(context, 'Метка удалённых', s.deletedMark, (v) => s.deletedMark = v),
              ),
              TextCell(
                title: 'Метка изменённых',
                value: s.editedMark,
                onTap: () => _editText(context, 'Метка изменённых', s.editedMark, (v) => s.editedMark = v),
              ),
              sw('Полупрозрачные удалённые', s.semiTransparentDeletedMessages, (v) => s.semiTransparentDeletedMessages = v),
              sw('Показывать ID', s.showPeerId, (v) => s.showPeerId = v),
              sw('Секунды во времени', s.showMessageSeconds, (v) => s.showMessageSeconds = v),
              sw('Фильтровать «залго»', s.filterZalgo, (v) => s.filterZalgo = v),
              sw('Режим стримера', s.streamerMode, (v) => s.streamerMode = v),
            ]),
            SettingsSection(
              footer: 'Неофициальный порт AyuGram (© Radolyn, github.com/AyuGram) на iOS. '
                  'Использование нарушает ToS Telegram — на свой риск.',
              children: [
                TextCell(
                  title: 'Выйти',
                  icon: Icons.logout,
                  color: const Color(0xffe56555),
                  onTap: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Выйти из аккаунта?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Выйти')),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await TdService.instance.logOut();
                      if (context.mounted) Navigator.popUntil(context, (r) => r.isFirst);
                    }
                  },
                ),
              ],
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
        return TextCell(
          title: 'Очистить базу AyuGram',
          value: '$d / $e',
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
