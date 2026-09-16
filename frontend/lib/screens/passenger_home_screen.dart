import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';

import '../services/api_service.dart';
import 'bonus_screen.dart';
import 'points_screen.dart';
import 'role_section_screen.dart';

class PassengerHomeScreen extends StatefulWidget {
  const PassengerHomeScreen({required this.api, required this.user, super.key});
  final ApiService api;
  final Map<String, dynamic> user;

  @override
  State<PassengerHomeScreen> createState() => _PassengerHomeScreenState();
}

class _PassengerHomeScreenState extends State<PassengerHomeScreen> {
  final _destination = TextEditingController();
  final _origin = TextEditingController(text: 'Mi ubicación actual');
  String _vehicle = 'economy';
  List<Map<String, dynamic>> _rides = [];
  final Set<int> _dismissedRatedRideIds = <int>{};
  final Set<int> _closedReviewRideIds = <int>{};
  List<Map<String, dynamic>> _suggestions = [];
  List<Map<String, dynamic>> _nearbyPlaces = [];
  int _points = 0;
  String _tier = 'Inicial';
  LatLng _location = const LatLng(10.391, -75.4794);
  LatLng? _destinationLocation;
  String? _selectedDestination;
  Map<String, dynamic>? _route;
  StreamSubscription<Position>? _locationSubscription;
  Timer? _searchDebounce;
  Timer? _rideRefreshTimer;
  GoogleMapController? _mapController;
  bool _hasInitialLocation = false;
  bool _loading = false;
  bool _menuExpanded = false;
  bool _navigationCardCondensed = false;
  int _sheetVersion = 0;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadRides();
    _loadPassengerProfile();
    _startLocationTracking();
    _rideRefreshTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _loadRides());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _rideRefreshTimer?.cancel();
    _locationSubscription?.cancel();
    _mapController?.dispose();
    _origin.dispose();
    _destination.dispose();
    super.dispose();
  }

  Future<void> _loadRides() async {
    try {
      final rides = await widget.api.getRides();
      if (mounted) {
        setState(() => _rides = rides
            .where((ride) =>
                !_closedReviewRideIds.contains(_asInt(ride['id'])) &&
                !_dismissedRatedRideIds.contains(_asInt(ride['id'])))
            .toList());
      }
    } catch (_) {}
  }

  Future<void> _loadPassengerProfile() async {
    try {
      final profile = await widget.api.getPassengerMe();
      if (mounted)
        setState(() {
          _points = profile['points'] ?? 0;
          _tier = profile['tier'] ?? 'Inicial';
        });
    } catch (_) {}
  }

  Map<String, dynamic>? get _activeRide {
    const activeStatuses = {
      'requested',
      'searching',
      'negotiating',
      'driver_selected',
      'accepted',
      'en_route',
      'arrived',
      'in_progress',
      'completed',
      'validated',
    };
    for (final ride in _rides) {
      final rideId = _asInt(ride['id']);
      if (activeStatuses.contains(ride['status']) &&
          ride['passenger_rating'] == null &&
          !_closedReviewRideIds.contains(rideId) &&
          !_dismissedRatedRideIds.contains(rideId)) return ride;
    }
    return null;
  }

  Future<void> _selectOffer(int rideId, int offerId) async {
    try {
      await widget.api.selectRideOffer(rideId, offerId);
      await _loadRides();
      if (mounted)
        setState(() =>
            _message = 'Conductor seleccionado. La reserva fue confirmada.');
    } on ApiException catch (error) {
      if (mounted) setState(() => _message = error.message);
    }
  }

  Future<void> _rejectOffer(int rideId, int offerId) async {
    try {
      await widget.api.rejectRideOffer(rideId, offerId);
      await _loadRides();
    } on ApiException catch (error) {
      if (mounted) setState(() => _message = error.message);
    }
  }

  Future<void> _rateRide(int rideId, int rating) async {
    _closeRideReview(rideId);
    try {
      await widget.api.rateRide(rideId, rating);
      _dismissedRatedRideIds.add(rideId);
      await _loadRides();
    } on ApiException catch (error) {
      if (mounted) setState(() => _message = error.message);
    }
  }

  Future<void> _skipRideRating(int rideId) async {
    _closeRideReview(rideId);
    _dismissedRatedRideIds.add(rideId);
    await _loadRides();
  }

  void _closeRideReview(int rideId) {
    _closedReviewRideIds.add(rideId);
    _dismissedRatedRideIds.add(rideId);
    if (!mounted) return;
    setState(() {
      _rides = _rides.where((ride) => _asInt(ride['id']) != rideId).toList();
      _sheetVersion++;
    });
    _clearDestination();
  }

  Future<void> _cancelRide(int rideId, String reason) async {
    try {
      await widget.api.cancelRide(rideId, reason: reason);
      await _loadRides();
      if (mounted) {
        _clearDestination(message: 'Viaje cancelado.');
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _message = error.message);
    }
  }

  void _clearDestination({String? message}) {
    _searchDebounce?.cancel();
    _destination.clear();
    setState(() {
      _selectedDestination = null;
      _destinationLocation = null;
      _route = null;
      _suggestions = [];
      _message = message;
    });
  }

  Future<void> _requestRide() async {
    if (_destination.text.trim().isEmpty) {
      setState(() => _message = 'Escribe un destino para continuar.');
      return;
    }
    var route = _route;
    var destinationLocation = _destinationLocation;
    if (destinationLocation == null || route == null) {
      setState(() => _message =
          'Selecciona un destino de la lista para confirmar su ubicación.');
      return;
    }
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final fare = _decreeFareFor(_destination.text, _vehicle);
      final distanceKm = _asDouble(route['distance_km']);
      final durationMinutes = _asInt(route['duration_minutes']);
      if (distanceKm == null || durationMinutes == null) {
        if (mounted)
          setState(() => _message =
              'La ruta no tiene datos suficientes para solicitar el viaje.');
        return;
      }
      await widget.api.requestRide(
          origin: _origin.text.trim(),
          destination: _destination.text.trim(),
          vehicleType: _vehicle,
          offerAmount: fare,
          estimatedPrice: fare,
          originLat: _roundCoordinate(_location.latitude),
          originLng: _roundCoordinate(_location.longitude),
          destinationLat: _roundCoordinate(destinationLocation.latitude),
          destinationLng: _roundCoordinate(destinationLocation.longitude),
          distanceKm: distanceKm,
          durationMinutes: durationMinutes);
      _selectedDestination = null;
      await _loadRides();
      if (mounted)
        setState(() => _message = 'Solicitud enviada. Buscando tu conductor.');
    } on ApiException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (error) {
      if (mounted)
        setState(() => _message = 'No se pudo enviar la solicitud: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _decreeFareFor(String destination, String vehicle) {
    final normalized = destination.toUpperCase();
    var carFare = 12250;
    const zoneFares = {
      2: 13150,
      3: 14950,
      4: 16900,
      5: 18250,
      6: 23500,
      7: 25500,
      8: 30600,
      9: 40400,
      10: 50800,
    };
    const zoneKeywords = {
      2: [
        'DANIEL LE MAITRE',
        'ALCIBIA',
        'BRUSELAS',
        'LA MARIA',
        'MARTINEZ MARTELO',
        'EL PRADO',
        'SAN FRANCISCO'
      ],
      3: [
        'ARMENIA',
        'BOSTON',
        'OLAYA SECTOR',
        'EL BOSQUE',
        'TESCA',
        'REPUBLICA DEL LIBANO',
        'PIEDRA DE BOLIVAR',
        'JUNIN',
        'JUAN XXIII',
        'ESPAÑA'
      ],
      4: [
        'ESCALLON VILLA',
        'UNIDAD DEPORTIVA',
        'HOSPITAL UNIVERSITARIO',
        'LOS CERROS',
        'REPUBLICA DE CHILE',
        'EL CAIRO',
        'LAS BRISAS',
        'ZARAGOCILLA',
        'CASTILLETE',
        'SAN ISIDRO',
        'CHAPACUA'
      ],
      5: [
        'NUEVO BOSQUE',
        'EL COUNTRY',
        'CAMAGUEY',
        'TACARIGUA',
        'LA FLORESTA',
        'LA CAMPIÑA',
        'EL CARMEN',
        'EL EDEN',
        'LAS GAVIOTAS',
        'CEBALLOS'
      ],
      6: [
        'VISTA HERMOSA',
        'LOS CALAMARES',
        'LOS ANGELES',
        'EL GOLF',
        'EL RUBI',
        'VILLA SANDRA',
        'LA CASTELLANA',
        'TRECE DE JUNIO',
        'SANTA CLARA',
        'BLAS DE LEZO',
        'ALMIRANTE COLON',
        'LOS ALPES'
      ],
      7: [
        'EL CARMELO',
        'PLAN 400',
        'URBANIZACION BARU',
        'CIUDAD SEVILLA',
        'UNIV. SAN BUENAVENTURA',
        'EL EDUCADOR',
        'LOS JARDINES',
        'LA CONSOLATA',
        'VILLA RUBIA',
        'LA CONCEPCION',
        'SAN FERNANDO',
        'TERNERA'
      ],
      8: [
        'SAN JOSE DE LOS CAMPANOS',
        'UNIVERSIDAD TECNOLOGICA',
        'CIUDADELA ONCE NOVIEMBRE',
        'SIMON BOLIVAR',
        'MARIA CANO',
        'CAMILO TORRES',
        'NAZARENO',
        'LA SIERRITA',
        'VEINTE DE JULIO',
        'EL REPOSO',
        'LA BOQUILLA'
      ],
      9: [
        'FLOR DEL CAMPO',
        'VILLA DE ARANJUEZ',
        'BICENTENARIO',
        'COLOMBIATON',
        'ROCKY VALDEZ',
        'INDIA CATALINA',
        'MAMONAL',
        'PASACABALLOS'
      ],
      10: [
        'ZONA FRANCA',
        'TERMINAL DE TRANSPORTE NORTE',
        'LAGUNA CLUB TERRANOVA',
        'UNIVERSIDAD TADEO LOZANO',
        'PUNTA CANOA',
        'BAYUNCA'
      ],
    };
    for (final entry in zoneKeywords.entries) {
      if (entry.value.any(normalized.contains)) {
        carFare = zoneFares[entry.key]!;
        break;
      }
    }
    return vehicle == 'moto' ? (carFare * 0.35).round() : carFare;
  }

  Future<void> _selectDestination(String destination, String? placeId) async {
    setState(() {
      _destination.text = destination;
      _selectedDestination = destination;
      _suggestions = [];
      _message = null;
      _route = null;
    });
    if (placeId == null) return;
    try {
      final details = await widget.api.placeDetails(placeId);
      final coordinates = LatLng((details['lat'] as num).toDouble(),
          (details['lng'] as num).toDouble());
      final outsideCartagena = !_isInsideCartagena(coordinates);
      final route = await widget.api.estimateRoute(
          originLat: _location.latitude,
          originLng: _location.longitude,
          destinationLat: coordinates.latitude,
          destinationLng: coordinates.longitude);
      if (mounted) {
        setState(() {
          _destinationLocation = coordinates;
          _route = route;
          if (outsideCartagena) {
            _vehicle = 'economy';
            _message =
                'Los destinos fuera de Cartagena se solicitan como Viaje.';
          }
        });
        await _fitRoute(coordinates, route);
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _message = error.message);
    }
  }

  bool _isInsideCartagena(LatLng coordinates) {
    return coordinates.latitude >= 10.20 &&
        coordinates.latitude <= 10.60 &&
        coordinates.longitude >= -75.70 &&
        coordinates.longitude <= -75.30;
  }

  void _onDestinationChanged(String value) {
    setState(() {
      if (_selectedDestination != null && value != _selectedDestination) {
        _selectedDestination = null;
        _destinationLocation = null;
        _route = null;
      }
      if (value.isEmpty) _message = null;
    });
    _searchPlaces(value);
  }

  Future<void> _searchPlaces(String query) async {
    _searchDebounce?.cancel();
    if (query.trim().length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final suggestions = await widget.api.searchPlaces(query.trim());
        if (mounted) setState(() => _suggestions = suggestions);
      } on ApiException catch (error) {
        if (mounted) setState(() => _message = error.message);
      }
    });
  }

  Future<void> _startLocationTracking() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted)
          setState(() => _message = 'Activa la ubicación del dispositivo.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied)
        permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted)
          setState(() => _message =
              'Permite la ubicación para mantener tu posición activa.');
        return;
      }
      await _locationSubscription?.cancel();
      final position = await Geolocator.getCurrentPosition();
      await _updateLocation(position, loadNearby: true);
      if (!_hasInitialLocation && _mapController != null) {
        _hasInitialLocation = true;
        await _mapController!
            .animateCamera(CameraUpdate.newLatLngZoom(_location, 16));
      }
      _locationSubscription = Geolocator.getPositionStream(
              locationSettings: const LocationSettings(
                  accuracy: LocationAccuracy.high, distanceFilter: 10))
          .listen((position) => _updateLocation(position));
    } catch (_) {
      if (mounted)
        setState(() => _message = 'No se pudo obtener tu ubicación actual.');
    }
  }

  Future<void> _recenterOnUser() async {
    await _startLocationTracking();
    if (_mapController != null) {
      await _mapController!
          .animateCamera(CameraUpdate.newLatLngZoom(_location, 16));
    }
  }

  Future<void> _updateLocation(Position position,
      {bool loadNearby = false}) async {
    final next = LatLng(position.latitude, position.longitude);
    if (mounted)
      setState(() {
        _location = next;
        _origin.text = 'Ubicación actual';
      });
    final activeRide = _activeRide;
    if (activeRide != null && activeRide['id'] is int) {
      await widget.api
          .updateRideLocation(
            rideId: activeRide['id'] as int,
            latitude: next.latitude,
            longitude: next.longitude,
          )
          .catchError((_) => <String, dynamic>{});
    }
    if (loadNearby) {
      final nearby = await widget.api
          .nearbyPlaces(position.latitude, position.longitude)
          .catchError((_) => <Map<String, dynamic>>[]);
      if (mounted) setState(() => _nearbyPlaces = nearby);
    }
    if (_destinationLocation != null) {
      final route = await widget.api
          .estimateRoute(
              originLat: next.latitude,
              originLng: next.longitude,
              destinationLat: _destinationLocation!.latitude,
              destinationLng: _destinationLocation!.longitude)
          .catchError((_) => <String, dynamic>{});
      if (mounted && route.isNotEmpty) setState(() => _route = route);
    }
  }

  Future<void> _onMapCreated(GoogleMapController controller) async {
    _mapController = controller;
    await controller.animateCamera(CameraUpdate.newLatLngZoom(_location, 15));
  }

  void _openMenuSection(String value) {
    setState(() => _menuExpanded = false);
    final screen = value == 'points'
        ? PointsScreen(role: 'passenger', points: _points, tier: _tier)
        : value == 'bonus'
            ? BonusScreen(role: 'passenger', points: _points, tier: _tier)
            : RoleSectionScreen(
                title: value == 'history'
                    ? 'Historial de viajes'
                    : value == 'support'
                        ? 'Soporte IR'
                        : 'Perfil',
                role: 'passenger',
                items: _passengerSectionItems(
                    value,
                    _rides,
                    widget.user['name']?.toString() ?? 'Usuario IR',
                    _points,
                    _tier));
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _fitRoute(LatLng destination, Map<String, dynamic> route) async {
    if (_mapController == null) return;
    final points = _routePoints(route, destination);
    final routePoints = points.isEmpty ? [_location, destination] : points;
    var minLat = routePoints.first.latitude;
    var maxLat = routePoints.first.latitude;
    var minLng = routePoints.first.longitude;
    var maxLng = routePoints.first.longitude;
    for (final point in routePoints.skip(1)) {
      minLat = point.latitude < minLat ? point.latitude : minLat;
      maxLat = point.latitude > maxLat ? point.latitude : maxLat;
      minLng = point.longitude < minLng ? point.longitude : minLng;
      maxLng = point.longitude > maxLng ? point.longitude : maxLng;
    }
    await _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
        LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng)),
        72));
  }

  Set<Polyline> get _routeLines {
    final points = _destinationLocation == null
        ? <LatLng>[]
        : _routePoints(_route, _destinationLocation!);
    if (points.length < 2) return {};
    return {
      Polyline(
        polylineId: const PolylineId('ride-route'),
        points: points,
        color: const Color(0xFFE8F044),
        width: 6,
        jointType: JointType.round,
      ),
    };
  }

  List<LatLng> _routePoints(Map<String, dynamic>? route, LatLng destination) {
    if (route == null) return [];
    final rawPoints = (route['route_points'] as List?) ?? [];
    final points = rawPoints
        .map((point) => LatLng(
            (point['lat'] as num).toDouble(), (point['lng'] as num).toDouble()))
        .toList();
    if (points.length >= 2) return points;
    return [];
  }

  Map<String, dynamic>? _nextStep(Map<String, dynamic>? route) {
    final steps =
        (route?['steps'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final step in steps) {
      final endLat = (step['end_lat'] as num?)?.toDouble();
      final endLng = (step['end_lng'] as num?)?.toDouble();
      if (endLat == null || endLng == null) continue;
      if (Geolocator.distanceBetween(
              _location.latitude, _location.longitude, endLat, endLng) >
          45) return step;
    }
    return steps.isEmpty ? null : steps.last;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF171B1D),
        body: SafeArea(
          bottom: false,
          child: Stack(children: [
            Positioned.fill(
              child: GoogleMap(
                initialCameraPosition: const CameraPosition(
                    target: LatLng(10.405, -75.505), zoom: 14.5),
                onMapCreated: _onMapCreated,
                myLocationButtonEnabled: false,
                myLocationEnabled: true,
                zoomControlsEnabled: false,
                scrollGesturesEnabled: true,
                webGestureHandling: WebGestureHandling.greedy,
                zoomGesturesEnabled: true,
                rotateGesturesEnabled: true,
                tiltGesturesEnabled: true,
                markers: {
                  Marker(
                    markerId: const MarkerId('current-location'),
                    position: _location,
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueYellow),
                    infoWindow: const InfoWindow(
                        title: 'Tu ubicación',
                        snippet: 'Ubicación activa en tiempo real'),
                  ),
                  if (_destinationLocation != null)
                    Marker(
                        markerId: const MarkerId('destination'),
                        position: _destinationLocation!,
                        icon: BitmapDescriptor.defaultMarkerWithHue(
                            BitmapDescriptor.hueYellow),
                        zIndexInt: 2,
                        infoWindow: InfoWindow(
                            title: _destination.text,
                            snippet: 'Destino seleccionado')),
                  if (_activeRide?['driver_lat'] != null &&
                      _activeRide?['driver_lng'] != null)
                    Marker(
                      markerId: const MarkerId('driver-location'),
                      position: LatLng(
                        _asDouble(_activeRide!['driver_lat'])!,
                        _asDouble(_activeRide!['driver_lng'])!,
                      ),
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueAzure),
                      infoWindow: const InfoWindow(title: 'Tu conductor'),
                    ),
                },
                polylines: _routeLines,
                style: _googleMapStyle,
              ),
            ),
            Positioned(
                top: 18,
                right: 18,
                child: _RoundAction(
                    icon: Icons.my_location, onPressed: _recenterOnUser)),
            Positioned(
              top: 84,
              left: 20,
              right: 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_destination.text.isNotEmpty &&
                      !_menuExpanded &&
                      !{
                        'accepted',
                        'driver_selected',
                        'en_route',
                        'arrived',
                        'in_progress',
                      }.contains(_activeRide?['status'])) ...[
                    const SizedBox(height: 8),
                    _NavigationCard(
                        destination: _destination.text,
                        route: _route,
                        nextStep: _nextStep(_route),
                        condensed: _navigationCardCondensed),
                  ],
                ],
              ),
            ),
            Positioned.fill(
              child: NotificationListener<DraggableScrollableNotification>(
                onNotification: (notification) {
                  final condensed = notification.extent >= 0.52;
                  if (condensed != _navigationCardCondensed && mounted) {
                    setState(() => _navigationCardCondensed = condensed);
                  }
                  return false;
                },
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: DraggableScrollableSheet(
                    key: ValueKey('passenger-ride-sheet-$_sheetVersion'),
                    expand: false,
                    initialChildSize: 0.43,
                    minChildSize: 0.36,
                    maxChildSize: 0.90,
                    snapSizes: const [0.43, 0.90],
                    snap: true,
                    builder: (context, controller) => _RideSheet(
                      controller: controller,
                      destinationController: _destination,
                      origin: _origin.text,
                      vehicle: _vehicle,
                      loading: _loading,
                      message: _message,
                      route: _route,
                      rides: _rides,
                      points: _points,
                      tier: _tier,
                      suggestions: _suggestions,
                      nearbyPlaces: _nearbyPlaces,
                      activeRide: _activeRide,
                      onVehicleChanged: (value) =>
                          setState(() => _vehicle = value),
                      onSuggestionSelected: (place) => _selectDestination(
                          place['description'].toString(),
                          place['place_id']?.toString()),
                      onNearbySelected: (place) => _selectDestination(
                          place['name'].toString(),
                          place['place_id']?.toString()),
                      onQueryChanged: _onDestinationChanged,
                      fare: _route == null
                          ? null
                          : _decreeFareFor(_destination.text, _vehicle),
                      onRequestRide: _requestRide,
                      onSelectOffer: _selectOffer,
                      onRejectOffer: _rejectOffer,
                      onCancelRide: _cancelRide,
                      onRateRide: _rateRide,
                      onSkipRating: _skipRideRating,
                    ),
                  ),
                ),
              ),
            ),
            if (_menuExpanded)
              Positioned.fill(
                  child: GestureDetector(
                      onTap: () => setState(() => _menuExpanded = false),
                      child: Container(
                          color:
                              const Color(0xFF000000).withValues(alpha: .42)))),
            AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                top: 0,
                bottom: 0,
                left: _menuExpanded ? 0 : -324,
                width: 308,
                child: _PassengerSideBar(
                    onClose: () => setState(() => _menuExpanded = false),
                    onSectionSelected: _openMenuSection)),
            Positioned(
                top: 16,
                left: 18,
                child: _RoundAction(
                    icon: _menuExpanded ? Icons.close : Icons.menu,
                    onPressed: () =>
                        setState(() => _menuExpanded = !_menuExpanded))),
          ]),
        ),
      );
}

