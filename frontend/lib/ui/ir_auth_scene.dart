import 'package:flutter/material.dart';
import 'ir_theme.dart';

/// A route diagram, not a simulated live map or availability claim.
class IrAuthScene extends StatelessWidget {
  const IrAuthScene({this.height = 260, super.key});
  final double height;

  @override
  Widget build(BuildContext context) => Semantics(
        image: true,
        label: 'Diagrama de un recorrido entre origen y destino',
        child: ExcludeSemantics(
            child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: ColoredBox(
                color: context.irColors.raised,
                child: Stack(children: [
                  Positioned.fill(
                      child: CustomPaint(
                          painter: _RouteScenePainter(
                              road: context.irColors.border,
                              water: context.irColors.surface))),
                  const Positioned(
                      left: 20,
                      top: 20,
                      child:
                          _MapLabel(icon: Icons.my_location, text: 'Origen')),
                  const Positioned(
                      right: 20,
                      bottom: 20,
                      child: _MapLabel(
                          icon: Icons.place_outlined, text: 'Destino')),
                ])),
          ),
        )),
      );
}

class _MapLabel extends StatelessWidget {
  const _MapLabel({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
            color: context.irColors.surface,
            borderRadius: BorderRadius.circular(10)),
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 17),
              const SizedBox(width: 8),
              Text(text,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ])),
      );
}

class _RouteScenePainter extends CustomPainter {
  const _RouteScenePainter({required this.road, required this.water});
  final Color road;
  final Color water;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 520, size.height / 280);
    final coastline = Path()
      ..moveTo(0, 0)
      ..lineTo(92, 0)
      ..cubicTo(133, 68, 35, 132, 112, 192)
      ..quadraticBezierTo(151, 227, 126, 280)
      ..lineTo(0, 280)
      ..close();
    canvas.drawPath(coastline, Paint()..color = water);
    final streetPaint = Paint()
      ..color = road
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    final streets = [
      Path()
        ..moveTo(133, -10)
        ..cubicTo(181, 69, 138, 176, 209, 292),
      Path()
        ..moveTo(245, -10)
        ..cubicTo(216, 83, 294, 175, 270, 292),
      Path()
        ..moveTo(359, -10)
        ..cubicTo(318, 94, 406, 167, 380, 292),
      Path()
        ..moveTo(479, -10)
        ..cubicTo(438, 89, 492, 210, 475, 292),
      Path()
        ..moveTo(98, 87)
        ..cubicTo(215, 52, 337, 117, 530, 61),
      Path()
        ..moveTo(80, 174)
        ..cubicTo(202, 137, 329, 213, 530, 163),
      Path()
        ..moveTo(126, 247)
        ..cubicTo(291, 236, 352, 265, 530, 235),
    ];
    for (final path in streets) {
      canvas.drawPath(path, streetPaint);
    }
    final route = Path()
      ..moveTo(166, 91)
      ..cubicTo(199, 82, 235, 93, 243, 115)
      ..lineTo(267, 169)
      ..cubicTo(306, 179, 354, 188, 389, 181);
    canvas.drawPath(
        route,
        Paint()
          ..color = IrPalette.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(
        const Offset(166, 91), 9, Paint()..color = IrPalette.accent);
    canvas.drawCircle(const Offset(166, 91), 4, Paint()..color = water);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(381, 173, 16, 16), const Radius.circular(3)),
        Paint()..color = IrPalette.accent);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RouteScenePainter oldDelegate) =>
      road != oldDelegate.road || water != oldDelegate.water;
}
