import 'dart:io';

import 'package:flutter/material.dart';

import '../ayu/ayu_settings.dart';
import '../td/td_client.dart';
import '../td/td_service.dart';
import 'ayu_theme.dart';

/// Градиенты аватарок tdesktop (historyPeerNUserpicBg → …Bg2), индекс как у peerNames.
const _userpicGradients = [
  [Color(0xffff885e), Color(0xffff516a)], // red
  [Color(0xffa0de7e), Color(0xff54cb68)], // green
  [Color(0xffffcd6a), Color(0xffffa85c)], // yellow
  [Color(0xff72d5fd), Color(0xff2a9ef1)], // blue
  [Color(0xffe0a2f3), Color(0xffd669ed)], // violet
  [Color(0xffffa8a8), Color(0xffff719a)], // pink
  [Color(0xff53edd6), Color(0xff28c9b7)], // sea
  [Color(0xffffcd6a), Color(0xffffa85c)], // orange
];

/// Data::DecideColorIndex из tdesktop: map[bareId % 7].
int peerColorIndex(int id) {
  final bare = id <= -1000000000000 ? -id - 1000000000000 : id.abs();
  const map = [0, 7, 4, 1, 6, 3, 5];
  return map[bare % 7];
}

Color peerColor(BuildContext context, int id) => context.ayu.peerNames[peerColorIndex(id)];

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
              errorBuilder: (_, _, _) => _ph(context));
        }
        return _ph(context);
      },
    );
  }

  Widget _ph(BuildContext context) =>
      placeholder ?? SizedBox(width: width, height: height, child: ColoredBox(color: context.ayu.windowBgOver));
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.id, required this.title, this.photo, this.radius = 27, this.saved = false});

  final int id;
  final String title;
  final TdObject? photo; // chatPhotoInfo / profilePhoto
  final double radius;
  final bool saved;

  @override
  Widget build(BuildContext context) {
    final streamer = AyuSettings.instance.streamerMode;
    final words = title.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final letters = words.isEmpty ? '?' : words.take(2).map((w) => w.characters.first).join().toUpperCase();
    final g = saved ? const [Color(0xff72d5fd), Color(0xff2a9ef1)] : _userpicGradients[peerColorIndex(id)];
    final fallback = Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: g),
      ),
      child: saved
          ? Icon(Icons.bookmark, color: Colors.white, size: radius)
          : Text(streamer ? '' : letters,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: radius * 0.72)),
    );
    final small = photo?['small'] as TdObject?;
    if (small == null || streamer || saved) return fallback;
    return ClipOval(child: TdImage(small, width: radius * 2, height: radius * 2, placeholder: fallback));
  }
}

/// Значок верификации.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.size = 16});
  final double size;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Icon(Icons.verified, size: size, color: context.ayu.windowActiveTextFg),
      );
}

/// Заголовок секции настроек tdesktop (синий, жирный).
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 6),
        child: Text(text,
            style: TextStyle(fontSize: 14, color: context.ayu.lightButtonFg, fontWeight: FontWeight.w600)),
      );
}

/// Секция настроек, отделённая полосой boxDividerBg, как в настройках AyuGram Desktop.
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, this.title, required this.children, this.footer, this.divider = true});
  final String? title;
  final List<Widget> children;
  final String? footer;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (title != null) SectionHeader(title!),
      ...children,
      if (footer != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 6, 22, 10),
          child: Text(footer!, style: TextStyle(fontSize: 13, color: c.windowSubTextFg, height: 1.35)),
        ),
      if (divider) Container(height: 8, margin: const EdgeInsets.only(top: 8), color: c.dividerBg),
    ]);
  }
}

/// Строка с переключателем (SettingsButton + toggle).
class CheckCell extends StatelessWidget {
  const CheckCell({super.key, required this.title, required this.value, required this.onChanged, this.subtitle, this.icon});
  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: EdgeInsets.fromLTRB(icon == null ? 22 : 18, 11, 16, 11),
        child: Row(children: [
          if (icon != null) Padding(padding: const EdgeInsets.only(right: 22), child: Icon(icon, color: c.menuIconFg, size: 22)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 15, color: c.windowFg)),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle!, style: TextStyle(fontSize: 13, color: c.windowSubTextFg)),
                ),
            ]),
          ),
          AyuToggle(value: value, onChanged: onChanged),
        ]),
      ),
    );
  }
}

/// Строка-кнопка (SettingsButton).
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
        height: 48,
        child: Row(children: [
          if (icon != null)
            Padding(padding: const EdgeInsets.only(left: 18, right: 22), child: Icon(icon, color: color ?? c.menuIconFg, size: 22))
          else
            const SizedBox(width: 22),
          Expanded(child: Text(title, style: TextStyle(fontSize: 15, color: color ?? c.windowFg))),
          if (value != null)
            Padding(
              padding: const EdgeInsets.only(right: 22),
              child: Text(value!, style: TextStyle(fontSize: 15, color: c.lightButtonFg)),
            ),
        ]),
      ),
    );
  }
}

/// Синяя кнопка tdesktop (activeButtonBg, скругление 6).
class AyuButton extends StatelessWidget {
  const AyuButton({super.key, required this.text, this.onPressed, this.busy = false});
  final String text;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    return SizedBox(
      height: 44,
      child: Material(
        color: c.activeButtonBg,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: busy ? null : onPressed,
          child: Center(
            child: busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(text, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}

/// Переключатель tdesktop (st::defaultToggle): таблетка с кружком.
class AyuToggle extends StatelessWidget {
  const AyuToggle({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    final on = c.activeLineFg;
    final off = c.dark ? const Color(0xff5c6a77) : const Color(0xffadb2b5);
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: SizedBox(
        width: 40,
        height: 24,
        child: Stack(alignment: Alignment.center, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 34,
            height: 14,
            decoration: BoxDecoration(color: value ? on : off, borderRadius: BorderRadius.circular(7)),
          ),
          AnimatedAlign(
            duration: const Duration(milliseconds: 150),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: c.windowBg,
                shape: BoxShape.circle,
                border: Border.all(color: value ? on : off, width: 2),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
