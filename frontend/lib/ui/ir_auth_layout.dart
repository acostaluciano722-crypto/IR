import 'package:flutter/material.dart';

import 'ir_auth_scene.dart';
import 'ir_brand.dart';
import 'ir_theme.dart';

class IrAuthLayout extends StatelessWidget {
  const IrAuthLayout(
      {required this.title,
      required this.subtitle,
      required this.child,
      super.key});
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1000;
          final horizontal = constraints.maxWidth < 500 ? 24.0 : 40.0;
          return Column(children: [
            Container(
              height: 72,
              padding: EdgeInsets.symmetric(horizontal: horizontal),
              decoration: BoxDecoration(
                  border: Border(
                      bottom: BorderSide(color: context.irColors.border))),
              child: Row(children: [
                if (Navigator.of(context).canPop()) ...[
                  IconButton(
                      tooltip: 'Volver',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back)),
                  const SizedBox(width: 8),
                ],
                const IrBrandLogo(size: 36, showWordmark: true),
              ]),
            ),
            Expanded(
                child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                  horizontal, wide ? 48 : 32, horizontal, 32),
              child: Center(
                  child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            Expanded(child: _intro(context, true)),
                            const SizedBox(width: 100),
                            SizedBox(width: 420, child: child),
                          ])
                    : ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _intro(context, false),
                              const SizedBox(height: 28),
                              child
                            ])),
              )),
            )),
          ]);
        })),
      );

  Widget _intro(BuildContext context, bool wide) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  color: context.irColors.text,
                  fontSize: wide ? 42 : 30,
                  height: 1.12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: wide ? -1.2 : -.7)),
          const SizedBox(height: 12),
          Text(subtitle,
              style: TextStyle(
                  color: context.irColors.muted, fontSize: 15, height: 1.5)),
          if (wide) ...[
            const SizedBox(height: 36),
            const IrAuthScene(height: 260),
            const SizedBox(height: 20),
            Row(children: [
              Icon(Icons.route_outlined,
                  size: 20, color: context.irColors.accent),
              const SizedBox(width: 10),
              Expanded(
                  child: Text('Tú eliges el destino. Tú acuerdas la tarifa.',
                      style: TextStyle(
                          color: context.irColors.muted,
                          fontSize: 13,
                          height: 1.4))),
            ]),
          ],
        ],
      );
}

class IrInlineMessage extends StatelessWidget {
  const IrInlineMessage(
      {required this.message, this.error = false, this.onRetry, super.key});
  final String message;
  final bool error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = error ? scheme.error : context.irColors.muted;
    return Semantics(
        liveRegion: true,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: error
                  ? scheme.error.withValues(alpha: .08)
                  : context.irColors.raised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: error
                      ? scheme.error.withValues(alpha: .35)
                      : context.irColors.border)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(error ? Icons.error_outline : Icons.info_outline,
                  color: foreground, size: 20),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(message,
                      style: TextStyle(
                          color: foreground, fontSize: 13, height: 1.5))),
            ]),
            if (onRetry != null)
              TextButton(
                  onPressed: onRetry, child: const Text('Intentar de nuevo')),
          ]),
        ));
  }
}
