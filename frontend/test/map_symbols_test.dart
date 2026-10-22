import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ir_mobile/ui/ir_map_route.dart';
import 'package:ir_mobile/ui/ir_map_symbols.dart';
import 'package:ir_mobile/ui/ir_theme.dart';

import 'ui_review_test.dart' show captureUi, loadReviewFonts, pumpScreen;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadReviewFonts);

  test('all five markers are distinct transparent PNGs at a fixed map size',
      () async {
    final symbols = await IrMapSymbols.load();
    expect(identical(symbols, await IrMapSymbols.load()), isTrue);
    final payloads = <String>{};
    for (final kind in IrMapSymbol.values) {
      final icon = symbols[kind] as BytesMapBitmap;
      expect(icon.width, 52);
      expect(icon.height, 52);
      expect(icon.byteData.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      payloads.add(icon.byteData.toString());
      final codec = await ui.instantiateImageCodec(icon.byteData);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 156);
      expect(frame.image.height, 156);
      final pixels = await frame.image.toByteData();
      expect(pixels!.getUint8(3), 0);
      frame.image.dispose();
      codec.dispose();
    }
    expect(payloads, hasLength(5));
  });

  test('map presentation rejects invalid coordinates and handles a short route',
      () {
    expect(IrMapRoute.point('NaN', '-75.5'), isNull);
    expect(IrMapRoute.point(10, 900), isNull);
    expect(IrMapRoute.point(null, null), isNull);
    final points = IrMapRoute.points({
      'route_points': [
        {'lat': '10.41', 'lng': '-75.51'},
        {'lat': null, 'lng': '-75.51'},
        {'lat': 10.42, 'lng': -75.52},
      ]
    });
    expect(points, [const LatLng(10.41, -75.51), const LatLng(10.42, -75.52)]);
    final shortRoute = IrMapRoute.cameraPosition([points.first, points.first],
        viewport: const Size(320, 568),
        obscured: const EdgeInsets.fromLTRB(12, 80, 12, 200));
    expect(shortRoute.zoom, 18);
    expect(shortRoute.target.longitude, closeTo(-75.51, .000001));
    expect(shortRoute.target.latitude, lessThan(points.first.latitude));
  });

  test('route endpoints fit above the panel on compact and wide maps', () {
    const points = [LatLng(10.41, -75.51), LatLng(10.44, -75.54)];
    for (final size in [const Size(320, 568), const Size(1092, 516)]) {
      final insets = EdgeInsets.fromLTRB(12, 80, 12, size.height * .32);
      final camera =
          IrMapRoute.cameraPosition(points, viewport: size, obscured: insets);
      final center = _mercator(camera.target);
      final scale = 256 * math.pow(2, camera.zoom);
      for (final point in points) {
        final pixel = (_mercator(point) - center) * scale.toDouble() +
            Offset(size.width / 2, size.height / 2);
        expect(pixel.dx, inInclusiveRange(47.9, size.width - 47.9));
        expect(pixel.dy,
            inInclusiveRange(115.9, size.height - insets.bottom - 35.9));
      }
    }
  });

  testWidgets('route symbols stay readable on light and dark maps',
      (tester) async {
    await pumpScreen(
        tester,
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final light in [false, true]) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: light
                          ? const Color(0xFFE6E5E1)
                          : const Color(0xFF172129),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(children: [
                      for (final kind in IrMapSymbol.values)
                        Row(children: [
                          IrMapSymbolPreview(symbol: kind),
                          const SizedBox(width: 16),
                          Expanded(
                              child: Text(
                            const {
                              IrMapSymbol.passenger: 'Pasajero',
                              IrMapSymbol.pickup: 'Recogida',
                              IrMapSymbol.destination: 'Destino',
                              IrMapSymbol.car: 'Conductor · carro',
                              IrMapSymbol.motorcycle: 'Conductor · moto',
                            }[kind]!,
                            style: TextStyle(
                                color: light ? IrPalette.ink : Colors.white,
                                fontSize: 15),
                          )),
                        ]),
                    ]),
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ));
    await captureUi(tester, 'map-symbols');
    expect(tester.takeException(), isNull);
  });
}

Offset _mercator(LatLng point) {
  final latitude = point.latitude * math.pi / 180;
  return Offset(
      (point.longitude + 180) / 360,
      (1 - math.log(math.tan(latitude) + 1 / math.cos(latitude)) / math.pi) /
          2);
}
