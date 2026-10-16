import 'package:flutter/material.dart';

/// ألوان محفظتي — أخضر-فيروزي مستوحى من اللوجو.
class AppColors {
  const AppColors._();

  static const primary = Color(0xFF1A6E5E);
  static const primaryDark = Color(0xFF16302B);
  static const primaryLight = Color(0xFF2E8B78);
  static const background = Color(0xFFF5F6F8);
  static const ink = Color(0xFF1B2B28);
  static const navIndicator = Color(0xFFD3EEE5);

  // ألوان بطاقات الأقسام (زي المرجع)
  static const walletsBlue = Color(0xFF1E5BB8);
  static const walletsBlueBg = Color(0xFFEAF1FB);
  static const pocketRed = Color(0xFFD9503F);
  static const pocketRedBg = Color(0xFFFCEDEA);
  static const debtsPurple = Color(0xFF6B4FC8);
  static const debtsPurpleBg = Color(0xFFF0EDFB);

  // ألوان أيقونات نوع العملية
  static const bankGreen = Color(0xFF1E8E6A);
  static const bankGreenBg = Color(0xFFDDF3EA);
  static const mobilePurple = Color(0xFF6B4FC8);
  static const mobilePurpleBg = Color(0xFFE9E4FA);
  static const servicesOrange = Color(0xFFE0562E);
  static const servicesOrangeBg = Color(0xFFFCE3DC);

  static const incoming = Color(0xFF1B8A5A);
  static const outgoing = Color(0xFFD64040);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.primary,
    secondary: AppColors.primaryLight,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 1.5,
      shadowColor: Colors.black26,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.navIndicator,
      indicatorShape: const StadiumBorder(),
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(color: selected ? AppColors.primary : Colors.grey.shade600);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? AppColors.primary : Colors.grey.shade600,
        );
      }),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
