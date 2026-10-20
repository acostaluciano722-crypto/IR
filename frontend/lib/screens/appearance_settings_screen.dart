import 'package:flutter/material.dart';

import '../ui/ir_theme.dart';
import '../ui/ir_page_body.dart';
import '../ui/ir_components.dart';

class AppearanceSettingsScreen extends StatelessWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: irLightMode,
      builder: (context, isLight, _) => Theme(
        data: isLight ? irLightTheme() : irDarkTheme(),
        child: Scaffold(
          appBar: AppBar(title: const Text('Configuración')),
          body: IrEditorialBackdrop(
              child: IrPageBody(
                  child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
            children: [
              const IrPageIntro(
                  title: 'Tu apariencia',
                  description:
                      'Elige el contraste que mejor se adapte a tu recorrido.'),
              const SizedBox(height: 28),
              IrPanel(
                padding: EdgeInsets.zero,
                child: SwitchListTile.adaptive(
                  contentPadding: const EdgeInsets.fromLTRB(18, 8, 12, 8),
                  secondary: Icon(
                      isLight ? Icons.light_mode : Icons.dark_mode_outlined,
                      color: isLight ? IrPalette.ink : IrPalette.accent),
                  title: const Text('Modo claro',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: const Text('Usar superficies claras en la app'),
                  value: isLight,
                  activeThumbColor: IrPalette.accent,
                  onChanged: (value) => irLightMode.value = value,
                ),
              ),
            ],
          ))),
        ),
      ),
    );
  }
}