double? _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

double _roundCoordinate(double value) {
  return double.parse(value.toStringAsFixed(6));
}

int? _asInt(dynamic value) {
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '');
}

List<SectionItem> _passengerSectionItems(
    String section,
    List<Map<String, dynamic>> rides,
    String userName,
    int points,
    String tier) {
  if (section == 'history') {
    if (rides.isEmpty)
      return const [
        SectionItem(
            icon: Icons.inbox_outlined,
            title: 'Sin viajes todavía',
            description:
                'Tus viajes aparecerán aquí cuando completes una solicitud.')
      ];
    return rides
        .map((ride) => SectionItem(
            icon: Icons.route,
            title: '${ride['origin']} → ${ride['destination']}',
            description:
                'Estado: ${ride['status']} · Tarifa: COP ${ride['final_fare'] == 0 ? ride['offer_amount'] : ride['final_fare']}'))
        .toList();
  }
  if (section == 'support')
    return const [
      SectionItem(
          icon: Icons.help_outline,
          title: 'Centro de ayuda',
          description:
              'Consulta preguntas frecuentes y crea un caso de soporte.'),
      SectionItem(
          icon: Icons.security_outlined,
          title: 'Centro de seguridad',
          description: 'Los reportes de seguridad tienen atención prioritaria.')
    ];
  return [
    SectionItem(
        icon: Icons.person_outline,
        title: userName,
        description: 'Rol: pasajero'),
    SectionItem(
        icon: Icons.stars_outlined,
        title: 'Nivel $tier',
        description: '$points PI de actividad válida')
  ];
}

