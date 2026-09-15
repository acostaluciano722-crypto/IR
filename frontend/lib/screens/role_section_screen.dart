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
    return Theme(
      data: irDarkTheme(),
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, index) {
          final item = items[index];
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
