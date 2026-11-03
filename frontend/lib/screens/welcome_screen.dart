import 'package:flutter/material.dart';

import '../ui/ir_auth_scene.dart';
import '../ui/ir_brand.dart';
import '../ui/ir_components.dart';

import '../ui/ir_theme.dart';
import 'login_screen.dart';
import 'register_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 800;
          final side = constraints.maxWidth < 500 ? 24.0 : 40.0;
          return Column(children: [
            Container(
                height: 72,
                padding: EdgeInsets.symmetric(horizontal: side),
                decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(color: context.irColors.border))),
                child: Row(children: [
                  const IrBrandLogo(size: 38, showWordmark: true),
                  const Spacer(),
                  Icon(Icons.place_outlined,
                      size: 17, color: context.irColors.muted),
                  const SizedBox(width: 6),
                  Flexible(
                      child: Text('Cartagena',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: context.irColors.muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w500))),
                ])),
            Expanded(
                child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(side, wide ? 36 : 28, side, 28),
              child: Center(
                  child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(children: [
                  IrEntrance(
                      child: Column(children: [
                    Text('Viaja para ganar',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: context.irColors.text,
                            fontSize: wide ? 60 : 40,
                            height: 1.08,
                            fontWeight: FontWeight.w700,
                            letterSpacing: wide ? -1.8 : -1.1)),
                    const SizedBox(height: 14),
                    ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 500),
                        child: Text(
                            'Pide, acuerda y muévete por tu ciudad con claridad.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: context.irColors.muted,
                                fontSize: 16,
                                height: 1.5))),
                  ])),
                  const SizedBox(height: 28),
                  ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: IrAuthScene(height: wide ? 240 : 194)),
                  const SizedBox(height: 28),
                  ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: LayoutBuilder(builder: (context, space) {
                        final create = FilledButton(
                            onPressed: () => Navigator.of(context).push(
                                _openingRoute(
                                    context, (_) => const RegisterScreen())),
                            child: const Text('Crear cuenta'));
                        final login = OutlinedButton(
                            onPressed: () => Navigator.of(context).push(
                                _openingRoute(
                                    context, (_) => const LoginScreen())),
                            child: const Text('Iniciar sesión'));
                        if (space.maxWidth >= 440 &&
                            MediaQuery.textScalerOf(context).scale(16) <= 21) {
                          return Row(children: [
                            Expanded(child: create),
                            const SizedBox(width: 12),
                            Expanded(child: login)
                          ]);
                        }
                        return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              create,
                              const SizedBox(height: 12),
                              login
                            ]);
                      })),
                  const SizedBox(height: 24),
                  Text('Tarifas acordadas. Cada viaje suma.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: context.irColors.muted,
                          fontSize: 13,
                          height: 1.5)),
                ]),
              )),
            )),
          ]);
        })),
      );

  MaterialPageRoute<void> _openingRoute(
          BuildContext context, WidgetBuilder page) =>
      MaterialPageRoute<void>(builder: page);
}
