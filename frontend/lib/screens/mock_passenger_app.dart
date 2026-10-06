import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/passenger_app_state.dart';
import '../ui/ir_theme.dart';
import 'role_section_screen.dart';

class MockPassengerApp extends StatefulWidget {
  const MockPassengerApp({super.key});
  @override
  State<MockPassengerApp> createState() => _MockPassengerAppState();
}

class _MockPassengerAppState extends State<MockPassengerApp> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    const placeholders = [
      _MockSection(
          icon: Icons.history,
          title: 'Viajes',
          detail: 'Aquí aparecerá tu historial de viajes.'),
      _MockSection(
          icon: Icons.account_tree_outlined,
          title: 'ProMaster',
          detail: 'Progreso, red, ciclos y referidos.'),
      _MockSection(
          icon: Icons.support_agent_outlined,
          title: 'Soporte',
          detail: 'Ayuda y seguridad IR.'),
      _MockSection(
          icon: Icons.person_outline,
          title: 'Perfil',
          detail: 'Tus datos y preferencias.'),
    ];
    return ValueListenableBuilder<bool>(
      valueListenable: irLightMode,
      builder: (context, isLight, _) => Theme(
        data: isLight ? irLightTheme() : irDarkTheme(),
        child: ChangeNotifierProvider(
          create: (_) => PassengerAppState(),
          child: Scaffold(
            drawer: Drawer(
              child: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 20),
                  children: [
                    const Text('IR',
                        style: TextStyle(
                            color: IrPalette.accent,
                            fontSize: 30,
                            fontWeight: FontWeight.w900)),
                    const SizedBox(height: 24),
                    _drawerItem(Icons.home_outlined, 'Inicio', () {
                      Navigator.pop(context);
                      setState(() => index = 0);
                    }),
                    _drawerItem(Icons.history_outlined, 'Historial', () {
                      Navigator.pop(context);
                      setState(() => index = 1);
                    }),
                    _drawerItem(Icons.account_tree_outlined, 'ProMaster', () {
                      Navigator.pop(context);
                      setState(() => index = 2);
                    }),
                    _drawerItem(Icons.support_agent_outlined, 'Soporte', () {
                      Navigator.pop(context);
                      setState(() => index = 3);
                    }),
                    _drawerItem(Icons.person_outline, 'Perfil', () {
                      Navigator.pop(context);
                      setState(() => index = 4);
                    }),
                    _drawerItem(Icons.settings_outlined, 'Configuración', () {
                      Navigator.pop(context);
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => RoleSectionScreen(
                              title: 'Configuración',
                              role: 'passenger',
                              items: const [
                                SectionItem(
                                    icon: Icons.settings_outlined,
                                    title: 'Preferencias de la cuenta',
                                    description:
                                        'Administra tus preferencias como pasajero.'),
                                SectionItem(
                                    icon: Icons.notifications_none_outlined,
                                    title: 'Notificaciones',
                                    description:
                                        'Configura los avisos de tus viajes.'),
                              ])));
                    }),
                  ],
                ),
              ),
            ),
            body: index == 0
                ? const _DemoPassengerHome()
                : Scaffold(
                    appBar: AppBar(title: Text(_titles[index])),
                    body: placeholders[index - 1]),
          ),
        ),
      ),
    );
  }

  static const _titles = ['Inicio', 'Viajes', 'ProMaster', 'Soporte', 'Perfil'];

  Widget _drawerItem(IconData icon, String title, VoidCallback onTap) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );
}

