import 'package:flutter/material.dart';

// Same colours as the web (dashboard/layout/layout.css for the app, styles/tokens.css for the public pages).
@immutable
class C extends ThemeExtension<C> {
  // after login (dashboard)
  final Color appBg, card, bg2, chip, line, lineStrong, ink, muted;
  final Color brand, brand2, brandInk, active, solid, onSolid;
  final List<Color> grad;
  final List<BoxShadow> cardShadow, popShadow, orangeShadow;
  // public pages (get started, log in, sign up)
  final Color pubBg, pubBg2, pubInk, pubMuted, pubLine, pubLineStrong, pubBrand, pubOnBrand, pubChip, limeBg, limeInk;
  // status
  final Color good, goodBg, warn, warnBg, danger, dangerBg;
  final bool dark;

  const C({
    required this.appBg,
    required this.card,
    required this.bg2,
    required this.chip,
    required this.line,
    required this.lineStrong,
    required this.ink,
    required this.muted,
    required this.brand,
    required this.brand2,
    required this.brandInk,
    required this.active,
    required this.solid,
    required this.onSolid,
    required this.grad,
    required this.cardShadow,
    required this.popShadow,
    required this.orangeShadow,
    required this.pubBg,
    required this.pubBg2,
    required this.pubInk,
    required this.pubMuted,
    required this.pubLine,
    required this.pubLineStrong,
    required this.pubBrand,
    required this.pubOnBrand,
    required this.pubChip,
    required this.limeBg,
    required this.limeInk,
    required this.good,
    required this.goodBg,
    required this.warn,
    required this.warnBg,
    required this.danger,
    required this.dangerBg,
    required this.dark,
  });

  static const light = C(
    appBg: Color(0xFFECEEF2),
    card: Color(0xFFFFFFFF),
    bg2: Color(0xFFF4F5F8),
    chip: Color(0xFFF1F2F6),
    line: Color(0xFFE6E8EE),
    lineStrong: Color(0xFFD7DAE3),
    ink: Color(0xFF16171B),
    muted: Color(0xFF6A6E7A),
    brand: Color(0xFFE0581A),
    brand2: Color(0xFFE08A1A),
    brandInk: Color(0xFFC2470F),
    active: Color(0x1AE0581A),
    solid: Color(0xFF16171B),
    onSolid: Color(0xFFFFFFFF),
    grad: [Color(0xFFE0581A), Color(0xFFE8701A), Color(0xFFE08A1A)],
    cardShadow: [BoxShadow(color: Color(0x0A16171B), blurRadius: 2, offset: Offset(0, 1)), BoxShadow(color: Color(0x0F16171B), blurRadius: 30, offset: Offset(0, 10))],
    popShadow: [BoxShadow(color: Color(0x2916171B), blurRadius: 50, offset: Offset(0, 20))],
    orangeShadow: [BoxShadow(color: Color(0x52E0581A), blurRadius: 24, offset: Offset(0, 10))],
    pubBg: Color(0xFFFFFFFF),
    pubBg2: Color(0xFFF7F5F1),
    pubInk: Color(0xFF1A1714),
    pubMuted: Color(0xFF5A534C),
    pubLine: Color(0xFFECE7E0),
    pubLineStrong: Color(0xFFDDD7CE),
    pubBrand: Color(0xFFB9420C),
    pubOnBrand: Color(0xFFFFFFFF),
    pubChip: Color(0xFFF3F0EB),
    limeBg: Color(0xFFEEF3CF),
    limeInk: Color(0xFF525C0E),
    good: Color(0xFF2F6B2F),
    goodBg: Color(0xFFE3F1DF),
    warn: Color(0xFF8A4B0E),
    warnBg: Color(0xFFFCE9D6),
    danger: Color(0xFFB42318),
    dangerBg: Color(0xFFFDECEA),
    dark: false,
  );

  static const darkTheme = C(
    appBg: Color(0xFF0D0E11),
    card: Color(0xFF17181D),
    bg2: Color(0xFF1F2027),
    chip: Color(0xFF23242C),
    line: Color(0xFF2A2C35),
    lineStrong: Color(0xFF363945),
    ink: Color(0xFFF2F3F6),
    muted: Color(0xFFA3A7B3),
    brand: Color(0xFFEE6A2A),
    brand2: Color(0xFFF08F2C),
    brandInk: Color(0xFFF58A52),
    active: Color(0x29EE6A2A),
    solid: Color(0xFFF2F3F6),
    onSolid: Color(0xFF16171B),
    grad: [Color(0xFFE0581A), Color(0xFFEC7322), Color(0xFFF0902C)],
    cardShadow: [BoxShadow(color: Color(0x4D000000), blurRadius: 2, offset: Offset(0, 1)), BoxShadow(color: Color(0x59000000), blurRadius: 30, offset: Offset(0, 10))],
    popShadow: [BoxShadow(color: Color(0x8C000000), blurRadius: 50, offset: Offset(0, 20))],
    orangeShadow: [BoxShadow(color: Color(0x40EE6A2A), blurRadius: 24, offset: Offset(0, 10))],
    pubBg: Color(0xFF0E0C0A),
    pubBg2: Color(0xFF15120F),
    pubInk: Color(0xFFF5F0E9),
    pubMuted: Color(0xFFB5ACA2),
    pubLine: Color(0xFF2C2722),
    pubLineStrong: Color(0xFF3A342D),
    pubBrand: Color(0xFFEE6A2A),
    pubOnBrand: Color(0xFF1A0D05),
    pubChip: Color(0xFF221E1A),
    limeBg: Color(0x29B4C21C),
    limeInk: Color(0xFFD4E05A),
    good: Color(0xFF8FD18A),
    goodBg: Color(0x298FD18A),
    warn: Color(0xFFF4B26B),
    warnBg: Color(0x29F4B26B),
    danger: Color(0xFFFF8A7A),
    dangerBg: Color(0x29FF8A7A),
    dark: true,
  );

