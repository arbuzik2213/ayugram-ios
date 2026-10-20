import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Палитры AyuGram Desktop: ночная — Telegram/Resources/night.tdesktop-theme,
/// дневная — lib_ui/ui/colors.palette. Имена полей — ключи палитры tdesktop.
@immutable
class AyuColors extends ThemeExtension<AyuColors> {
  const AyuColors({
    required this.dark,
    required this.windowBg,
    required this.windowBgOver,
    required this.windowBgRipple,
    required this.windowFg,
    required this.windowBoldFg,
    required this.windowSubTextFg,
    required this.windowActiveTextFg,
    required this.activeLineFg,
    required this.activeButtonBg,
    required this.lightButtonFg,
    required this.menuIconFg,
    required this.attentionFg,
    required this.dividerBg,
    required this.inputBorderFg,
    required this.filterInputBg,
    required this.placeholderFg,
    required this.dialogsTextFg,
    required this.dialogsTextFgService,
    required this.dialogsDateFg,
    required this.dialogsUnreadBg,
    required this.dialogsUnreadBgMuted,
    required this.dialogsSentIconFg,
    required this.dialogsDraftFg,
    required this.dialogsBgActive,
    required this.historyBg,
    required this.msgInBg,
    required this.msgOutBg,
    required this.historyTextInFg,
    required this.historyTextOutFg,
    required this.historyLinkInFg,
    required this.historyLinkOutFg,
    required this.msgInDateFg,
    required this.msgOutDateFg,
    required this.historyOutIconFg,
    required this.msgInReplyBarColor,
    required this.msgOutReplyBarColor,
    required this.msgInServiceFg,
    required this.msgOutServiceFg,
    required this.msgServiceBg,
    required this.msgFileInBg,
    required this.msgFileOutBg,
    required this.historyComposeAreaBg,
    required this.historyComposeIconFg,
    required this.historySendIconFg,
    required this.historyToDownBg,
    required this.peerNames,
    required this.online,
  });

  final bool dark;
  final Color windowBg, windowBgOver, windowBgRipple, windowFg, windowBoldFg, windowSubTextFg, windowActiveTextFg;
  final Color activeLineFg, activeButtonBg, lightButtonFg, menuIconFg, attentionFg, dividerBg, inputBorderFg;
  final Color filterInputBg, placeholderFg;
  final Color dialogsTextFg, dialogsTextFgService, dialogsDateFg, dialogsUnreadBg, dialogsUnreadBgMuted;
  final Color dialogsSentIconFg, dialogsDraftFg, dialogsBgActive;
  final Color historyBg, msgInBg, msgOutBg, historyTextInFg, historyTextOutFg, historyLinkInFg, historyLinkOutFg;
  final Color msgInDateFg, msgOutDateFg, historyOutIconFg, msgInReplyBarColor, msgOutReplyBarColor;
  final Color msgInServiceFg, msgOutServiceFg, msgServiceBg, msgFileInBg, msgFileOutBg;
  final Color historyComposeAreaBg, historyComposeIconFg, historySendIconFg, historyToDownBg;
  final List<Color> peerNames;
  final Color online;

  static const night = AyuColors(
    dark: true,
    windowBg: Color(0xff17212b),
    windowBgOver: Color(0xff232e3c),
    windowBgRipple: Color(0xff24303d),
    windowFg: Color(0xfff5f5f5),
    windowBoldFg: Color(0xffe9e8e8),
    windowSubTextFg: Color(0xff708499),
    windowActiveTextFg: Color(0xff6ab3f3),
    activeLineFg: Color(0xff6396cb),
    activeButtonBg: Color(0xff2f6ea5),
    lightButtonFg: Color(0xff6ab2f2),
    menuIconFg: Color(0xff6c7883),
    attentionFg: Color(0xffec3942),
    dividerBg: Color(0xff232e3c),
    inputBorderFg: Color(0xff313c49),
    filterInputBg: Color(0xff242f3d),
    placeholderFg: Color(0xff6d7883),
    dialogsTextFg: Color(0xff7f91a4),
    dialogsTextFgService: Color(0xff73b9f5),
    dialogsDateFg: Color(0xff8696a8),
    dialogsUnreadBg: Color(0xff4082bc),
    dialogsUnreadBgMuted: Color(0xff3e546a),
    dialogsSentIconFg: Color(0xff72bcfd),
    dialogsDraftFg: Color(0xffff525d),
    dialogsBgActive: Color(0xff2b5278),
    historyBg: Color(0xff0e1621),
    msgInBg: Color(0xff182533),
    msgOutBg: Color(0xff2b5278),
    historyTextInFg: Color(0xfff5f5f5),
    historyTextOutFg: Color(0xffe4ecf2),
    historyLinkInFg: Color(0xff70baf5),
    historyLinkOutFg: Color(0xff83caff),
    msgInDateFg: Color(0xff6d7f8f),
    msgOutDateFg: Color(0xff7da8d3),
    historyOutIconFg: Color(0xff6bbfff),
    msgInReplyBarColor: Color(0xff429bdb),
    msgOutReplyBarColor: Color(0xff65b9f4),
    msgInServiceFg: Color(0xff71bafa),
    msgOutServiceFg: Color(0xff90caff),
    msgServiceBg: Color(0xd5213040),
    msgFileInBg: Color(0xff3f96d0),
    msgFileOutBg: Color(0xff4c9ce2),
    historyComposeAreaBg: Color(0xff17212b),
    historyComposeIconFg: Color(0xff6c7883),
    historySendIconFg: Color(0xff5288c1),
    historyToDownBg: Color(0xff1d2b3a),
    peerNames: [
      Color(0xfffb6169), Color(0xff85de85), Color(0xfff3bc5c), Color(0xff65bdf3),
      Color(0xffb48bf2), Color(0xffff5694), Color(0xff62d4e3), Color(0xfffaa357),
    ],
    online: Color(0xff4dc920),
  );

