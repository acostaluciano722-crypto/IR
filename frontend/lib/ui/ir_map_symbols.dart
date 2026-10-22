import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'ir_theme.dart';

enum IrMapSymbol { passenger, pickup, destination, car, motorcycle }

/// Original IR artwork, rasterized once as PNG for all Maps implementations.
class IrMapSymbols {
  IrMapSymbols._(this._icons);

  static Future<IrMapSymbols>? _cached;
  static final Map<String, Future<BitmapDescriptor>> _passengerMarkers = {};
  final Map<IrMapSymbol, BitmapDescriptor> _icons;

  static Future<IrMapSymbols> load() => _cached ??= _create();

  BitmapDescriptor operator [](IrMapSymbol symbol) => _icons[symbol]!;

  Future<BitmapDescriptor> passengerMarker(String? photoUrl) {
    final key = photoUrl?.trim().isNotEmpty == true ? photoUrl!.trim() : '';
    return _passengerMarkers.putIfAbsent(key, () => _createPassengerMarker(key));
  }

  static Future<BitmapDescriptor> _createPassengerMarker(String photoUrl) async {
    ui.Image? avatar;
    if (photoUrl.isNotEmpty) {
      final completer = Completer<ui.Image>();
      final stream = NetworkImage(photoUrl).resolve(ImageConfiguration.empty);
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          if (!completer.isCompleted) completer.complete(info.image.clone());
        },
        onError: (error, stackTrace) {
          if (!completer.isCompleted) completer.completeError(error, stackTrace);
        },
      );
      stream.addListener(listener);
      try {
        avatar = await completer.future.timeout(const Duration(seconds: 8));
      } catch (_) {
        // Keep the marker usable when a remote profile photo cannot load.
      } finally {
        stream.removeListener(listener);
      }
    }

    const logicalSize = Size(56, 78);
    const ratio = 3.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(ratio);
    final pin = Path()
      ..moveTo(28, 76)
      ..lineTo(6, 36)
      ..cubicTo(-1, 22, 7, 3, 28, 3)
      ..cubicTo(49, 3, 57, 22, 50, 36)
      ..close();
    canvas.drawShadow(pin, Colors.black.withValues(alpha: .28), 3, false);
    canvas.drawPath(pin, Paint()..color = const Color(0xFFFFD000));
    canvas.drawPath(
      pin,
      Paint()
        ..color = const Color(0xFF171B1D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    const center = Offset(28, 26);
    canvas.drawCircle(center, 19.5, Paint()..color = Colors.white);
    canvas.drawCircle(center, 17.2, Paint()..color = const Color(0xFF171B1D));
    if (avatar != null) {
      final sourceSize = avatar.width < avatar.height ? avatar.width : avatar.height;
      final source = Rect.fromLTWH(
        (avatar.width - sourceSize) / 2,
        (avatar.height - sourceSize) / 2,
        sourceSize.toDouble(),
        sourceSize.toDouble(),
      );
      final destination = Rect.fromCircle(center: center, radius: 15.5);
      canvas.save();
      canvas.clipPath(Path()..addOval(destination));
      canvas.drawImageRect(
        avatar,
        source,
        destination,
        Paint()..filterQuality = FilterQuality.high,
      );
      canvas.restore();
      avatar.dispose();
    } else {
      final person = Paint()..color = const Color(0xFF171B1D);
      canvas.drawCircle(const Offset(28, 22), 5.5, person);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTRB(18, 28, 38, 39),
          const Radius.circular(8),
        ),
        person,
      );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (logicalSize.width * ratio).round(),
      (logicalSize.height * ratio).round(),
    );
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw StateError('No se pudo dibujar el marcador.');
      return BitmapDescriptor.bytes(
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        width: logicalSize.width,
        height: logicalSize.height,
      );
    } finally {
      image.dispose();
      picture.dispose();
    }
  }

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