const _googleMapStyle = '''[
  {"elementType":"geometry","stylers":[{"color":"#11151b"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#aeb7c2"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#11151b"}]},
  {"featureType":"poi","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#28333e"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#626b75"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#091017"}]}
]''';

class _PassengerSideBar extends StatelessWidget {
  const _PassengerSideBar(
      {required this.onClose, required this.onSectionSelected});
  final VoidCallback onClose;
  final ValueChanged<String> onSectionSelected;

  static const _items = [
    ('points', 'Puntos', Icons.stars_outlined),
    ('bonus', 'Bonificaciones', Icons.card_giftcard_outlined),
    ('history', 'Historial', Icons.history),
    ('support', 'Soporte', Icons.support_agent_outlined),
    ('profile', 'Perfil', Icons.person_outline),
  ];

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF111213),
        elevation: 10,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 82, 16, 20),
            children: [
              Row(children: [
                const Expanded(
                    child: Text('IR',
                        style: TextStyle(
                            color: Color(0xFFE8F044),
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1))),
                IconButton(
                    tooltip: 'Cerrar menú',
                    onPressed: onClose,
                    icon: const Icon(Icons.close, color: Colors.white70)),
              ]),
              const SizedBox(height: 8),
              const Divider(color: Color(0xFF343638)),
              const SizedBox(height: 8),
              ..._items.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      minVerticalPadding: 8,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      leading: Icon(item.$3,
                          color: const Color(0xFFE8F044), size: 24),
                      title: Text(item.$2,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                      onTap: () => onSectionSelected(item.$1),
                    ),
                  )),
            ],
          ),
        ),
      );
}

