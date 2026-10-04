import 'package:flutter/material.dart';

// Todos los colores extraídos del logo Captain Pingui.
class AppColors {
  // Fondos
  static const bg = Color(0xFFF5F5F7); // gris claro tipo Apple
  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF0D0D0F); // negro del cuerpo del pingüino

  // Acentos — extraídos del logo
  static const blue = Color(0xFF2563EB); // azul de la cinta del sombrero
  static const blue2 = Color(0xFF1D4ED8);
  static const blueLt = Color(0xFFEFF6FF);
  static const green = Color(0xFF16A34A); // verde del trébol
  static const green2 = Color(0xFF15803D);
  static const greenLt = Color(0xFFF0FDF4);
  static const greenOk = Color(0xFF34C759); // verde sistema (OK, batería)

  // Estados
  static const red = Color(0xFFFF3B30);
  static const amber = Color(0xFFFF9500);

  // Grises
  static const gray = Color(0xFFF5F5F7);
  static const gray2 = Color(0xFFE5E5EA);
  static const gray3 = Color(0xFF8E8E93);

  // Texto
  static const text = Color(0xFF1C1C1E);
  static const text2 = Color(0xFF3A3A3C);
  static const text3 = Color(0xFF8E8E93);
}

class AppTheme {
  static ThemeData get theme => ThemeData(
    scaffoldBackgroundColor: AppColors.bg,
    fontFamily: 'SF Pro Display', // cae a la fuente del sistema si no está
    colorScheme: const ColorScheme.light(
      primary: AppColors.blue,
      secondary: AppColors.green,
      surface: AppColors.white,
    ),
    // Quita el efecto de splash azul en Android al tocar
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
  );
}
