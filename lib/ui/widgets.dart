import 'dart:io';

import 'package:flutter/material.dart';

import '../ayu/ayu_settings.dart';
import '../td/td_client.dart';
import '../td/td_service.dart';

const ayuAccent = Color(0xFF8E7CFF);

Color peerColor(int id) {
  const colors = [
    Color(0xFFE17076), Color(0xFFFAA774), Color(0xFFA695E7), Color(0xFF7BC862),
    Color(0xFF6EC9CB), Color(0xFF65AADD), Color(0xFFEE7AAE),
  ];
  return colors[id.abs() % colors.length];
}

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
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: peerColor(id),
      child: Text(streamer ? '•' : letters,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: radius * 0.7)),
    );
    final small = photo?['small'] as TdObject?;
    if (small == null || streamer) return fallback;
    return ClipOval(
      child: TdImage(small, width: radius * 2, height: radius * 2, placeholder: fallback),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(text.toUpperCase(),
            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
      );
}
