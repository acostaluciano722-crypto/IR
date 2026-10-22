import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:ir_mobile/screens/driver_home_screen.dart';
import 'package:ir_mobile/screens/passenger_home_screen.dart';
import 'package:ir_mobile/services/api_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show GoogleMap;
import 'package:ir_mobile/ui/ir_map_layout.dart';
import 'package:ir_mobile/ui/ir_map_symbols.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import 'ui_review_test.dart' show captureUi, pumpScreen, loadReviewFonts;

class _MapPlatform extends GoogleMapsFlutterPlatform {
  @override
  Widget buildViewWithConfiguration(
    int creationId,
    PlatformViewCreatedCallback onPlatformViewCreated, {
    required MapWidgetConfiguration widgetConfiguration,
    MapConfiguration mapConfiguration = const MapConfiguration(),
    MapObjects mapObjects = const MapObjects(),
  }) =>
      const ColoredBox(
          color: Color(0xFF26302E),
          child: Center(
              child:
                  Icon(Icons.map_outlined, color: Colors.white38, size: 72)));
}

class _LocationPlatform extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => false;
}

class _EnabledLocationPlatform extends _LocationPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;
  @override
  Future<Position> getCurrentPosition(
          {LocationSettings? locationSettings}) async =>
      Position(
          latitude: 10.41,
          longitude: -75.51,
          timestamp: DateTime(2026, 10, 21),
          accuracy: 1,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0);
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      const Stream.empty();
}

class _Api extends ApiService {
  _Api(
      {this.rides = const [],
      this.available = const [],
      this.status = 'offline'});
  final List<Map<String, dynamic>> rides;
  final List<Map<String, dynamic>> available;
  final String status;
  @override
  Future<List<Map<String, dynamic>>> getRides() async => rides;
  @override
  Future<List<Map<String, dynamic>>> getDriverRides() async => rides;
  @override
  Future<List<Map<String, dynamic>>> getDriverAvailableRides() async =>
      available;
  @override
  Future<Map<String, dynamic>> getPassengerMe() async =>
      {'points': 1200, 'tier': 'Inicial'};
  @override
  Future<Map<String, dynamic>> getDriverMe() async => {
        'status': status,
        'wallet_balance': '50000.00',
        'reserved_balance': '1500.00',
        'points': 1200,
        'tier': 'Inicial'
      };
  @override
  Future<Map<String, dynamic>> estimateRoute(
          {required double originLat,
          required double originLng,
          required double destinationLat,
          required double destinationLng}) async =>
      {};
}

class _RatingApi extends _Api {
  _RatingApi() : super(rides: [_ride('validated')]);
  @override
  Future<void> rateRide(int rideId, int rating) async =>
      throw ApiException('No se pudo guardar la calificación.');
}

class _NearbyApi extends _Api {
  int selections = 0;
  @override
  Future<List<Map<String, dynamic>>> nearbyPlaces(
          double latitude, double longitude) async =>
      [
        {'place_id': 'nearby-clock', 'name': 'Torre del Reloj'}
      ];
  @override
  Future<Map<String, dynamic>> placeDetails(String placeId) async {
    expect(placeId, 'nearby-clock');
    selections++;
    return {'lat': 10.42, 'lng': -75.52};
  }

  @override
  Future<Map<String, dynamic>> estimateRoute(
          {required double originLat,
          required double originLng,
          required double destinationLat,
          required double destinationLng}) async =>
      {
        'route_points': [
          {'lat': originLat, 'lng': originLng},
          {'lat': destinationLat, 'lng': destinationLng}
        ],
        'distance_km': 2,
        'duration_minutes': 6,
      };
}

Map<String, dynamic> _ride(String status) => {
      'id': 1,
      'status': status,
      'origin': 'Centro histórico de Cartagena',
      'destination':
          'Centro comercial Paseo de la Castellana, entrada principal',
      'passenger_name': 'María Alejandra García Rodríguez',
      'driver_name': 'Juan Carlos Martínez López',
      'distance_km': 12.5,
      'duration_minutes': 28,
      'offer_amount': '15000.00',
      'estimated_price': '18000.00',
      'final_fare': '15000.00',
      'vehicle_type': 'economy',
      'pickup_code': 'A1B2C3',
      'driver_vehicle_type': 'moto',
      'driver_vehicle_plate': 'ABC123',
      'driver_vehicle_brand': 'Marca del vehículo',
      'driver_vehicle_color': 'Negro',
      'remaining_seconds': 200,
      'offers': <Map<String, dynamic>>[],
    };

