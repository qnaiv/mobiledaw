import 'package:flutter/material.dart';

/// 画面案（キャンバス）と同じ配色
abstract final class DawColors {
  static const background = Color(0xFF111214);
  static const panel = Color(0xFF1B1D21);
  static const line = Color(0xFF2A2D33);
  static const text = Color(0xFFECEDEF);
  static const muted = Color(0xFF9AA0A8);
  static const accent = Color(0xFFC8F25A);
  static const lead = Color(0xFFE879C6);
  static const danger = Color(0xFFF2555A);
}

ThemeData buildDawTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: DawColors.background,
    colorScheme: base.colorScheme.copyWith(
      primary: DawColors.accent,
      onPrimary: DawColors.background,
      surface: DawColors.panel,
      onSurface: DawColors.text,
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 28,
      activeTrackColor: Color(0xFF2E3A1A),
      inactiveTrackColor: DawColors.panel,
      thumbColor: DawColors.accent,
      overlayShape: RoundSliderOverlayShape(overlayRadius: 0),
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 10),
      trackShape: RoundedRectSliderTrackShape(),
    ),
  );
}