class _RideSheet extends StatelessWidget {
  const _RideSheet(
      {required this.controller,
      required this.destinationController,
      required this.origin,
      required this.vehicle,
      required this.loading,
      required this.message,
      required this.route,
      required this.rides,
      required this.points,
      required this.tier,
      required this.suggestions,
      required this.nearbyPlaces,
      required this.activeRide,
      required this.fare,
      required this.onVehicleChanged,
      required this.onSuggestionSelected,
      required this.onNearbySelected,
      required this.onQueryChanged,
      required this.onRequestRide,
      required this.onSelectOffer,
      required this.onRejectOffer,
      required this.onCancelRide,
      required this.onRateRide,
      required this.onSkipRating});
  final ScrollController controller;
  final TextEditingController destinationController;
  final String origin;
  final String vehicle;
  final bool loading;
  final String? message;
  final Map<String, dynamic>? route;
  final List<Map<String, dynamic>> rides;
  final int points;
  final String tier;
  final List<Map<String, dynamic>> suggestions;
  final List<Map<String, dynamic>> nearbyPlaces;
  final Map<String, dynamic>? activeRide;
  final int? fare;
  final ValueChanged<String> onVehicleChanged;
  final ValueChanged<Map<String, dynamic>> onSuggestionSelected;
  final ValueChanged<Map<String, dynamic>> onNearbySelected;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onRequestRide;
  final void Function(int rideId, int offerId) onSelectOffer;
  final void Function(int rideId, int offerId) onRejectOffer;
  final void Function(int rideId, String reason) onCancelRide;
  final void Function(int rideId, int rating) onRateRide;
  final Future<void> Function(int rideId) onSkipRating;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
            color: Color(0xFF111213),
            borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
            children: [
              Center(
                  child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                          color: Colors.white38,
                          borderRadius: BorderRadius.circular(5)))),
              const SizedBox(height: 16),
              if (activeRide != null)
                _ActiveRidePanel(
                    ride: activeRide!,
                    onSelectOffer: onSelectOffer,
                    onRejectOffer: onRejectOffer,
                    onCancelRide: onCancelRide,
                    onRateRide: onRateRide,
                    onSkipRating: onSkipRating)
              else ...[
                _VehiclePicker(selected: vehicle, onChanged: onVehicleChanged),
                const SizedBox(height: 16),
                _PointsCard(points: points, tier: tier),
                const SizedBox(height: 14),
                TextField(
                  controller: destinationController,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                      hintText: '¿A dónde y por cuánto?',
                      hintStyle: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700),
                      prefixIcon: const Icon(Icons.search,
                          color: Colors.white, size: 31),
                      suffixIcon: destinationController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Borrar destino',
                              onPressed: () {
                                destinationController.clear();
                                onQueryChanged('');
                              },
                              icon: const Icon(Icons.close,
                                  color: Colors.white70)),
                      filled: true,
                      fillColor: const Color(0xFF303031),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 18)),
                  onChanged: onQueryChanged,
                  onSubmitted: (_) => onRequestRide(),
                ),
                ...suggestions.take(5).map((place) => _PlaceRow(
                    title: place['description'].toString(),
                    onTap: () => onSuggestionSelected(place))),
                if (route != null && fare != null)
                  _RouteSummary(route: route!, fare: fare!),
                const SizedBox(height: 8),
                _OriginRow(origin: origin),
                if (message != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 4, left: 10),
                      child: Text(message!,
                          style: const TextStyle(color: Color(0xFFE8F044)))),
                if (destinationController.text.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  FilledButton(
                      onPressed: loading ? null : onRequestRide,
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFE8F044),
                          foregroundColor: const Color(0xFF171B1D),
                          minimumSize: const Size.fromHeight(52)),
                      child: loading
                          ? const CircularProgressIndicator(
                              color: Color(0xFF171B1D))
                          : const Text('Elegir viaje',
                              style: TextStyle(fontWeight: FontWeight.w800))),
                ],
              ],
              if (rides.isNotEmpty) ...[
                const SizedBox(height: 18),
                const Text('Viajes recientes',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
                ...rides.take(3).map((ride) =>
                    _RecentRide(ride: ride, onSelectOffer: onSelectOffer)),
              ],
            ]),
      );
}

