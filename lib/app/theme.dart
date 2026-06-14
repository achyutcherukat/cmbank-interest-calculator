import 'package:flutter/material.dart';

class CMBColors {
  const CMBColors._();

  static const navy = Color(0xFF0D1B3E);
  static const goldRich = Color(0xFFD4A843);
  static const goldLight = Color(0xFFE8C96A);
  static const goldDark = Color(0xFFB8960C);
  static const warmWhite = Color(0xFFF2EFE8);
  static const textOnNavyLarge = Color(0xFFD4A843);
  static const textOnNavySmall = Color(0xFFE8C96A);
  static const textOnNavyMuted = Color(0xFFB8960C);
  static const textOnLight = Color(0xFF0D1B3E);
  static const textOnLightMuted = Color(0xFF555555);
  static const cardBackground = Color(0xFFFFFFFF);
  static const borderOnLight = Color(0x660D1B3E);
  static const borderOnNavy = Color(0x66D4A843);
  static const borderInputUnfocused = Color(0x330D1B3E);
  static const borderInputFocused = Color(0xFFD4A843);
  static const borderInputError = Color(0xFFC62828);
  static const dividerOnCard = Color(0x33D4A843);
  static const pageBackground = Color(0xFFF2EFE8);

  // Semantic (do not change)
  static const moneyIn = Color(0xFF2E7D32);
  static const moneyOut = Color(0xFFC62828);
  static const statusOpen = Color(0xFF2E7D32);
  static const statusClosed = Color(0xFF555555);
  static const statusRenewed = Color(0xFF1565C0);
  static const warningRed = Color(0xFFC62828);
  static const warningOrange = Color(0xFFE65100);
  static const ageingGreen = Color(0xFF2E7D32);
  static const ageingYellow = Color(0xFFF9A825);
  static const ageingOrange = Color(0xFFE65100);
  static const ageingRed = Color(0xFFC62828);
}

class CMBankTheme {
  const CMBankTheme._();

  static ThemeData get light {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: CMBColors.navy,
        primary: CMBColors.navy,
      ),
      scaffoldBackgroundColor: CMBColors.warmWhite,
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: CMBColors.navy,
        foregroundColor: CMBColors.goldRich,
        titleTextStyle: TextStyle(
          color: CMBColors.textOnNavyLarge,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
        iconTheme: IconThemeData(color: CMBColors.goldRich),
        actionsIconTheme: IconThemeData(color: CMBColors.goldRich),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
              color: CMBColors.borderInputUnfocused, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
              color: CMBColors.borderInputUnfocused, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
              color: CMBColors.borderInputFocused, width: 2.5),
        ),
        labelStyle: const TextStyle(fontSize: 18, color: CMBColors.navy),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: CMBColors.navy,
          foregroundColor: CMBColors.textOnNavyLarge,
          minimumSize: const Size(double.infinity, 60),
          side: const BorderSide(color: CMBColors.borderOnNavy, width: 0.8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }
}
