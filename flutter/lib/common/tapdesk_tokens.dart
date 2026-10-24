import 'package:flutter/material.dart';

/// TapDesk 视觉 token（只放"皮"：颜色 / 圆角 / 间距 / 状态色）。
///
/// 目的：组件里不再散写十六进制与魔法数字，换肤或统一微调时改这里。
/// 与 RustDesk 的 MyTheme 分工：MyTheme 是上游主题（accent/border/画布色），
/// 这里只补充我们自己的品牌与中性色，避免动上游主题导致别的界面跑版。
class TapDeskTokens {
  TapDeskTokens._();

  // —— 品牌 ——
  static const Color accent = Color(0xFF0071FF);
  static const Color accentSoft = Color(0xFFE6F0FF);

  // —— 中性（浅色）——
  static const Color lineLight = Color(0xFFE8E8EC);
  static const Color lineSoftLight = Color(0xFFF0F0F3);
  static const Color ink = Color(0xFF1A1A1F);
  static const Color inkSecondary = Color(0xFF8A8A93);
  static const Color fieldLight = Color(0xFFF5F6F8);
  static const Color card = Color(0xFFFFFFFF);

  // —— 中性（深色）——
  static const Color lineDark = Color(0xFF2A2D36);
  static const Color lineSoftDark = Color(0xFF23252C);
  static const Color fieldDark = Color(0xFF1E2027);

  // —— 状态 ——
  static const Color online = Color(0xFF34C759);

  // —— 圆角 / 间距 / 图标 ——
  static const double radiusCard = 14;
  static const double radiusAvatar = 12;
  static const double radiusField = 18;
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double iconSm = 18;
  static const double iconMd = 22;
  static const double iconLg = 24;

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color line(BuildContext context) =>
      isDark(context) ? lineDark : lineLight;

  static Color lineSoft(BuildContext context) =>
      isDark(context) ? lineSoftDark : lineSoftLight;

  static Color field(BuildContext context) =>
      isDark(context) ? fieldDark : fieldLight;

  static Color secondaryText(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;
}