class _ActiveRidePanel extends StatefulWidget {
  const _ActiveRidePanel(
      {required this.ride,
      required this.onSelectOffer,
      required this.onRejectOffer,
      required this.onCancelRide,
      required this.onRateRide,
      required this.onSkipRating});
  final Map<String, dynamic> ride;
  final void Function(int rideId, int offerId) onSelectOffer;
  final void Function(int rideId, int offerId) onRejectOffer;
  final void Function(int rideId, String reason) onCancelRide;
  final void Function(int rideId, int rating) onRateRide;
  final Future<void> Function(int rideId) onSkipRating;

  @override
  State<_ActiveRidePanel> createState() => _ActiveRidePanelState();
}

class _ActiveRidePanelState extends State<_ActiveRidePanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _searchAnimation;
  bool _showRating = false;

  @override
  void initState() {
    super.initState();
    _searchAnimation = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 6500));
    _syncSearchAnimation();
  }

  @override
  void didUpdateWidget(covariant _ActiveRidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ride['id'] != widget.ride['id'] ||
        oldWidget.ride['status'] != widget.ride['status']) {
      _showRating = false;
    }
    _syncSearchAnimation();
  }

  void _syncSearchAnimation() {
    final status = widget.ride['status']?.toString();
    final searching = status == 'searching' ||
        status == 'requested' ||
        status == 'negotiating';
    if (searching && !_searchAnimation.isAnimating) {
      _searchAnimation.repeat();
    } else if (!searching && _searchAnimation.isAnimating) {
      _searchAnimation.stop();
    }
  }

  @override
  void dispose() {
    _searchAnimation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final status = ride['status']?.toString() ?? 'requested';
    final offers =
        (ride['offers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final rideId = ride['id'] as int?;
    final canSelect = status == 'searching' ||
        status == 'requested' ||
        status == 'negotiating';
    if (status == 'completed' || status == 'validated') {
      if (!_showRating) {
        return _RideCompletionPanel(
          ride: ride,
          onContinue: () => setState(() => _showRating = true),
        );
      }
      return _RatingPanel(
        title: 'Califica a tu conductor',
        personName: ride['driver_name']?.toString() ?? 'Conductor IR',
        rideId: rideId,
        existingRating: ride['passenger_rating'],
        onRate: widget.onRateRide,
        onSkip: widget.onSkipRating,
      );
    }
    final searching = status == 'requested' || status == 'negotiating';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_statusTitle(status),
          style: const TextStyle(
              color: Colors.white, fontSize: 23, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text(_statusDescription(status),
          style: const TextStyle(color: Colors.white70, fontSize: 15)),
      const SizedBox(height: 16),
      ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: searching
              ? AnimatedBuilder(
                  animation: _searchAnimation,
                  builder: (context, child) => LinearProgressIndicator(
                      value: _searchAnimation.value,
                      minHeight: 5,
                      backgroundColor: const Color(0xFF343638),
                      color: const Color(0xFFE8F044)))
              : LinearProgressIndicator(
                  value: _statusProgress(status),
                  minHeight: 5,
                  backgroundColor: const Color(0xFF343638),
                  color: const Color(0xFFE8F044))),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: const Color(0xFF202122),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF2D2E2F))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_vehicleLabel(ride['vehicle_type']?.toString()),
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          Text(_rideMessage(status, ride),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  height: 1.15,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          Row(children: [
            const Icon(Icons.my_location, color: Color(0xFFE8F044), size: 20),
            const SizedBox(width: 9),
            Expanded(
                child: Text(_displayOrigin(ride['origin']?.toString()),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.location_on, color: Color(0xFFE8F044), size: 20),
            const SizedBox(width: 9),
            Expanded(
                child: Text(ride['destination']?.toString() ?? 'Destino',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600))),
          ]),
          if (status == 'accepted') ...[
            const SizedBox(height: 16),
            _DriverInfoPanel(ride: ride),
          ],
          if (ride['driver_lat'] != null && ride['driver_lng'] != null) ...[
            const SizedBox(height: 12),
            _LiveDistanceRow(
              label: 'Distancia al conductor',
              distanceKm: ride['live_distance_km'],
            ),
          ],
          const SizedBox(height: 14),
          Row(children: [
            Text(
                'COP ${ride['final_fare'] == 0 ? ride['offer_amount'] : ride['final_fare']}',
                style: const TextStyle(
                    color: Color(0xFFE8F044), fontWeight: FontWeight.w800)),
            const SizedBox(width: 12),
            Text('${ride['distance_km']} km · ${ride['duration_minutes']} min',
                style: const TextStyle(color: Colors.white54)),
          ]),
        ]),
      ),
      if (offers.isNotEmpty) ...[
        const SizedBox(height: 18),
        const Text('Ofertas de conductores',
            style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ...offers.map((offer) => _OfferTile(
              offer: offer,
              enabled:
                  canSelect && rideId != null && offer['status'] == 'pending',
              onSelect: () => widget.onSelectOffer(rideId!, offer['id'] as int),
              onReject: () => widget.onRejectOffer(rideId!, offer['id'] as int),
            )),
      ],
      const SizedBox(height: 18),
      OutlinedButton(
          onPressed: () => _showCancelFlow(context, rideId),
          style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFF6B6B),
              minimumSize: const Size.fromHeight(52),
              side: const BorderSide(color: Color(0xFF6F3030)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14))),
          child: const Text('Cancelar viaje',
              style: TextStyle(fontWeight: FontWeight.w800))),
    ]);
  }

  Future<void> _showCancelFlow(BuildContext context, int? rideId) async {
    if (rideId == null) return;
    final reason = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF171819),
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (_) => const _CancelRideSheet());
    if (reason != null && context.mounted) {
      widget.onCancelRide(rideId, reason);
    }
  }
}

