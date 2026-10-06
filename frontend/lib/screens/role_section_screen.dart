import 'package:flutter/material.dart';

import '../ui/ir_theme.dart';

class RoleSectionScreen extends StatelessWidget {
  const RoleSectionScreen(
      {required this.title,
      required this.role,
      required this.items,
      super.key});

  final String title;
  final String role;
  final List<SectionItem> items;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: irLightMode,
      builder: (context, isLight, _) => Theme(
      data: isLight ? irLightTheme() : irDarkTheme(),
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: items.length + (title == 'Configuración' ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, index) {
          if (title == 'Configuración' && index == 0) {
            return Card(
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
            );
          }
          final itemIndex = title == 'Configuración' ? index - 1 : index;
          final item = items[itemIndex];
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading:
                  Icon(item.icon, color: IrPalette.accent),
              title: Text(item.title,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(item.description)),
              trailing:
                  item.action == null ? null : const Icon(Icons.chevron_right),
              onTap: item.action == null ? null : () => item.action!(context),
            ),
          );
        },
        ),
      ),
      ),
    );
  }
}

class SectionItem {
  const SectionItem(
      {required this.icon,
      required this.title,
      required this.description,
      this.action});

  final IconData icon;
  final String title;
  final String description;
  final void Function(BuildContext context)? action;
}
