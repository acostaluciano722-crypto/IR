import 'package:flutter/material.dart';

class IrPageBody extends StatelessWidget {
  const IrPageBody({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: child)),
      );
}