class _CancelRideSheet extends StatefulWidget {
  const _CancelRideSheet();

  @override
  State<_CancelRideSheet> createState() => _CancelRideSheetState();
}

class _CancelRideSheetState extends State<_CancelRideSheet> {
  String? _reason;

  static const _reasons = [
    'Lo solicité por error',
    'Seleccioné un punto de partida incorrecto',
    'Solicité un vehículo incorrecto',
    'El tiempo de espera fue demasiado',
    'Seleccioné un destino incorrecto',
    'Otro',
  ];

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                    color: Colors.white38,
                    borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 20),
            const Text('¿Quieres cancelar el viaje?',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Align(
                alignment: Alignment.centerLeft,
                child: Text('¿Por qué quieres cancelar? Opcional',
                    style: TextStyle(color: Colors.white70, fontSize: 15))),
            const SizedBox(height: 10),
            ..._reasons.map((reason) => RadioListTile<String>(
                  value: reason,
                  groupValue: _reason,
                  activeColor: const Color(0xFFE8F044),
                  contentPadding: EdgeInsets.zero,
                  title:
                      Text(reason, style: const TextStyle(color: Colors.white)),
                  onChanged: (value) => setState(() => _reason = value),
                )),
            const SizedBox(height: 10),
            SizedBox(
                width: double.infinity,
                child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(_reason ?? ''),
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFF5D5D),
                        foregroundColor: const Color(0xFF171B1D),
                        minimumSize: const Size.fromHeight(54)),
                    child: const Text('Cancelar viaje',
                        style: TextStyle(fontWeight: FontWeight.w800)))),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Conservar mi viaje',
                  style: TextStyle(color: Colors.white70)),
            ),
          ]),
        ),
      );
}

class _OfferTile extends StatelessWidget {
  const _OfferTile(
      {required this.offer,
      required this.enabled,
      required this.onSelect,
      required this.onReject});
  final Map<String, dynamic> offer;
  final bool enabled;
  final VoidCallback onSelect;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        decoration: BoxDecoration(
            color: const Color(0xFF191A1B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF343638))),
        child: Row(children: [
          const CircleAvatar(
              backgroundColor: Color(0xFFE8F044),
              foregroundColor: Color(0xFF171B1D),
              child: Icon(Icons.person, size: 20)),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(offer['driver_name']?.toString() ?? 'Conductor IR',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
                Text('${offer['amount']} COP · ${offer['status']}',
                    style:
                        const TextStyle(color: Colors.white60, fontSize: 12)),
              ])),
          if (enabled)
            Column(children: [
              TextButton(
                  onPressed: onSelect,
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFE8F044)),
                  child: const Text('Aceptar')),
              TextButton(
                  onPressed: onReject,
                  style: TextButton.styleFrom(foregroundColor: Colors.white60),
                  child: const Text('Rechazar')),
            ]),
        ]),
      );
}

class _LiveDistanceRow extends StatelessWidget {
  const _LiveDistanceRow({required this.label, required this.distanceKm});

  final String label;
  final dynamic distanceKm;

  @override
  Widget build(BuildContext context) {
    final distance = distanceKm is num
        ? distanceKm.toDouble().toStringAsFixed(2)
        : 'calculando';
    return Row(children: [
      const Icon(Icons.near_me_outlined, color: Color(0xFFE8F044), size: 20),
      const SizedBox(width: 9),
      Text('$label: $distance km',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700)),
    ]);
  }
}

class _RideCompletionPanel extends StatelessWidget {
  const _RideCompletionPanel({required this.ride, required this.onContinue});

