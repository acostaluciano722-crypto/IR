import 'package:flutter/material.dart';

import 'ir_brand.dart';
import 'ir_theme.dart';

abstract final class IrMobilityLayout {
  static const railWidth = 88.0;
  static const panelWidth = 400.0;
  static const appBarHeight = 64.0;
  static const navigationHeight = 76.0;

  static bool expanded(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 1000;

  static bool keyboardOpen(BuildContext context) =>
      MediaQuery.viewInsetsOf(context).bottom > 0;

  static Size mapViewport(BuildContext context) {
    final media = MediaQuery.of(context);
    final desktop = expanded(context);
    final width = media.size.width - (desktop ? railWidth + panelWidth : 0);
    final bottom = desktop || keyboardOpen(context)
        ? 0.0
        : navigationHeight + media.padding.bottom;
    final height = media.size.height -
        media.padding.top -
        media.viewInsets.bottom -
        appBarHeight -
        bottom;
    return Size(width.clamp(1.0, double.infinity).toDouble(),
        height.clamp(1.0, double.infinity).toDouble());
  }

  static EdgeInsets mapPadding(BuildContext context, double sheetExtent) {
    final height = mapViewport(context).height;
    if (expanded(context)) {
      return const EdgeInsets.fromLTRB(20, 76, 20, 24);
    }
    final maximum = (height - 140).clamp(0.0, double.infinity);
    final bottom = (height * sheetExtent + 12).clamp(0.0, maximum);
    return EdgeInsets.fromLTRB(12, 72, 12, bottom.toDouble());
  }
}

class IrMobilityAppBar extends StatelessWidget implements PreferredSizeWidget {
  const IrMobilityAppBar({
    required this.title,
    required this.onMenu,
    required this.onProfile,
    this.photoUrl,
    super.key,
  });

  final String title;
  final VoidCallback onMenu;
  final VoidCallback onProfile;
  final String? photoUrl;

  @override
  Size get preferredSize =>
      const Size.fromHeight(IrMobilityLayout.appBarHeight);

  @override
  Widget build(BuildContext context) => AppBar(
        toolbarHeight: IrMobilityLayout.appBarHeight,
        titleSpacing: 4,
        leading: IconButton(
            tooltip: 'Abrir menú',
            onPressed: onMenu,
            icon: const Icon(Icons.menu_rounded)),
        title: Row(children: [
          const IrBrandLogo(size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: context.irColors.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.2)),
          ),
        ]),
        actions: [
          IconButton(
              tooltip: 'Abrir perfil',
              onPressed: onProfile,
              icon: CircleAvatar(
                  radius: 17,
                  backgroundColor: context.irColors.input,
                  child: photoUrl == null
                      ? Icon(Icons.person_outline,
                          size: 22, color: context.irColors.text)
                      : ClipOval(
                          child: Image.network(photoUrl!,
                              width: 34,
                              height: 34,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(
                                  Icons.person_outline,
                                  size: 22,
                                  color: context.irColors.text))))),
          const SizedBox(width: 12),
        ],
      );
}

List<(String, String, IconData, IconData)> _destinations(bool driver) => [
      (
        'home',
        driver ? 'Inicio' : 'Viajar',
        Icons.home_outlined,
        Icons.home_rounded
      ),
      (
        'history',
        'Actividad',
        Icons.receipt_long_outlined,
        Icons.receipt_long_rounded
      ),
      (
        driver ? 'wallet' : 'points',
        driver ? 'Bolsa IR' : 'Puntos',
        driver ? Icons.account_balance_wallet_outlined : Icons.stars_outlined,
        driver ? Icons.account_balance_wallet : Icons.stars_rounded,
      ),
      ('profile', 'Cuenta', Icons.person_outline, Icons.person_rounded),
    ];

class IrMobilityBottomNavigation extends StatelessWidget {
  const IrMobilityBottomNavigation({
    required this.onSelected,
    this.driver = false,
    super.key,
  });
  final bool driver;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final destinations = _destinations(driver);
    final restricted = MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) > 19;
    return DecoratedBox(
      decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.irColors.border))),
      child: NavigationBar(
        height: IrMobilityLayout.navigationHeight,
        selectedIndex: 0,
        animationDuration: const Duration(milliseconds: 160),
        backgroundColor: context.irColors.surface,
        indicatorColor: IrPalette.accent,
        labelBehavior: restricted
            ? NavigationDestinationLabelBehavior.onlyShowSelected
            : NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) {
          if (index != 0) onSelected(destinations[index].$1);
        },
        destinations: [
          for (final destination in destinations)
            NavigationDestination(
              icon: Icon(destination.$3, color: context.irColors.muted),
              selectedIcon: Icon(destination.$4, color: IrPalette.ink),
              label: destination.$2,
              tooltip: destination.$2,
            ),
        ],
      ),
    );
  }
}

class IrMobilityDrawerFooter extends StatelessWidget {
  const IrMobilityDrawerFooter({required this.onLogout, super.key});
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(height: 1, color: context.irColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: ListTile(
              leading: Icon(Icons.logout, color: context.irColors.muted),
              title: const Text('Cerrar sesión'),
              onTap: onLogout,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      );
}

class IrMobilityRail extends StatelessWidget {
  const IrMobilityRail({
    required this.onSelected,
    this.driver = false,
    super.key,
  });
  final bool driver;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final destinations = _destinations(driver);
    return SizedBox(
      width: IrMobilityLayout.railWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
            border: Border(right: BorderSide(color: context.irColors.border))),
        child: NavigationRail(
          selectedIndex: 0,
          minWidth: IrMobilityLayout.railWidth,
          backgroundColor: context.irColors.surface,
          indicatorColor: IrPalette.accent,
          labelType: MediaQuery.textScalerOf(context).scale(14) > 19
              ? NavigationRailLabelType.selected
              : NavigationRailLabelType.all,
          groupAlignment: -.85,
          selectedLabelTextStyle: TextStyle(
              fontFamily: 'Geist',
              color: context.irColors.text,
              fontSize: 11,
              fontWeight: FontWeight.w700),
          unselectedLabelTextStyle: TextStyle(
              fontFamily: 'Geist', color: context.irColors.muted, fontSize: 11),
          onDestinationSelected: (index) {
            if (index != 0) onSelected(destinations[index].$1);
          },
          destinations: [
            for (final destination in destinations)
              NavigationRailDestination(
                  icon: Icon(destination.$3, color: context.irColors.muted),
                  selectedIcon: Icon(destination.$4, color: IrPalette.ink),
                  label: Text(destination.$2,
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}
