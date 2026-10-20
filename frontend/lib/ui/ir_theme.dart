import 'package:flutter/material.dart';
import 'ir_motion.dart';

final ValueNotifier<bool> irLightMode = ValueNotifier<bool>(false);

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

extension IrThemeColors on BuildContext {
  IrColors get irColors =>
      IrColors(Theme.of(this).brightness == Brightness.light);
}

class IrColors {
  const IrColors(this.light);
  final bool light;
  Color get surface => light ? const Color(0xFFF7F7F2) : IrPalette.surface;
  Color get raised => light ? Colors.white : IrPalette.raised;
  Color get input => light ? const Color(0xFFEBECE4) : IrPalette.input;
  Color get border => light ? const Color(0xFFD4D7CC) : IrPalette.border;
  Color get text => light ? IrPalette.ink : IrPalette.text;
  Color get muted => light ? const Color(0xFF565B53) : const Color(0xFFB7BABA);
  Color get accent => light ? const Color(0xFF596000) : IrPalette.accent;
}

ThemeData irDarkTheme() => _theme(Brightness.dark);
ThemeData irLightTheme() => _theme(Brightness.light);
ThemeData irCurrentTheme() =>
    irLightMode.value ? irLightTheme() : irDarkTheme();
ThemeData _theme(Brightness brightness) {
  final colors = IrColors(brightness == Brightness.light);
  final scheme = ColorScheme.fromSeed(
      seedColor: IrPalette.accent,
      brightness: brightness,
      primary: colors.accent,
      onPrimary: colors.light ? Colors.white : IrPalette.ink,
      surface: colors.surface,
      onSurface: colors.text,
      onSurfaceVariant: colors.muted,
      outline: colors.border,
      outlineVariant: colors.border,
      surfaceContainerLow: colors.raised,
      surfaceContainerHighest: colors.input);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(18));
  final actionStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(48, 52)),
      padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 22, vertical: 15)),
      shape: WidgetStatePropertyAll(shape),
      textStyle: const WidgetStatePropertyAll(TextStyle(
          fontFamily: 'Arial', fontSize: 16, fontWeight: FontWeight.w700)),
      animationDuration: IrMotion.feedback,
      foregroundBuilder: IrMotion.buttonFeedback,
      visualDensity: VisualDensity.standard);
  final primaryStyle = actionStyle.copyWith(
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.disabled)
              ? colors.input
              : IrPalette.accent),
      foregroundColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.disabled)
              ? colors.muted
              : IrPalette.ink));
  return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.surface,
      fontFamily: 'Arial',
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
          fontFamily: 'Arial',
          bodyColor: colors.text,
          displayColor: colors.text),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
          backgroundColor: colors.surface,
          foregroundColor: colors.text,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          toolbarHeight: 68,
          titleSpacing: 20,
          titleTextStyle: TextStyle(
              fontFamily: 'Arial',
              color: colors.text,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: -.35)),
      cardTheme: CardThemeData(
          color: colors.raised,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(color: colors.border))),
      inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: colors.raised,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 19),
          labelStyle: TextStyle(color: colors.muted),
          hintStyle: TextStyle(color: colors.muted),
          errorMaxLines: 3,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: colors.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: colors.accent, width: 2))),
      filledButtonTheme: FilledButtonThemeData(style: primaryStyle),
      elevatedButtonTheme: ElevatedButtonThemeData(style: primaryStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: actionStyle.copyWith(
              foregroundColor: WidgetStatePropertyAll(colors.text),
              side: WidgetStatePropertyAll(BorderSide(color: colors.muted)))),
      textButtonTheme: TextButtonThemeData(
          style: actionStyle.copyWith(
              foregroundColor: WidgetStatePropertyAll(colors.accent))),
      iconButtonTheme: IconButtonThemeData(
          style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
              foregroundBuilder: IrMotion.buttonFeedback)),
      dividerTheme: DividerThemeData(color: colors.border, space: 24),
      progressIndicatorTheme: ProgressIndicatorThemeData(
          color: colors.accent, linearTrackColor: colors.border),
      snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: colors.text,
          contentTextStyle: TextStyle(color: colors.surface),
          shape: shape),
      bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: colors.surface,
          surfaceTintColor: Colors.transparent,
          showDragHandle: true,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)))),
      drawerTheme:
          DrawerThemeData(backgroundColor: colors.surface, elevation: 0),
      navigationDrawerTheme: NavigationDrawerThemeData(
          backgroundColor: colors.surface,
          indicatorColor: IrPalette.accent,
          iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? IrPalette.ink
                  : colors.muted))),
      segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size(88, 52)),
              shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18))),
              side: WidgetStatePropertyAll(BorderSide(color: colors.border)),
              backgroundColor:
                  WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? IrPalette.accent : colors.raised),
              foregroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? IrPalette.ink : colors.text),
              textStyle: const WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w800, letterSpacing: -.15)))),
      chipTheme: ChipThemeData(backgroundColor: colors.input, selectedColor: IrPalette.accent, side: BorderSide(color: colors.border), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), labelStyle: TextStyle(color: colors.text, fontWeight: FontWeight.w700)),
      tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 350)),
      textSelectionTheme: TextSelectionThemeData(cursorColor: colors.accent, selectionColor: colors.accent.withValues(alpha: .25), selectionHandleColor: colors.accent));
}
