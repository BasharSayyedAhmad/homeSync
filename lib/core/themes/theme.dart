// lib/core/theme/theme.dart
import 'package:flutter/material.dart';

ThemeData lightMode = ThemeData(
  brightness: Brightness.light,
  colorScheme: ColorScheme.light(
    primary: Color(0xFF5E35B1), // بنفسجي ناعم
    secondary: Color(0xFF00BFA5), // توركوازي
    surface: Colors.white,
    background: Color(0xFFF5F5F5), // رمادي فاتح جداً
    error: Color(0xFFE53935),
    onPrimary: Colors.white,
    onSecondary: Colors.white,
    onSurface: Color(0xFF1A1A1A), // أسود مائل للرمادي
    onBackground: Color(0xFF1A1A1A),
    onError: Colors.white,
  ),

  // عناصر إضافية
  cardColor: Colors.white,
  scaffoldBackgroundColor: Color(0xFFF5F5F5),
  appBarTheme: AppBarTheme(
    backgroundColor: Color(0xFF5E35B1),
    foregroundColor: Colors.white,
    elevation: 0,
    centerTitle: true,
  ),
  iconTheme: IconThemeData(color: Color(0xFF5E35B1)),
  textTheme: TextTheme(
    bodyLarge: TextStyle(color: Color(0xFF1A1A1A)),
    bodyMedium: TextStyle(color: Color(0xFF4A4A4A)),
    titleLarge: TextStyle(
      color: Color(0xFF1A1A1A),
      fontWeight: FontWeight.bold,
    ),
  ),
);

ThemeData darkMode = ThemeData(
  brightness: Brightness.dark,
  colorScheme: ColorScheme.dark(
    primary: Color(0xFF7E57C2), // بنفسجي فاتح (مريح للعين)
    secondary: Color(0xFF00BFA5), // توركوازي
    surface: Color(0xFF1E1E1E), // رمادي غامق
    background: Color(0xFF121212), // أسود مائل للرمادي
    error: Color(0xFFCF6679),
    onPrimary: Colors.white,
    onSecondary: Colors.white,
    onSurface: Color(0xFFE0E0E0),
    onBackground: Color(0xFFE0E0E0),
    onError: Colors.black,
  ),

  // عناصر إضافية
  cardColor: Color(0xFF2C2C2C),
  scaffoldBackgroundColor: Color(0xFF121212),
  appBarTheme: AppBarTheme(
    backgroundColor: Color(0xFF1E1E1E),
    foregroundColor: Colors.white,
    elevation: 0,
    centerTitle: true,
  ),
  iconTheme: IconThemeData(color: Color(0xFF7E57C2)),
  textTheme: TextTheme(
    bodyLarge: TextStyle(color: Color(0xFFE0E0E0)),
    bodyMedium: TextStyle(color: Color(0xFFB0B0B0)),
    titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
  ),
);