class _DemoPassengerHome extends StatelessWidget {
  const _DemoPassengerHome();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PassengerAppState>();
    final isLight = irLightMode.value;
    final sheet = isLight ? const Color(0xFFFFFFFF) : IrPalette.surface;
    final muted = isLight ? const Color(0xFF5F6368) : IrPalette.muted;
    return Stack(
      children: [
        Positioned.fill(
            child: _DemoMap(isLight: isLight)),
        Positioned(
          top: 18,
          right: 18,
          child: Builder(
              builder: (context) => Material(
                    color: IrPalette.surface,
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Abrir menú',
                      icon: const Icon(Icons.menu, color: Colors.white, size: 32),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  )),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            decoration: BoxDecoration(
                color: sheet,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(30))),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
            child: SingleChildScrollView(
              child: Column(children: [
                Container(
                    width: 66,
                    height: 6,
                    decoration: BoxDecoration(
                        color: muted,
                        borderRadius: BorderRadius.circular(20))),
                const SizedBox(height: 16),
                Row(children: const [
                  _VehicleOption(icon: Icons.directions_car, label: 'Viaje', selected: true),
                  SizedBox(width: 10),
                  _VehicleOption(icon: Icons.two_wheeler, label: 'Moto'),
                  SizedBox(width: 10),
                  _VehicleOption(icon: Icons.directions_car, label: 'Viaje+'),
                  SizedBox(width: 10),
                  _VehicleOption(icon: Icons.ac_unit, label: 'Comfort'),
                ]),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: isLight ? const Color(0xFFF0F0E8) : IrPalette.raised,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: isLight ? const Color(0xFFD9D9D0) : IrPalette.border)),
                  child: Row(children: [
                    const Icon(Icons.stars, color: IrPalette.accent, size: 34),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('ProMaster pasajero', style: TextStyle(color: muted)),
                          Text('1836 PI · Nivel Plata',
                              style: TextStyle(
                                  color: isLight ? IrPalette.ink : Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800)),
                        ])),
                    Text('COP 20 = 1 PI', style: TextStyle(color: muted, fontSize: 12)),
                  ]),
                ),
                const SizedBox(height: 14),
                TextField(
                    onChanged: state.setDestination,
                    decoration: const InputDecoration(
                        hintText: '¿A dónde vas?', prefixIcon: Icon(Icons.search))),
                const SizedBox(height: 12),
                FilledButton.icon(
                    onPressed: () => state.prepareTrip(),
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Elegir destino')),
              ]),
            ),
          ),
        ),
      ],
    );
  }
}

class _VehicleOption extends StatelessWidget {
  const _VehicleOption({required this.icon, required this.label, this.selected = false});
  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          height: 96,
          decoration: BoxDecoration(
              color: selected ? IrPalette.accent : const Color(0xFF191A1B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: selected ? IrPalette.accent : const Color(0xFF3A3B3C))),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon,
                color: selected ? IrPalette.ink : Colors.white70, size: 34),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    color: selected ? IrPalette.ink : Colors.white70,
                    fontWeight: FontWeight.w800)),
          ]),
        ),
      );
}

class _DemoMap extends StatelessWidget {
  const _DemoMap({required this.isLight});
  final bool isLight;

  @override
  Widget build(BuildContext context) => CustomPaint(
      foregroundPainter: _DemoMapPainter(isLight: isLight),
        child: Container(
            color: isLight ? const Color(0xFFE6E5E1) : const Color(0xFF182027)),
      );
  }

class _DemoMapPainter extends CustomPainter {
  const _DemoMapPainter({required this.isLight});
  final bool isLight;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isLight ? const Color(0xFFD2D0CA) : const Color(0xFF28333E)
      ..strokeWidth = 2;
    for (var x = -size.height; x < size.width; x += 90) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), paint);
    }
    for (var y = 80.0; y < size.height; y += 100) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 30), paint);
    }
    final marker = Paint()..color = IrPalette.accent;
    canvas.drawCircle(Offset(size.width * .32, size.height * .52), 14, marker);
    canvas.drawCircle(Offset(size.width * .32, size.height * .52), 5,
        Paint()..color = IrPalette.ink);
  }

  @override
  bool shouldRepaint(covariant _DemoMapPainter oldDelegate) =>
      oldDelegate.isLight != isLight;
}

class _MockSection extends StatelessWidget {
  const _MockSection(
      {required this.icon, required this.title, required this.detail});
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: const Color(0xFFC9A227), size: 56),
        const SizedBox(height: 14),
        Text(title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(detail, style: const TextStyle(color: Colors.black54))
      ]));
}
