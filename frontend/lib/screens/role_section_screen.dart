import 'package:flutter/material.dart';

import '../ui/ir_components.dart';
import '../ui/ir_page_body.dart';
import '../ui/ir_theme.dart';

class RoleSectionScreen extends StatelessWidget {
  const RoleSectionScreen({
    required this.title,
    required this.role,
    required this.items,
    super.key,
  });

  final String title;
  final String role;
  final List<SectionItem> items;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: irLightMode,
        builder: (context, isLight, _) => Theme(
          data: isLight ? irLightTheme() : irDarkTheme(),
          child: Scaffold(
            appBar: AppBar(title: Text(title)),
            body: IrEditorialBackdrop(
              child: IrPageBody(
                child: items.isEmpty && title != 'Configuración'
                    ? _empty(context)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
                        itemCount:
                            items.length + (title == 'Configuración' ? 2 : 1),
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return IrEntrance(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: IrPageIntro(
                                  title: title,
                                  description:
                                      'Todo lo que necesitas para gestionar tu experiencia como ${role == 'driver' ? 'conductor' : 'pasajero'}.',
                                ),
                              ),
                            );
                          }
                          if (title == 'Configuración' && index == 1) {
                            return IrEntrance(
                              delay: const Duration(milliseconds: 70),
                              child: IrPanel(
                                padding: EdgeInsets.zero,
                                child: SwitchListTile.adaptive(
                                  contentPadding:
                                      const EdgeInsets.fromLTRB(18, 8, 12, 8),
                                  secondary: Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: context.irColors.input,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(
                                      isLight
                                          ? Icons.light_mode
                                          : Icons.dark_mode_outlined,
                                      color: context.irColors.accent,
                                    ),
                                  ),
                                  title: const Text('Modo claro',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w800)),
                                  subtitle: const Text(
                                      'Usar superficies claras en la app'),
                                  value: isLight,
                                  activeThumbColor: IrPalette.accent,
                                  onChanged: (value) =>
                                      irLightMode.value = value,
                                ),
                              ),
                            );
                          }
                          final itemIndex =
                              title == 'Configuración' ? index - 2 : index - 1;
                          final item = items[itemIndex];
                          return IrEntrance(
                            delay:
                                Duration(milliseconds: 80 + (itemIndex * 45)),
                            child: IrInfoRow(
                              icon: item.icon,
                              title: item.title,
                              description: item.description,
                              trailing: item.action == null
                                  ? null
                                  : const Icon(Icons.arrow_forward, size: 20),
                              onTap: item.action == null
                                  ? null
                                  : () => item.action!(context),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
        ),
      );

  Widget _empty(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: IrEntrance(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: IrPanel(
                padding: const EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: context.irColors.input,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(Icons.route_outlined,
                        size: 30, color: context.irColors.accent),
                  ),
                  const SizedBox(height: 20),
                  Text('Aún no hay actividad',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: context.irColors.text,
                          fontSize: 24,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.7)),
                  const SizedBox(height: 10),
                  Text(
                    'Tus registros aparecerán aquí cuando estén disponibles.',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: context.irColors.muted, height: 1.45),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}

class SectionItem {
  const SectionItem({
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });

  final IconData icon;
  final String title;
  final String description;
  final void Function(BuildContext context)? action;
}
