import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'ir_theme.dart';

enum IrMapSymbol { passenger, pickup, destination, car, motorcycle }

/// Original IR artwork, rasterized once as PNG for all Maps implementations.
class IrMapSymbols {
  IrMapSymbols._(this._icons);

  static Future<IrMapSymbols>? _cached;
  final Map<IrMapSymbol, BitmapDescriptor> _icons;

  static Future<IrMapSymbols> load() => _cached ??= _create();

  BitmapDescriptor operator [](IrMapSymbol symbol) => _icons[symbol]!;

  static Future<IrMapSymbols> _create() async {
    try {
      final icons = <IrMapSymbol, BitmapDescriptor>{};
      for (final symbol in IrMapSymbol.values) {
        const size = 52.0;
        const ratio = 3.0;
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)..scale(ratio);
        paint(canvas, const Size(size, size), symbol);
        final picture = recorder.endRecording();
        final image = await picture.toImage(
            (size * ratio).round(), (size * ratio).round());
        try {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          if (png == null) throw StateError('No se pudo dibujar el marcador.');
          icons[symbol] = BitmapDescriptor.bytes(
            png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
            width: size,
            height: size,
          );
        } finally {
          image.dispose();
          picture.dispose();
        }
      }
      return IrMapSymbols._(icons);
    } catch (_) {
      _cached = null;
      rethrow;
    }
  }

  /// Uses paths instead of font glyphs so map icons never depend on web fonts.
  static void paint(Canvas canvas, Size size, IrMapSymbol symbol) {
    canvas.save();
    canvas.scale(size.width / 52, size.height / 52);
    final ink = Paint()..color = IrPalette.ink;
    final white = Paint()..color = Colors.white;
    final yellow = Paint()..color = IrPalette.accent;
    final outline = Paint()
      ..color = IrPalette.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    const center = Offset(26, 26);

    switch (symbol) {
      case IrMapSymbol.passenger:
        canvas.drawCircle(center, 21, white);
        canvas.drawCircle(center, 19, ink);
        canvas.drawCircle(center, 16, yellow);
        canvas.drawCircle(const Offset(26, 22), 4.5, ink);
        canvas.drawRRect(
            RRect.fromRectAndCorners(const Rect.fromLTRB(18, 28, 34, 36),
                topLeft: const Radius.circular(7),
                topRight: const Radius.circular(7),
                bottomLeft: const Radius.circular(2),
                bottomRight: const Radius.circular(2)),
            ink);
      case IrMapSymbol.pickup:
        canvas.drawCircle(center, 14, white);
        canvas.drawCircle(center, 12, ink);
        canvas.drawCircle(center, 8, yellow);
        canvas.drawCircle(center, 3, ink);
      case IrMapSymbol.destination:
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTRB(12, 12, 40, 40), const Radius.circular(7)),
            white);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTRB(14, 14, 38, 38), const Radius.circular(5)),
            ink);
        canvas.drawRect(const Rect.fromLTRB(20, 20, 32, 32), yellow);
      case IrMapSymbol.car:
        // White perimeter and dark windows remain visible on both map themes.
        for (final x in [15.0, 34.0]) {
          for (final y in [15.0, 33.0]) {
            canvas.drawRRect(
                RRect.fromRectAndRadius(
                    Rect.fromLTWH(x, y, 3, 7), const Radius.circular(1)),
                ink);
          }
        }
        final body = RRect.fromRectAndRadius(
            const Rect.fromLTRB(17, 5, 35, 47), const Radius.circular(7));
        canvas.drawRRect(body, white);
        canvas.drawRRect(body, outline);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTRB(20, 16, 32, 33), const Radius.circular(3)),
            ink);
        canvas.drawRect(const Rect.fromLTRB(20, 22, 32, 28), white);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTRB(21, 8, 31, 12), const Radius.circular(2)),
            yellow);
        canvas.drawRect(const Rect.fromLTRB(21, 40, 31, 43), yellow);
      case IrMapSymbol.motorcycle:
        final halo = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..strokeCap = StrokeCap.round;
        final frame = Paint()
          ..color = IrPalette.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(const Offset(26, 8), const Offset(26, 44), halo);
        canvas.drawLine(const Offset(26, 8), const Offset(26, 44), frame);
        canvas.drawLine(const Offset(17, 17), const Offset(35, 17), halo);
        canvas.drawLine(const Offset(17, 17), const Offset(35, 17), frame);
        canvas.drawOval(const Rect.fromLTRB(18, 19, 34, 37), white);
        canvas.drawOval(const Rect.fromLTRB(18, 19, 34, 37), outline);
        canvas.drawOval(const Rect.fromLTRB(21, 21, 31, 30), yellow);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTRB(22, 30, 30, 39), const Radius.circular(3)),
            ink);
    }
    canvas.restore();
  }
}

class IrMapSymbolPreview extends StatelessWidget {
  const IrMapSymbolPreview({required this.symbol, this.size = 52, super.key});

  final IrMapSymbol symbol;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _SymbolPainter(symbol)),
      );
}

class _SymbolPainter extends CustomPainter {
  const _SymbolPainter(this.symbol);

  final IrMapSymbol symbol;

  @override
  void paint(Canvas canvas, Size size) =>
      IrMapSymbols.paint(canvas, size, symbol);

  @override
  bool shouldRepaint(_SymbolPainter oldDelegate) =>
      oldDelegate.symbol != symbol;
}