void main() {
  setUpAll(() async {
    await loadReviewFonts();
    await IrMapSymbols.load();
  });
  setUp(() {
    GoogleMapsFlutterPlatform.instance = _MapPlatform();
    GeolocatorPlatform.instance = _LocationPlatform();
  });
  const user = {'name': 'María Alejandra García Rodríguez'};
  for (final light in [false, true]) {
    testWidgets('passenger controls, drawer and text scaling, light=$light',
        (tester) async {
      await pumpScreen(tester, PassengerHomeScreen(api: _Api(), user: user),
          light: light);
      final menu = find.byTooltip('Abrir menú');
      final location = find.byTooltip('Centrar en mi ubicación');
      expect(tester.getRect(menu).overlaps(tester.getRect(location)), isFalse);
      await captureUi(tester, 'passenger-${light ? 'light' : 'dark'}');
      await tester.tap(menu);
      await tester.pumpAndSettle();
      expect(find.text('Cerrar sesión'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpScreen(tester, PassengerHomeScreen(api: _Api(), user: user),
          size: const Size(320, 568), textScale: 1.6, light: light);
      await tester.tap(find.byTooltip('Abrir menú'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'driver handles decimal balances, requests and drawer, light=$light',
        (tester) async {
      await pumpScreen(
          tester,
          DriverHomeScreen(
              api: _Api(status: 'available', available: [_ride('searching')]),
              user: user),
          light: light);
      expect(find.text('Disponible para recibir viajes'), findsOneWidget);
      await captureUi(tester, 'driver-${light ? 'light' : 'dark'}');
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Abrir menú'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpScreen(
          tester,
          DriverHomeScreen(
              api: _Api(status: 'available', available: [_ride('searching')]),
              user: user),
          size: const Size(320, 568),
          textScale: 1.6,
          light: light);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final status in ['accepted', 'validated']) {
    testWidgets('active ride $status fits small screens', (tester) async {
      await pumpScreen(tester,
          PassengerHomeScreen(api: _Api(rides: [_ride(status)]), user: user),
          size: const Size(320, 568), textScale: 1.6);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpScreen(
          tester,
          DriverHomeScreen(
              api: _Api(
                  rides: [_ride(status)],
                  status: status == 'validated'
                      ? 'available'
                      : 'reserved_for_trip'),
              user: user),
          size: const Size(320, 568),
          textScale: 1.6);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('map sheet intercepts pointers and adapts to short wide screens',
      (tester) async {
    await pumpScreen(
      tester,
      PassengerHomeScreen(api: _Api(), user: user),
      size: const Size(1092, 516),
    );

    final title = find.text('Elige cómo viajar');
    expect(title, findsOneWidget);
    expect(tester.getRect(title).top, lessThan(260));
    await captureUi(tester, 'passenger-wide-short');
    expect(find.ancestor(of: title, matching: find.byType(PointerInterceptor)),
        findsOneWidget);

    for (final label in ['Viaje', 'Moto', 'Viaje+', 'Comfort']) {
      final rect = tester.getRect(find.text(label));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(1092));
    }
    expect(tester.getRect(find.text('Comfort')).right, greaterThan(800));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpScreen(
      tester,
      PassengerHomeScreen(api: _Api(), user: user),
      size: const Size(280, 653),
      textScale: 1.4,
    );
    expect(
        tester.getRect(find.byTooltip('Abrir menú')).overlaps(
            tester.getRect(find.byTooltip('Centrar en mi ubicación'))),
        isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('destination stays accessible above the keyboard',
      (tester) async {
    await pumpScreen(tester, PassengerHomeScreen(api: _Api(), user: user));
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final field = find.byType(TextField);
    await tester.ensureVisible(field);
    await tester.pump();
    expect(tester.getRect(field).bottom, lessThanOrEqualTo(524));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('both roles show custom symbols and a usable route overview',
      (tester) async {
    final ride = {
      ..._ride('accepted'),
      'origin_lat': '10.420',
      'origin_lng': '-75.520',
      'passenger_lat': '10.420',
      'passenger_lng': '-75.520',
      'driver_lat': '10.410',
      'driver_lng': '-75.510',
      'destination_lat': '10.440',
      'destination_lng': '-75.540',
    };
    for (final driver in [false, true]) {
      await pumpScreen(
          tester,
          driver
              ? DriverHomeScreen(
                  api: _Api(rides: [ride], status: 'reserved_for_trip'),
                  user: user)
              : PassengerHomeScreen(api: _Api(rides: [ride]), user: user),
          size: const Size(320, 568),
          textScale: 1.6);
      await tester.runAsync(() => IrMapSymbols.load());
      await tester.pumpAndSettle();
      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      expect(map.markers.length, greaterThanOrEqualTo(3),
          reason: 'driver=$driver');
      for (final marker in map.markers) {
        expect(marker.icon, isA<BytesMapBitmap>());
        expect(
            marker.anchor,
            marker.markerId.value == 'current-location'
                ? const Offset(.5, .97)
                : const Offset(.5, .5));
      }
      final destination = map.markers.singleWhere((marker) =>
          marker.markerId.value ==
          (driver ? 'active-destination' : 'destination'));
      expect(destination.position, const LatLng(10.440, -75.540));
      expect(map.myLocationEnabled, isFalse);
      final overview = find.byTooltip('Ver recorrido completo');
      final menu = find.byTooltip('Abrir menú');
      expect(tester.getRect(overview).overlaps(tester.getRect(menu)), isFalse);
      await tester.tap(overview);
      await tester.pumpAndSettle();
      final sheet = tester.widget<DraggableScrollableSheet>(
          find.byType(DraggableScrollableSheet));
      final layout = IrMapLayout.of(tester.element(find.byType(GoogleMap)));
      expect(
          sheet.controller!.size,
          closeTo(
              driver ? layout.driverMinimum : layout.passengerMinimum, .01));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('a nearby destination reuses the existing route selection',
      (tester) async {
    GeolocatorPlatform.instance = _EnabledLocationPlatform();
    final api = _NearbyApi();
    await pumpScreen(tester, PassengerHomeScreen(api: api, user: user));
    tester
        .widget<DraggableScrollableSheet>(find.byType(DraggableScrollableSheet))
        .controller!
        .jumpTo(.9);
    await tester.pumpAndSettle();
    final place = find.text('Torre del Reloj');
    await tester.ensureVisible(place);
    await tester.tap(place);
    await tester.pumpAndSettle();
    expect(api.selections, 1);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Torre del Reloj');
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Elegir viaje'))
            .onPressed,
        isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed rating keeps the review available to retry',
      (tester) async {
    await pumpScreen(
        tester, PassengerHomeScreen(api: _RatingApi(), user: user));
    tester
        .widget<DraggableScrollableSheet>(find.byType(DraggableScrollableSheet))
        .controller!
        .jumpTo(.9);
    await tester.pump();
    await tester.ensureVisible(find.text('Continuar'));
    await tester.tap(find.text('Continuar'));
    await tester.pump();
    await tester.ensureVisible(find.byTooltip('4 estrellas'));
    await tester.tap(find.byTooltip('4 estrellas'));
    await tester.pump();
    await tester.ensureVisible(find.text('Guardar calificación'));
    await tester.tap(find.text('Guardar calificación'));
    await tester.pump();
    expect(find.text('Califica a tu conductor'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(SnackBar),
            matching: find.text('No se pudo guardar la calificación.')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('signing out clears the token and returns to welcome',
      (tester) async {
    final api = _Api()..token = 'test-token';
    await pumpScreen(tester, PassengerHomeScreen(api: api, user: user));
    await tester.tap(find.byTooltip('Abrir menú'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Cerrar sesión'));
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 800));
    expect(api.token, isNull);
    expect(find.text('Viaja para ganar'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