  static const day = AyuColors(
    dark: false,
    windowBg: Color(0xffffffff),
    windowBgOver: Color(0xfff1f1f1),
    windowBgRipple: Color(0xffe5e5e5),
    windowFg: Color(0xff000000),
    windowBoldFg: Color(0xff222222),
    windowSubTextFg: Color(0xff999999),
    windowActiveTextFg: Color(0xff168acd),
    activeLineFg: Color(0xff37a1de),
    activeButtonBg: Color(0xff40a7e3),
    lightButtonFg: Color(0xff168acd),
    menuIconFg: Color(0xff999999),
    attentionFg: Color(0xffd14e4e),
    dividerBg: Color(0xfff1f1f1),
    inputBorderFg: Color(0xffe0e0e0),
    filterInputBg: Color(0xfff1f1f1),
    placeholderFg: Color(0xff999999),
    dialogsTextFg: Color(0xff999999),
    dialogsTextFgService: Color(0xff168acd),
    dialogsDateFg: Color(0xff999999),
    dialogsUnreadBg: Color(0xff40a7e3),
    dialogsUnreadBgMuted: Color(0xffbbbbbb),
    dialogsSentIconFg: Color(0xff5dc452),
    dialogsDraftFg: Color(0xffdd4b39),
    dialogsBgActive: Color(0xff419fd9),
    historyBg: Color(0xffdfe7ea),
    msgInBg: Color(0xffffffff),
    msgOutBg: Color(0xffe1fec6),
    historyTextInFg: Color(0xff000000),
    historyTextOutFg: Color(0xff000000),
    historyLinkInFg: Color(0xff007aff),
    historyLinkOutFg: Color(0xff1d63b8),
    msgInDateFg: Color(0xff8e8e93),
    msgOutDateFg: Color(0xff4ba64f),
    historyOutIconFg: Color(0xff4ba64f),
    msgInReplyBarColor: Color(0xff37a1de),
    msgOutReplyBarColor: Color(0xff5eb854),
    msgInServiceFg: Color(0xff168acd),
    msgOutServiceFg: Color(0xff45a32d),
    msgServiceBg: Color(0x7f517c41),
    msgFileInBg: Color(0xff40a7e3),
    msgFileOutBg: Color(0xff5fbe67),
    historyComposeAreaBg: Color(0xffffffff),
    historyComposeIconFg: Color(0xff999999),
    historySendIconFg: Color(0xff40a7e3),
    historyToDownBg: Color(0xffffffff),
    peerNames: [
      Color(0xffc03d33), Color(0xff4fad2d), Color(0xffd09306), Color(0xff168acd),
      Color(0xff8544d6), Color(0xffcd4073), Color(0xff2996ad), Color(0xffce671b),
    ],
    online: Color(0xff4dc920),
  );

  @override
  AyuColors copyWith() => this;

  @override
  AyuColors lerp(AyuColors? other, double t) => t < 0.5 ? this : (other ?? this);
}

extension AyuColorsX on BuildContext {
  AyuColors get ayu => Theme.of(this).extension<AyuColors>() ?? AyuColors.night;
}

const ayuFont = 'OpenSans';

