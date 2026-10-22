import 'package:flutter/material.dart';
import 'ir_brand.dart';
import 'ir_components.dart';
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
  Widget build(BuildContext context) => Scaffold(body: IrEditorialBackdrop(
          child: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 820;
        final header = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              IconButton.filledTonal(
                  tooltip: 'Volver',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back)),
              const SizedBox(width: 12),
              const IrBrandLogo(size: 42, showWordmark: true),
            ]),
            SizedBox(height: wide ? 78 : 34),
            Container(
                width: 46,
                height: 4,
                decoration: BoxDecoration(
                    color: context.irColors.accent,
                    borderRadius: BorderRadius.circular(99))),
            const SizedBox(height: 18),
            Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: context.irColors.text,
                    fontSize: wide ? 52 : 36,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: wide ? -2 : -1.1)),
            const SizedBox(height: 14),
            Text(subtitle,
                style: TextStyle(
                    color: context.irColors.muted, fontSize: 16, height: 1.5)),
          ],
        );
        final form = IrPanel(
            padding: EdgeInsets.fromLTRB(
                wide ? 28 : 18, wide ? 30 : 24, wide ? 28 : 18, 24),
            child: child);
        return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                        wide ? 48 : 20, 16, wide ? 48 : 20, 32),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                Expanded(child: IrEntrance(child: header)),
                                const SizedBox(width: 64),
                                SizedBox(
                                    width: 430,
                                    child: IrEntrance(
                                        delay:
                                            const Duration(milliseconds: 100),
                                        child: form)),
                              ])
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                                IrEntrance(child: header),
                                const SizedBox(height: 28),
                                IrEntrance(
                                    delay: const Duration(milliseconds: 100),
                                    child: form),
                              ]))));
      }))));
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
    return Semantics(
        liveRegion: true,
        child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: error ? scheme.errorContainer : context.irColors.raised,
                borderRadius: BorderRadius.circular(12)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(error ? Icons.error_outline : Icons.info_outline,
                    color: error
                        ? scheme.onErrorContainer
                        : context.irColors.accent,
                    size: 22),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(message,
                        style: TextStyle(
                            color: error
                                ? scheme.onErrorContainer
                                : context.irColors.text,
                            height: 1.4))),
              ]),
              if (onRetry != null)
                TextButton(onPressed: onRetry, child: const Text('Reintentar')),
            ])));
  }
}
