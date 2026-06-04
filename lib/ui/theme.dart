import 'package:flutter/material.dart';

/// Clash Verge 风格的配色与卡片样式集中在这里，方便全局统一。
class AppColors {
  static const bg = Color(0xFFF4F5F7);
  static const sidebar = Color(0xFFFFFFFF);
  static const card = Color(0xFFFFFFFF);
  static const primary = Color(0xFF2563EB);
  static const primaryDeep = Color(0xFF1D4ED8);
  static const primarySoft = Color(0xFFEAF1FF);
  static const textPrimary = Color(0xFF1F2933);
  static const textSecondary = Color(0xFF8A94A6);
  static const border = Color(0xFFE9EBF0);
  static const success = Color(0xFF22C55E);
  static const danger = Color(0xFFEF4444);
  static const warning = Color(0xFFF59E0B);

  // 半透明白（叠在蓝色卡片上时使用，避免 withOpacity 的 lint 警告）
  static const white18 = Color(0x2EFFFFFF);
  static const white24 = Color(0x3DFFFFFF);
  static const white70 = Color(0xB3FFFFFF);
}

const double kRadius = 16;

const List<BoxShadow> kCardShadow = [
  BoxShadow(color: Color(0x0D101828), blurRadius: 14, offset: Offset(0, 3)),
];

const LinearGradient kPrimaryGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF3B82F6), AppColors.primaryDeep],
);

BoxDecoration panelDecoration({Color? color, Color? borderColor}) {
  return BoxDecoration(
    color: color ?? AppColors.card,
    borderRadius: BorderRadius.circular(kRadius),
    border: Border.all(color: borderColor ?? AppColors.border),
    boxShadow: kCardShadow,
  );
}