ThemeData buildAyuTheme(bool night) {
  final c = night ? AyuColors.night : AyuColors.day;
  final b = night ? Brightness.dark : Brightness.light;
  final base = ThemeData(
    brightness: b,
    useMaterial3: false,
    fontFamily: ayuFont,
    // Эмодзи и флаги: системный шрифт iOS (в тестах — Noto Color Emoji).
    fontFamilyFallback: const ['Apple Color Emoji', 'NotoColorEmoji'],
    colorScheme: ColorScheme.fromSeed(seedColor: c.activeButtonBg, brightness: b).copyWith(
      primary: c.windowActiveTextFg,
      secondary: c.windowActiveTextFg,
      surface: c.windowBg,
      onSurface: c.windowFg,
    ),
    scaffoldBackgroundColor: c.windowBg,
    canvasColor: c.windowBg,
    dividerColor: c.inputBorderFg,
    splashColor: c.windowBgRipple,
    highlightColor: c.windowBgOver,
    extensions: [c],
  );
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: c.windowBg,
      foregroundColor: c.windowBoldFg,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: c.dark ? const Color(0xff0e1621) : c.inputBorderFg, width: 1)),
      titleTextStyle: TextStyle(fontFamily: ayuFont, fontFamilyFallback: const ['Apple Color Emoji', 'NotoColorEmoji'], color: c.windowBoldFg, fontSize: 16, fontWeight: FontWeight.w600),
      iconTheme: IconThemeData(color: c.menuIconFg),
      actionsIconTheme: IconThemeData(color: c.menuIconFg),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(c.windowBg),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.activeLineFg : c.inputBorderFg),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    textTheme: base.textTheme.apply(bodyColor: c.windowFg, displayColor: c.windowFg, fontFamily: ayuFont),
    iconTheme: IconThemeData(color: c.menuIconFg),
    listTileTheme: ListTileThemeData(textColor: c.windowFg, iconColor: c.menuIconFg),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.windowBg, modalBackgroundColor: c.windowBg),
    popupMenuTheme: PopupMenuThemeData(
      color: c.windowBg,
      textStyle: TextStyle(fontFamily: ayuFont, color: c.windowFg, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.windowBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      titleTextStyle: TextStyle(fontFamily: ayuFont, color: c.windowBoldFg, fontSize: 17, fontWeight: FontWeight.w600),
      contentTextStyle: TextStyle(fontFamily: ayuFont, color: c.windowFg, fontSize: 14),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.lightButtonFg,
        textStyle: const TextStyle(fontFamily: ayuFont, fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.dark ? const Color(0xff242f3d) : const Color(0xdd000000),
      contentTextStyle: const TextStyle(fontFamily: ayuFont, color: Colors.white, fontSize: 14),
      behavior: SnackBarBehavior.floating,
    ),
    textSelectionTheme: TextSelectionThemeData(cursorColor: c.activeLineFg, selectionHandleColor: c.activeLineFg),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.windowActiveTextFg),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.activeButtonBg : null),
    ),
  );
}

/// Фон истории: градиент + свой «дудл»-узор (звёздочки, сердечки, кружки, самолётики).
class AyuWallpaper extends StatelessWidget {
  const AyuWallpaper({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.ayu;
    final colors = c.dark
        ? const [Color(0xff0e1621), Color(0xff16222f), Color(0xff0f1a26)]
        : const [Color(0xffd9e8bd), Color(0xffaecf94), Color(0xffc9df9f)];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
      ),
      child: Stack(fit: StackFit.expand, children: [
        RepaintBoundary(
          child: CustomPaint(painter: _DoodlePainter(c.dark ? Colors.white.withValues(alpha: 0.05) : const Color(0x1f2e5a1c))),
        ),
        child,
      ]),
    );
  }
}

class _DoodlePainter extends CustomPainter {
  _DoodlePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    const step = 64.0;
    var seed = 7;
    double rnd() {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return seed / 0x7fffffff;
    }

    for (var y = -step / 2; y < size.height + step; y += step) {
      for (var x = -step / 2 + ((y / step).round().isOdd ? step / 2 : 0); x < size.width + step; x += step) {
        final cx = x + rnd() * 18, cy = y + rnd() * 18;
        canvas.save();
        canvas.translate(cx, cy);
        canvas.rotate((rnd() - 0.5) * 1.2);
        switch ((rnd() * 6).floor()) {
          case 0: // звезда
            final path = Path();
            for (var i = 0; i < 10; i++) {
              final r = i.isEven ? 9.0 : 4.0;
              final a = -1.5708 + i * 0.6283;
              final pt = Offset(r * _cos(a), r * _sin(a));
              i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
            }
            canvas.drawPath(path..close(), p);
          case 1: // сердечко
            final path = Path()
              ..moveTo(0, 7)
              ..cubicTo(-12, -2, -6, -11, 0, -4)
              ..cubicTo(6, -11, 12, -2, 0, 7);
            canvas.drawPath(path, p);
          case 2: // кружок
            canvas.drawCircle(Offset.zero, 6, p);
          case 3: // бумажный самолётик
            final path = Path()
              ..moveTo(-10, 0)
              ..lineTo(10, -7)
              ..lineTo(3, 8)
              ..lineTo(0, 2)
              ..close()
              ..moveTo(0, 2)
              ..lineTo(10, -7);
            canvas.drawPath(path, p);
          case 4: // волна
            final path = Path()
              ..moveTo(-10, 0)
              ..quadraticBezierTo(-5, -6, 0, 0)
              ..quadraticBezierTo(5, 6, 10, 0);
            canvas.drawPath(path, p);
          default: // облачко-сообщение
            canvas.drawRRect(RRect.fromLTRBR(-9, -6, 9, 5, const Radius.circular(5)), p);
            canvas.drawLine(const Offset(-4, 5), const Offset(-6, 9), p);
        }
        canvas.restore();
      }
    }
  }

  static double _sin(double a) => math.sin(a);
  static double _cos(double a) => math.cos(a);

  @override
  bool shouldRepaint(_DoodlePainter old) => old.color != color;
}