  LinearGradient get gradient => LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: grad);

  @override
  C copyWith() => this;
  @override
  C lerp(ThemeExtension<C>? other, double t) => (other is C && t > .5) ? other : this;
}

extension CtxColors on BuildContext {
  C get c => Theme.of(this).extension<C>()!;
}

// the homepage colours (roast brown stage, lime) used on "Get started"
class Brand {
  static const orange = Color(0xFFE0581A);
  static const roast = Color(0xFF1C120B);
  static const roast2 = Color(0xFF2A1A0F);
  static const cream = Color(0xFFFFF7EF);
  static const lime = Color(0xFFB4C21C);
  // per service, same gradients as the homepage icons
  static const typeGrad = <String, List<Color>>{
    'namecard': [Color(0xFF1F1B16), Color(0xFFB9420C)],
    'restaurant': [Color(0xFFC2410C), Color(0xFFF08A1E)],
    'mart': [Color(0xFFD2600F), Color(0xFFC9A21A)],
    'guest_house': [Color(0xFF8E9A12), Color(0xFFC2B21A)],
    'attendance': [Color(0xFFB9420C), Color(0xFF8E9A12)],
    'website': [Color(0xFF7C3AED), Color(0xFFE0581A)],
    'menu_qr': [Color(0xFF059669), Color(0xFF84CC16)],
    'flipbook': [Color(0xFF4F46E5), Color(0xFF0EA5E9)],
    'qr_gen': [Color(0xFF0369A1), Color(0xFF22D3EE)],
    'debt_book': [Color(0xFFBE123C), Color(0xFFF97316)],
    'stamp_card': [Color(0xFF92400E), Color(0xFFF59E0B)],
    'event': [Color(0xFF9D174D), Color(0xFFF0662B)],
  };
}

ThemeData buildTheme({required bool dark, required bool khmer}) {
  final c = dark ? C.darkTheme : C.light;
  // Khmer needs taller lines (web: headings 1.45, text 1.75)
  final hHead = khmer ? 1.45 : 1.15;
  final hBody = khmer ? 1.7 : 1.5;
  final base = ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    fontFamily: 'PlusJakartaSans',
    fontFamilyFallback: const ['KantumruyPro'],
    scaffoldBackgroundColor: c.appBg,
    colorScheme: ColorScheme.fromSeed(seedColor: c.brand, brightness: dark ? Brightness.dark : Brightness.light, primary: c.brand, surface: c.card),
    extensions: [c],
    splashFactory: InkSparkle.splashFactory,
  );
  TextStyle s(double size, FontWeight w, double h, [Color? col]) => TextStyle(fontSize: size, fontWeight: w, height: h, color: col ?? c.ink, letterSpacing: size >= 22 && !khmer ? -0.4 : 0);
  return base.copyWith(
    textTheme: TextTheme(
      displaySmall: s(34, FontWeight.w800, hHead),
      headlineMedium: s(28, FontWeight.w800, hHead),
      headlineSmall: s(22, FontWeight.w800, hHead),
      titleLarge: s(18, FontWeight.w700, hHead),
      titleMedium: s(16, FontWeight.w700, hHead),
      titleSmall: s(14, FontWeight.w700, hHead),
      bodyLarge: s(16, FontWeight.w400, hBody),
      bodyMedium: s(14.5, FontWeight.w400, hBody),
      bodySmall: s(13, FontWeight.w500, hBody, c.muted),
      labelLarge: s(15, FontWeight.w700, 1.2),
      labelMedium: s(13, FontWeight.w600, 1.2),
      labelSmall: s(11.5, FontWeight.w600, 1.2, c.muted),
    ).apply(fontFamily: 'PlusJakartaSans', fontFamilyFallback: const ['KantumruyPro']),
    dividerColor: c.line,
    textSelectionTheme: TextSelectionThemeData(cursorColor: c.brand, selectionColor: c.brand.withValues(alpha: .25), selectionHandleColor: c.brand),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.brand),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.solid,
      contentTextStyle: TextStyle(color: c.onSolid, fontWeight: FontWeight.w600, fontFamily: 'PlusJakartaSans', fontFamilyFallback: const ['KantumruyPro']),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.card, showDragHandle: true, dragHandleColor: c.lineStrong, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28)))),
    dialogTheme: DialogThemeData(backgroundColor: c.card, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
  );
}
