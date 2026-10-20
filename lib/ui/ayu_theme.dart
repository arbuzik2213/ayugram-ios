import 'package:flutter/material.dart';

/// Цвета стандартных тем AyuGram4A (Telegram Android):
/// светлая — defaultColors из ThemeColors.java, тёмная — assets/night.attheme.
@immutable
class AyuColors extends ThemeExtension<AyuColors> {
  const AyuColors({
    required this.actionBar,
    required this.actionBarTitle,
    required this.actionBarSubtitle,
    required this.windowBg,
    required this.windowGray,
    required this.text,
    required this.grayText,
    required this.blueText,
    required this.blueHeader,
    required this.divider,
    required this.unread,
    required this.unreadMuted,
    required this.chatName,
    required this.chatMessage,
    required this.chatNameMessage,
    required this.chatDate,
    required this.sentCheck,
    required this.pinnedIcon,
    required this.fab,
    required this.menuBg,
    required this.menuText,
    required this.menuIcon,
    required this.menuTop,
    required this.inBubble,
    required this.outBubble,
    required this.textIn,
    required this.textOut,
    required this.inTime,
    required this.outTime,
    required this.outCheck,
    required this.inReplyLine,
    required this.outReplyLine,
    required this.inReplyName,
    required this.outReplyName,
    required this.inForwardName,
    required this.outForwardName,
    required this.panelBg,
    required this.panelHint,
    required this.panelIcons,
    required this.panelSend,
    required this.wallpaper,
    required this.serviceBg,
    required this.switchOn,
    required this.online,
  });

  final Color actionBar, actionBarTitle, actionBarSubtitle;
  final Color windowBg, windowGray, text, grayText, blueText, blueHeader, divider;
  final Color unread, unreadMuted, chatName, chatMessage, chatNameMessage, chatDate, sentCheck, pinnedIcon, fab;
  final Color menuBg, menuText, menuIcon, menuTop;
  final Color inBubble, outBubble, textIn, textOut, inTime, outTime, outCheck;
  final Color inReplyLine, outReplyLine, inReplyName, outReplyName, inForwardName, outForwardName;
  final Color panelBg, panelHint, panelIcons, panelSend;
  final List<Color> wallpaper;
  final Color serviceBg, switchOn, online;

  static const light = AyuColors(
    actionBar: Color(0xff527da3),
    actionBarTitle: Color(0xffffffff),
    actionBarSubtitle: Color(0xffd5e8f7),
    windowBg: Color(0xffffffff),
    windowGray: Color(0xfff0f0f0),
    text: Color(0xff222222),
    grayText: Color(0xff82868a),
    blueText: Color(0xff4092cd),
    blueHeader: Color(0xff3a95d5),
    divider: Color(0xffd9d9d9),
    unread: Color(0xff4ecc5e),
    unreadMuted: Color(0xffc6c9cc),
    chatName: Color(0xff222222),
    chatMessage: Color(0xff8b8d8f),
    chatNameMessage: Color(0xff3c7eb0),
    chatDate: Color(0xff95999c),
    sentCheck: Color(0xff46aa36),
    pinnedIcon: Color(0xffa8a8a8),
    fab: Color(0xff65a9e0),
    menuBg: Color(0xffffffff),
    menuText: Color(0xff444444),
    menuIcon: Color(0xff889198),
    menuTop: Color(0xff598fba),
    inBubble: Color(0xffffffff),
    outBubble: Color(0xffefffde),
    textIn: Color(0xff000000),
    textOut: Color(0xff000000),
    inTime: Color(0xffa1aab3),
    outTime: Color(0xff70b15c),
    outCheck: Color(0xff5db050),
    inReplyLine: Color(0xff599fd8),
    outReplyLine: Color(0xff6eb969),
    inReplyName: Color(0xff3a8ccf),
    outReplyName: Color(0xff55ab4f),
    inForwardName: Color(0xff3886c7),
    outForwardName: Color(0xff55ab4f),
    panelBg: Color(0xffffffff),
    panelHint: Color(0xffa4acb3),
    panelIcons: Color(0xff8e959b),
    panelSend: Color(0xff62b0eb),
    // Стандартные обои Telegram (градиент из четырёх цветов).
    wallpaper: [Color(0xffdbddbb), Color(0xff6ba587), Color(0xffd5d88d), Color(0xff88b884)],
    serviceBg: Color(0x66456a4e),
    switchOn: Color(0xff52ade9),
    online: Color(0xff4bcb1c),
  );

