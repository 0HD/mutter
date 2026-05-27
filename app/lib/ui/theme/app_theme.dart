import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Discord-ish dark palette: deep neutral bluish-black, restrained accent.
class AppColors {
  static const Color bg0 = Color(0xFF14161B); // window background
  static const Color bg1 = Color(0xFF1A1D24); // sidebar
  static const Color bg2 = Color(0xFF21252E); // surfaces, cards
  static const Color bg3 = Color(0xFF2B313C); // elevated, hover

  static const Color border = Color(0xFF2A2F3A);

  static const Color text = Color(0xFFE6E8EE);
  static const Color textDim = Color(0xFF9AA0AC);
  static const Color textMuted = Color(0xFF6B7180);

  static const Color accent = Color(0xFF5B8DEF); // calm blue
  static const Color accentSoft = Color(0xFF334566);

  static const Color speaking = Color(0xFF4ADE80); // bright green
  static const Color whispering = Color(0xFFB07CFF);
  static const Color muted = Color(0xFFEF6464);
  static const Color warning = Color(0xFFE0B95B);
}

ThemeData buildTheme() {
  const fontFamily = 'Segoe UI Variable';
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg0,
    fontFamily: fontFamily,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      secondary: AppColors.accent,
      surface: AppColors.bg2,
      onPrimary: Colors.white,
      onSurface: AppColors.text,
      outline: AppColors.border,
    ),
  );

  return base.copyWith(
    textTheme: base.textTheme
        .apply(bodyColor: AppColors.text, displayColor: AppColors.text)
        .copyWith(
          bodyMedium: const TextStyle(
              fontSize: 14, height: 1.35, letterSpacing: 0.1),
          titleMedium: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1),
          labelMedium: const TextStyle(
              fontSize: 12, color: AppColors.textDim, letterSpacing: 0.3),
        ),
    iconTheme: const IconThemeData(color: AppColors.textDim, size: 18),
    dividerTheme: const DividerThemeData(
        color: AppColors.border, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.bg2,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: const TextStyle(color: AppColors.textMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle:
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.accent,
      inactiveTrackColor: AppColors.bg3,
      thumbColor: AppColors.accent,
      overlayColor: Color(0x335B8DEF),
      trackHeight: 3,
      // Fixed-size thumb and a tight overlay; the default Material 3 slider
      // grows the thumb dramatically on press, which reads as buggy.
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
      trackShape: RoundedRectSliderTrackShape(),
    ),
    splashFactory: NoSplash.splashFactory,
    visualDensity: VisualDensity.compact,
    hoverColor: AppColors.bg3.withValues(alpha: 0.4),
  );
}

class WindowChromeStyle {
  // Slim system chrome. Apply once at startup if we want to draw our own
  // title bar in the future via the window_manager package.
  static SystemUiOverlayStyle dark() => SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: AppColors.bg0,
        systemNavigationBarColor: AppColors.bg0,
      );
}