  final Map<String, dynamic> ride;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 22),
        decoration: BoxDecoration(
            color: const Color(0xFF202122),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF343638))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Resumen de tu viaje',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          _SummaryRow(
              icon: Icons.my_location,
              label: 'Origen',
              value: ride['origin']?.toString() ?? 'Ubicación actual'),
          const SizedBox(height: 10),
          _SummaryRow(
              icon: Icons.location_on,
              label: 'Destino',
              value: ride['destination']?.toString() ?? 'Destino'),
          const SizedBox(height: 10),
          _SummaryRow(
              icon: Icons.payments_outlined,
              label: 'Total',
              value:
                  'COP ${ride['final_fare'] == 0 ? ride['offer_amount'] : ride['final_fare']}'),
          const SizedBox(height: 10),
          _SummaryRow(
              icon: Icons.route,
              label: 'Recorrido',
              value:
                  '${ride['distance_km']} km · ${ride['duration_minutes']} min'),
          const SizedBox(height: 18),
          SizedBox(
              width: double.infinity,
              child: FilledButton(
                  onPressed: onContinue,
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE8F044),
                      foregroundColor: const Color(0xFF171B1D),
                      minimumSize: const Size.fromHeight(48)),
                  child: const Text('Continuar'))),
        ]),
      );
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: const Color(0xFFE8F044), size: 20),
        const SizedBox(width: 9),
        Expanded(
            child: RichText(
                text: TextSpan(
                    style: const TextStyle(color: Colors.white70),
                    children: [
              TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: value),
            ]))),
      ]);
}

class _RatingPanel extends StatefulWidget {
  const _RatingPanel(
      {required this.title,
      required this.personName,
      required this.rideId,
      required this.existingRating,
      required this.onRate,
      required this.onSkip});
  final String title;
  final String personName;
  final int? rideId;
  final dynamic existingRating;
  final void Function(int rideId, int rating) onRate;
  final Future<void> Function(int rideId) onSkip;

  @override
  State<_RatingPanel> createState() => _RatingPanelState();
}

class _RatingPanelState extends State<_RatingPanel> {
  int _rating = 0;

  @override
  void initState() {
    super.initState();
    _rating = (widget.existingRating as num?)?.toInt() ?? 0;
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 22),
        decoration: BoxDecoration(
            color: const Color(0xFF202122),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF343638))),
        child: Column(children: [
          Text(widget.title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          const CircleAvatar(
              radius: 34,
              backgroundColor: Color(0xFFE8F044),
              child: Icon(Icons.person, color: Color(0xFF171B1D), size: 34)),
          const SizedBox(height: 10),
          Text(widget.personName,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                  5,
                  (index) => IconButton(
                        onPressed: widget.rideId == null
                            ? null
                            : () => setState(() => _rating = index + 1),
                        icon: Icon(
                            index < _rating ? Icons.star : Icons.star_border,
                            color: index < _rating
                                ? const Color(0xFFE8F044)
                                : Colors.white54,
                            size: 34),
                        tooltip: '${index + 1} estrellas',
                      ))),
          const SizedBox(height: 8),
          FilledButton(
              onPressed: widget.rideId != null &&
                      _rating > 0 &&
                      widget.existingRating == null
                  ? () => widget.onRate(widget.rideId!, _rating)
                  : null,
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE8F044),
                  foregroundColor: const Color(0xFF171B1D),
                  minimumSize: const Size.fromHeight(48)),
              child: Text(widget.existingRating == null
                  ? 'Guardar calificación'
                  : 'Calificación enviada')),
          TextButton(
              onPressed: widget.rideId == null
                  ? null
                  : () => widget.onSkip(widget.rideId!),
              child: const Text('Omitir por ahora')),
        ]),
      );
}

class _DriverInfoPanel extends StatelessWidget {
  const _DriverInfoPanel({required this.ride});

  final Map<String, dynamic> ride;

  String _value(dynamic value) => value?.toString().trim().isNotEmpty == true
      ? value.toString()
      : 'No registrado';

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: const Color(0xFF191A1B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF343638))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Tu conductor',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(_value(ride['driver_name']),
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700)),
          Text('Vehículo: ${_value(ride['driver_vehicle_type'])}'),
          Text('Marca: ${_value(ride['driver_vehicle_brand'])}'),
          Text('Color: ${_value(ride['driver_vehicle_color'])}'),
          Text('Placa: ${_value(ride['driver_vehicle_plate'])}'),
          const SizedBox(height: 12),
          Text('Código de encuentro: ${_value(ride['pickup_code'])}',
              style: const TextStyle(
                  color: Color(0xFFE8F044), fontWeight: FontWeight.w800)),
        ]),
      );
}

String _statusTitle(String status) {
  switch (status) {
    case 'accepted':
      return 'Conductor confirmado';
    case 'negotiating':
      return 'Buscando conductores';
    case 'driver_selected':
      return 'Conductor confirmado';
    case 'en_route':
      return 'Yendo a tu destino';
    case 'arrived':
      return 'Tu conductor llegó';
    case 'in_progress':
      return 'Viaje en curso';
    default:
      return 'Solicitud enviada';
  }
}

String _statusDescription(String status) {
  switch (status) {
    case 'accepted':
      return 'Comparte el código de encuentro con tu conductor.';
    case 'driver_selected':
      return 'Tu reserva fue confirmada.';
    case 'en_route':
      return 'Yendo a tu destino.';
    case 'arrived':
      return 'Encuéntralo en tu punto de partida.';
    case 'in_progress':
      return 'Disfruta el trayecto hasta tu destino.';
    case 'negotiating':
      return 'Estamos comparando ofertas cercanas para ti.';
    default:
      return 'Estamos buscando conductores cerca de ti.';
  }
}

double _statusProgress(String status) {
  const values = {
    'requested': .18,
    'negotiating': .35,
    'driver_selected': .55,
    'en_route': .72,
    'arrived': .84,
    'in_progress': .95,
  };
  return values[status] ?? .18;
}

String _vehicleLabel(String? vehicle) {
  const labels = {
    'economy': 'Detalles de Viaje',
    'moto': 'Detalles de Moto',
    'plus': 'Detalles de Viaje+',
    'comfort': 'Detalles de Comfort',
  };
  return labels[vehicle] ?? 'Detalles del viaje';
}

String _rideMessage(String status, Map<String, dynamic> ride) {
  final destination = ride['destination']?.toString() ?? 'tu destino';
  if (status == 'arrived') return 'Espera en el punto de partida';
  if (status == 'in_progress') return 'Viaje hacia $destination';
  if (status == 'driver_selected') {
    return 'Tu conductor se dirige a recogerte';
  }
  if (status == 'en_route') return 'Yendo a tu destino';
  return 'Espera mientras encontramos tu conductor';
}