  static const dark = AyuColors(
    actionBar: Color(0xff232326),
    actionBarTitle: Color(0xffffffff),
    actionBarSubtitle: Color(0x73f2f2f2),
    windowBg: Color(0xff181819),
    windowGray: Color(0xff000000),
    text: Color(0xffffffff),
    grayText: Color(0x9efdfdff),
    blueText: Color(0xff64b5ef),
    blueHeader: Color(0xff6cb6f8),
    divider: Color(0xff000000),
    unread: Color(0xff399ef3),
    unreadMuted: Color(0xff454545),
    chatName: Color(0xfff1f1f1),
    chatMessage: Color(0xff828282),
    chatNameMessage: Color(0xffebebeb),
    chatDate: Color(0xff787878),
    sentCheck: Color(0xff46adf3),
    pinnedIcon: Color(0xff646464),
    fab: Color(0xff5ea0db),
    menuBg: Color(0xff242426),
    menuText: Color(0xf4ffffff),
    menuIcon: Color(0xff828282),
    menuTop: Color(0xff1b1b1b),
    inBubble: Color(0xff1f2123),
    outBubble: Color(0xff366caf),
    textIn: Color(0xfffafafa),
    textOut: Color(0xfffafafa),
    inTime: Color(0xff7d7f81),
    outTime: Color(0xff94d3f6),
    outCheck: Color(0xe1c9f0ff),
    inReplyLine: Color(0xff79c4fc),
    outReplyLine: Color(0xff7eceff),
    inReplyName: Color(0xff79c4fc),
    outReplyName: Color(0xff9fd9ff),
    inForwardName: Color(0xff77bcfc),
    outForwardName: Color(0xffacddff),
    panelBg: Color(0xff1e1e1f),
    panelHint: Color(0x64ffffff),
    panelIcons: Color(0x64ffffff),
    panelSend: Color(0xff4ca9f4),
    wallpaper: [Color(0xff0f0f10), Color(0xff0f0f10), Color(0xff0f0f10), Color(0xff0f0f10)],
    serviceBg: Color(0x96373737),
    switchOn: Color(0xff459ce3),
    online: Color(0xff4bcb1c),
  );

  @override
  AyuColors copyWith() => this;

  @override
  AyuColors lerp(AyuColors? other, double t) => t < 0.5 ? this : (other ?? this);
}

extension AyuColorsX on BuildContext {
  AyuColors get ayu => Theme.of(this).extension<AyuColors>() ?? AyuColors.light;
}

ThemeData buildAyuTheme(Brightness b) {
  final c = b == Brightness.dark ? AyuColors.dark : AyuColors.light;
  final base = ThemeData(
    brightness: b,
    useMaterial3: false,
    fontFamily: 'Roboto',
    colorScheme: ColorScheme.fromSeed(seedColor: c.blueText, brightness: b).copyWith(
      primary: c.blueText,
      surface: c.windowBg,
    ),
    scaffoldBackgroundColor: c.windowBg,
    dividerColor: c.divider,
    extensions: [c],
  );
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: c.actionBar,
      foregroundColor: c.actionBarTitle,
      elevation: 1.5,
      titleTextStyle: TextStyle(fontFamily: 'Roboto', color: c.actionBarTitle, fontSize: 20, fontWeight: FontWeight.w600),
      iconTheme: IconThemeData(color: c.actionBarTitle),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.switchOn : null),
    ),
    textTheme: base.textTheme.apply(bodyColor: c.text, displayColor: c.text),
    listTileTheme: ListTileThemeData(textColor: c.text, iconColor: c.menuIcon),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.windowBg),
    popupMenuTheme: PopupMenuThemeData(color: c.windowBg),
    dialogTheme: DialogThemeData(backgroundColor: c.windowBg),
    textSelectionTheme: TextSelectionThemeData(cursorColor: c.blueText),
  );
}

/// Обои чата: четырёхточечный градиент Telegram, нарисованный радиальными пятнами.
class AyuWallpaper extends StatelessWidget {
  const AyuWallpaper({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _WallpaperPainter(context.ayu.wallpaper), child: child);
}

class _WallpaperPainter extends CustomPainter {
  _WallpaperPainter(this.colors);
  final List<Color> colors;

  // Позиции цветов как в GradientRenderer Telegram.
  static const _points = [Offset(0.80, 0.10), Offset(0.35, 0.25), Offset(0.20, 0.90), Offset(0.65, 0.75)];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = colors[0]);
    final r = size.longestSide * 0.75;
    for (var i = 0; i < 4; i++) {
      final center = Offset(_points[i].dx * size.width, _points[i].dy * size.height);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(colors: [colors[i], colors[i].withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: center, radius: r)),
      );
    }
  }

  @override
  bool shouldRepaint(_WallpaperPainter old) => old.colors != colors;
}
