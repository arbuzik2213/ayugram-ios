import 'dart:io';

import 'package:flutter/material.dart';

import '../ayu/ayu_settings.dart';
import '../td/td_client.dart';
import '../td/td_service.dart';
import 'ayu_theme.dart';

const ayuAccent = Color(0xff527da3);

/// Цвета аватарок Telegram Android (верх/низ градиента).
const _avatarGradients = [
  [Color(0xffff845e), Color(0xffd45246)],
  [Color(0xfffebb5b), Color(0xfff68136)],
  [Color(0xffb694f9), Color(0xff6c61df)],
  [Color(0xff9ad164), Color(0xff46ba43)],
  [Color(0xff53edd6), Color(0xff28c9b7)],
  [Color(0xff5bcbe3), Color(0xff359ad4)],
  [Color(0xffff8aac), Color(0xffd95574)],
];

/// Цвета имён в группах (avatar_nameInMessage*).
const _nameColors = [
  Color(0xffca5650), Color(0xffd87b29), Color(0xff9b66dc), Color(0xff50b232),
  Color(0xff379eb8), Color(0xff4e92cc), Color(0xffcf5c95),
];

int _colorIndex(int id) => const [0, 6, 2, 3, 4, 5, 1][id.abs() % 7];

Color peerColor(int id) => _nameColors[_colorIndex(id)];

/// Картинка из файла TDLib: сама запускает загрузку и перерисовывается по готовности.
class TdImage extends StatelessWidget {
  const TdImage(this.file, {super.key, this.fit = BoxFit.cover, this.width, this.height, this.placeholder});

  final TdObject file;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TdObject>(
      valueListenable: TdService.instance.file(file),
      builder: (context, f, _) {
        final local = f['local'] as TdObject?;
        final path = local?['path'] as String?;
        if (local?['is_downloading_completed'] == true && path != null && path.isNotEmpty) {
          return Image.file(File(path), fit: fit, width: width, height: height, gaplessPlayback: true,
              errorBuilder: (_, __, ___) => _ph());
        }
        return _ph();
      },
    );
  }

  Widget _ph() => placeholder ?? SizedBox(width: width, height: height, child: const ColoredBox(color: Color(0x22888888)));
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.id, required this.title, this.photo, this.radius = 26});

  final int id;
  final String title;
  final TdObject? photo; // chatPhotoInfo / profilePhoto
  final double radius;

  @override
  Widget build(BuildContext context) {
    final streamer = AyuSettings.instance.streamerMode;
    final letters = title.trim().isEmpty
        ? '?'
        : title.trim().split(RegExp(r'\s+')).take(2).map((w) => w.characters.first).join().toUpperCase();
    final g = _avatarGradients[_colorIndex(id)];
    final fallback = Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: g),
      ),
      child: Text(streamer ? '•' : letters,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: radius * 0.72)),
    );
    final small = photo?['small'] as TdObject?;
    if (small == null || streamer) return fallback;
    return ClipOval(
      child: TdImage(small, width: radius * 2, height: radius * 2, placeholder: fallback),
    );
  }
}

/// Заголовок секции настроек в стиле Telegram Android (синий, на белом).
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(21, 15, 21, 6),
        child: Text(text,
            style: TextStyle(fontSize: 15, color: context.ayu.blueHeader, fontWeight: FontWeight.w600)),
      );
}

/// Белая секция настроек на сером фоне, как в Telegram Android.
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, this.title, required this.children, this.footer});
  final String? title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        color: c.windowBg,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null) SectionHeader(title!),
          ...children,
        ]),
      ),
      if (footer != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(21, 10, 21, 14),
          child: Text(footer!, style: TextStyle(fontSize: 14, color: c.grayText)),
        )
      else
        const SizedBox(height: 12),
    ]);
  }
}

/// Строка-переключатель в стиле TextCheckCell.
class CheckCell extends StatelessWidget {
  const CheckCell({super.key, required this.title, required this.value, required this.onChanged, this.subtitle});
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(21, 10, 12, 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 16, color: c.text)),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(subtitle!, style: TextStyle(fontSize: 13, color: c.grayText)),
                ),
            ]),
          ),
          Switch(value: value, onChanged: onChanged),
        ]),
      ),
    );
  }
}

/// Строка-кнопка в стиле TextCell / TextSettingsCell.
class TextCell extends StatelessWidget {
  const TextCell({super.key, required this.title, this.icon, this.value, this.onTap, this.color});
  final String title;
  final IconData? icon;
  final String? value;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 50,
        child: Row(children: [
          if (icon != null) Padding(padding: const EdgeInsets.only(left: 20, right: 12), child: Icon(icon, color: color ?? c.menuIcon))
          else const SizedBox(width: 21),
          Expanded(child: Text(title, style: TextStyle(fontSize: 16, color: color ?? c.text))),
          if (value != null)
            Padding(
              padding: const EdgeInsets.only(right: 21),
              child: Text(value!, style: TextStyle(fontSize: 16, color: c.blueText)),
            ),
        ]),
      ),
    );
  }
}
