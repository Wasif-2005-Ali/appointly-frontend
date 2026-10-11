import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color navy      = Color(0xFF0B2447);
  static const Color navy2     = Color(0xFF0F2D56);
  static const Color navy3     = Color(0xFF163560);
  static const Color alice     = Color(0xFFA8C8E8);
  static const Color aliceLight = Color(0xFFDAEEFF);
  static const Color aliceBg   = Color(0xFFF0F8FF);
  static const Color accent    = Color(0xFF4A90D9);
  static const Color green     = Color(0xFF2ECC96);
  static const Color warning   = Color(0xFFF4A24A);
  static const Color danger    = Color(0xFFE05C5C);
  static const Color purple    = Color(0xFF7C3AED);
  static const Color white     = Colors.white;
}

class AppTheme {
  static ThemeData theme() {
    return ThemeData(
      scaffoldBackgroundColor: AppColors.aliceBg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.navy,
        primary: AppColors.navy,
      ),
      textTheme: GoogleFonts.dmSansTextTheme(),
      useMaterial3: true,
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.navy,
      ),
    );
  }
}
