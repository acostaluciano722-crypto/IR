import 'package:flutter/material.dart';

import 'ir_theme.dart';

class IrLogoMark extends StatelessWidget {
  const IrLogoMark({this.size = 96, this.showWordmark = false, super.key});

  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: IrPalette.accent,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(size * .28),
          topRight: Radius.circular(size * .28),
          bottomRight: Radius.circular(size * .28),
          bottomLeft: Radius.circular(size * .08),
        ),
      ),
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            'IR',
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              color: IrPalette.ink,
              fontFamily: 'Georgia',
              fontSize: size * .38,
              fontWeight: FontWeight.w900,
              letterSpacing: -size * .014,
              height: .9,
            ),
          ),
          Positioned(
            top: size * .13,
            right: size * .13,
            child: Container(
              width: size * .07,
              height: size * .07,
              decoration: const BoxDecoration(
                  color: IrPalette.ink, shape: BoxShape.circle),
            ),
          ),
        ],
      ),
    );

    if (!showWordmark) return mark;
    return Row(children: [
      mark,
      const SizedBox(width: 12),
      Text('IR',
          textScaler: TextScaler.noScaling,
          style: TextStyle(
              color: context.irColors.text,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -.7)),
    ]);
  }
}
