import 'package:flutter/material.dart';

import 'ir_theme.dart';

class IrBrandLogo extends StatelessWidget {
  const IrBrandLogo({this.size = 96, this.showWordmark = false, super.key});

  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final logo = SizedBox.square(
      dimension: size,
      child: Image.asset(
        'assets/branding/ir_logo.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        excludeFromSemantics: true,
      ),
    );

    if (!showWordmark) {
      return Semantics(
        image: true,
        label: 'IR',
        child: Center(child: logo),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(image: true, label: 'IR', child: logo),
        const SizedBox(width: 12),
        Text(
          'IR',
          style: TextStyle(
            color: context.irColors.text,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -.7,
          ),
        ),
      ],
    );
  }
}
