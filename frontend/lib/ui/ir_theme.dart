import 'package:flutter/material.dart';

abstract final class IrPalette {
  static const ink = Color(0xFF171B1D);
  static const surface = Color(0xFF111213);
  static const raised = Color(0xFF202122);
  static const input = Color(0xFF303031);
  static const border = Color(0xFF2D2E2F);
  static const accent = Color(0xFFE8F044);
  static const text = Colors.white;
  static const muted = Color(0xB3FFFFFF);
}

ThemeData irDarkTheme() => ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: IrPalette.surface,
      colorScheme: const ColorScheme.dark(
        primary: IrPalette.accent,
        onPrimary: IrPalette.ink,
        secondary: IrPalette.accent,
        onSecondary: IrPalette.ink,
        surface: IrPalette.surface,
        onSurface: IrPalette.text,
        outline: IrPalette.border,
      ),
      fontFamily: 'Arial',
      appBarTheme: const AppBarTheme(
        backgroundColor: IrPalette.surface,
        foregroundColor: IrPalette.text,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: IrPalette.raised,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          side: BorderSide(color: IrPalette.border),
        ),
      ),
      dividerTheme: const DividerThemeData(color: IrPalette.border),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: IrPalette.accent,
        linearTrackColor: IrPalette.border,
      ),
    );
