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
        borderRadius: BorderRadius.circular(size * .25),
      ),
      alignment: Alignment.center,
      child: Text(
        'IR',
        style: TextStyle(
          color: IrPalette.ink,
          fontFamily: 'Georgia',
          fontSize: size * .38,
          fontWeight: FontWeight.w900,
          letterSpacing: -size * .045,
          height: .9,
        ),
      ),
    );

    if (!showWordmark) return mark;
    return Row(children: [
      mark,
      const SizedBox(width: 12),
      const Text('IR',
          style: TextStyle(
              color: IrPalette.text,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.5)),
    ]);
  }
}