class _VehiclePicker extends StatelessWidget {
  const _VehiclePicker({required this.selected, required this.onChanged});
  final String selected;
  final ValueChanged<String> onChanged;
  static const options = [
    ('economy', 'Viaje', Icons.directions_car),
    ('moto', 'Moto', Icons.two_wheeler),
    ('plus', 'Viaje+', Icons.directions_car_filled),
    ('comfort', 'Comfort', Icons.ac_unit)
  ];

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 88,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: options.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, index) {
            final option = options[index];
            final active = option.$1 == selected;
            return GestureDetector(
              onTap: () => onChanged(option.$1),
              child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 96,
                  padding: const EdgeInsets.fromLTRB(8, 9, 8, 8),
                  decoration: BoxDecoration(
                      color: active
                          ? const Color(0xFFE8F044)
                          : const Color(0xFF191A1B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: active
                              ? const Color(0xFFE8F044)
                              : const Color(0xFF3A3B3C))),
                  child: Column(children: [
                    Icon(option.$3,
                        color:
                            active ? const Color(0xFF171B1D) : Colors.white70,
                        size: 34),
                    const SizedBox(height: 4),
                    Text(option.$2,
                        style: TextStyle(
                            color: active
                                ? const Color(0xFF171B1D)
                                : Colors.white70,
                            fontWeight: FontWeight.w700))
                  ])),
            );
          },
        ),
      );
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({required this.title, required this.onTap});
  final String title;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 7),
          child: Row(children: [
            const Icon(Icons.location_on_outlined,
                color: Colors.white70, size: 29),
            const SizedBox(width: 17),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                ]))
          ])));
}

String _displayOrigin(String? origin) {
  final value = origin?.trim() ?? '';
  final coordinateStart = value.indexOf(' (');
  if (coordinateStart >= 0) return value.substring(0, coordinateStart);
  return value.isEmpty ? 'Ubicación actual' : value;
}

class _OriginRow extends StatelessWidget {
  const _OriginRow({required this.origin});
  final String origin;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 9),
      child: Row(children: [
        const Icon(Icons.my_location_outlined, color: Colors.white70, size: 29),
        const SizedBox(width: 17),
        Expanded(
            child: Text(origin,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis))
      ]));
}

class _PointsCard extends StatelessWidget {
  const _PointsCard({required this.points, required this.tier});
  final int points;
  final String tier;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
            color: const Color(0xFF191A1B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF2B2C2D))),
        child: Row(children: [
          const Icon(Icons.stars, color: Color(0xFFE8F044), size: 28),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('ProMaster pasajero',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                Text('$points PI · Nivel $tier',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800)),
              ])),
          const Text('COP 20 = 1 PI',
              style: TextStyle(color: Colors.white54, fontSize: 10)),
        ]),
      );
}

class _RecentRide extends StatelessWidget {
  const _RecentRide({required this.ride, required this.onSelectOffer});
  final Map<String, dynamic> ride;
  final void Function(int rideId, int offerId) onSelectOffer;

  @override
  Widget build(BuildContext context) {
    final offers =
        (ride['offers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final canSelect =
        ride['status'] == 'requested' || ride['status'] == 'negotiating';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: const Color(0xFF202122),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2D2E2F))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.route, color: Color(0xFFE8F044)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(
                  '${_displayOrigin(ride['origin']?.toString())} → ${ride['destination']}',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700))),
          Text('\$${ride['offer_amount']}',
              style: const TextStyle(
                  color: Color(0xFFE8F044), fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 4),
        Text(
            'Estado: ${ride['status']} · ${ride['distance_km']} km · ${ride['duration_minutes']} min',
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        if (offers.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('Ofertas privadas',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ...offers.map((offer) => Row(children: [
                Expanded(
                    child: Text(
                        '${offer['driver_name']} · ${offer['amount']} COP',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12))),
                if (canSelect && offer['status'] == 'pending')
                  TextButton(
                      onPressed: () =>
                          onSelectOffer(ride['id'] as int, offer['id'] as int),
                      child: const Text('Elegir')),
              ])),
        ],
      ]),
    );
  }
}

class _RouteSummary extends StatelessWidget {
  const _RouteSummary({required this.route, required this.fare});
  final Map<String, dynamic> route;
  final int fare;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
            color: const Color(0xFF202122),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF2D2E2F))),
        child: Row(children: [
          const Icon(Icons.route, color: Color(0xFFE8F044)),
          const SizedBox(width: 10),
          Expanded(
              child: Text(
                  '${route['distance_text'] ?? '${route['distance_km']} km'}  ·  ${route['duration_text'] ?? '${route['duration_minutes']} min'}',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700))),
          Text('\$${fare.toString()} COP',
              style: const TextStyle(
                  color: Color(0xFFE8F044), fontWeight: FontWeight.w800)),
        ]),
      );
}

class _NavigationCard extends StatelessWidget {
  const _NavigationCard(
      {required this.destination,
      required this.route,
      required this.nextStep,
      required this.condensed});
  final String destination;
  final Map<String, dynamic>? route;
  final Map<String, dynamic>? nextStep;
  final bool condensed;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding:
            EdgeInsets.symmetric(horizontal: 16, vertical: condensed ? 7 : 12),
        decoration: BoxDecoration(
            color: const Color(0xFF111213).withValues(alpha: .97),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF2D2E2F))),
        child: Row(children: [
          Icon(_maneuverIcon(nextStep?['maneuver']?.toString()),
              color: const Color(0xFFE8F044), size: condensed ? 20 : 24),
          SizedBox(width: condensed ? 8 : 12),
          Expanded(
              child: Text(destination,
                  maxLines: condensed ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: condensed ? 14 : 15,
                      fontWeight: FontWeight.w800))),
          if (route != null)
            Text(route!['duration_text']?.toString() ?? '',
                style: const TextStyle(
                    color: Color(0xFFE8F044), fontWeight: FontWeight.w800)),
        ]),
      );
}

IconData _maneuverIcon(String? maneuver) {
  if (maneuver?.contains('left') == true) return Icons.turn_left;
  if (maneuver?.contains('right') == true) return Icons.turn_right;
  if (maneuver?.contains('uturn') == true) return Icons.u_turn_left;
  if (maneuver?.contains('roundabout') == true) return Icons.roundabout_left;
  return Icons.navigation;
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Material(
      color: const Color(0xFF111213),
      shape: const CircleBorder(),
      child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF343638))),
              child: Icon(icon, color: Colors.white, size: 29))));
}
