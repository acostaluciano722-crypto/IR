import 'package:flutter/material.dart';

import '../ui/ir_theme.dart';

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
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: SwitchListTile.adaptive(
                  contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
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
          ),
        ),
      ),
    );
  }
}