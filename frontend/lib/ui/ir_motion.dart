import 'package:flutter/material.dart';

abstract final class IrMotion {
  static const feedback = Duration(milliseconds: 120);
  static const transition = Duration(milliseconds: 220);
  static const entrance = Duration(milliseconds: 420);
  static const welcomeOpening = Duration(milliseconds: 620);
  static const welcomeOpeningExit = Duration(milliseconds: 240);

  static Duration duration(BuildContext context, Duration value) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : value;

  static Widget buttonFeedback(
      BuildContext context, Set<WidgetState> states, Widget? child) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final scale = reduced
        ? 1.0
        : states.contains(WidgetState.pressed)
            ? .97
            : states.contains(WidgetState.hovered)
                ? 1.015
                : 1.0;
    return AnimatedScale(
      scale: scale,
      duration: duration(context, feedback),
      curve: Curves.easeOutCubic,
      child: child,
    );
  }
}

class IrMapAction extends StatelessWidget {
  const IrMapAction(
      {required this.icon,
      required this.label,
      required this.onPressed,
      super.key});
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => SizedBox.square(
      dimension: 56,
      child: IconButton.filledTonal(
          tooltip: label,
          onPressed: onPressed,
          icon: Icon(icon, size: 26),
          style: IconButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  side: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant))
              .copyWith(foregroundBuilder: IrMotion.buttonFeedback)));
}

class IrResponsiveActions extends StatelessWidget {
  const IrResponsiveActions({required this.children, super.key});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 360 ||
            MediaQuery.textScalerOf(context).scale(16) > 21) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  children[i]
                ]
              ]);
        }
        return Row(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: children[i])
          ]
        ]);
      });
}
