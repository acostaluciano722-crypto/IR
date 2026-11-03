import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/auth_gate.dart';
import 'services/app_auth.dart';
import 'ui/ir_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppAuth.initialize();
  runApp(const IrApp());
}

class IrApp extends StatelessWidget {
  const IrApp({super.key});
  static const lemonTonic = IrPalette.accent;
  static const ink = IrPalette.ink;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
      valueListenable: irLightMode,
      builder: (context, light, _) => MaterialApp(
          title: 'IR',
          locale: const Locale('es', 'CO'),
          supportedLocales: const [Locale('es', 'CO')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          debugShowCheckedModeBanner: false,
          theme: irLightTheme(),
          darkTheme: irDarkTheme(),
          themeMode: light ? ThemeMode.light : ThemeMode.dark,
          themeAnimationCurve: Curves.easeOutCubic,
          themeAnimationDuration: WidgetsBinding.instance.platformDispatcher
                  .accessibilityFeatures.disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 220),
          home: const AuthGate()));
}
