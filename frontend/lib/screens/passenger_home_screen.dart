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
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadRides();
    _loadPassengerProfile();
    _startLocationTracking();
    _rideRefreshTimer =
        Timer.periodic(const Duration(seconds: 8), (_) => _loadRides());
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
      if (mounted) setState(() => _rides = rides);
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

  Future<void> _requestRide() async {
    if (_destination.text.trim().isEmpty) {
      setState(() => _message = 'Escribe un destino para continuar.');
      return;
    }
    var route = _route;
    var destinationLocation = _destinationLocation;
    if (destinationLocation == null || route == null) {
      destinationLocation = _manualDestinationCoordinates(_destination.text);
      route = _manualRoute(destinationLocation);
      if (mounted)
        setState(() {
          _destinationLocation = destinationLocation;
          _route = route;
        });
    }
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final fare = _decreeFareFor(_destination.text, _vehicle);
      final distanceKm = (route['distance_km'] as num?)?.toDouble();
      final durationMinutes = (route['duration_minutes'] as num?)?.round();
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
          originLat: _location.latitude,
          originLng: _location.longitude,
          destinationLat: destinationLocation.latitude,
          destinationLng: destinationLocation.longitude,
          distanceKm: distanceKm,
          durationMinutes: durationMinutes);
      _destination.clear();
      _selectedDestination = null;
      _destinationLocation = null;
      _route = null;
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

  LatLng _manualDestinationCoordinates(String destination) {
    final seed =
        destination.trim().codeUnits.fold<int>(0, (sum, value) => sum + value);
    final latitudeOffset = 0.008 + (seed % 12) / 10000;
    final longitudeOffset = 0.008 + (seed % 9) / 10000;
    return LatLng(_location.latitude + latitudeOffset,
        _location.longitude - longitudeOffset);
  }

  Map<String, dynamic> _manualRoute(LatLng destination) {
    final distance = Geolocator.distanceBetween(_location.latitude,
            _location.longitude, destination.latitude, destination.longitude) /
        1000;
    return {
      'distance_km': double.parse(distance.toStringAsFixed(2)),
      'duration_minutes': (distance * 4.5).ceil().clamp(5, 90),
      'distance_text': '${distance.toStringAsFixed(1)} km',
      'duration_text': '${(distance * 4.5).ceil().clamp(5, 90)} min',
      'route_points': [
        {'lat': _location.latitude, 'lng': _location.longitude},
        {'lat': destination.latitude, 'lng': destination.longitude},
      ],
      'steps': const [],
      'manual': true,
    };
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
        'AMBERES',
        'ESPERANZA',
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
        'PONTEZUELA',
        'LAGUNA CLUB TERRANOVA',
        'COLEGIO GEORGE WASHINGTON',
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
      final route = await widget.api.estimateRoute(
          originLat: _location.latitude,
          originLng: _location.longitude,
          destinationLat: coordinates.latitude,
          destinationLng: coordinates.longitude);
      if (mounted) {
        setState(() {
          _destinationLocation = coordinates;
          _route = route;
        });
        await _fitRoute(coordinates, route);
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _message = error.message);
    }
  }

  void _onDestinationChanged(String value) {
    if (_selectedDestination != null && value != _selectedDestination) {
      setState(() {
        _selectedDestination = null;
        _destinationLocation = null;
        _route = null;
        _message = null;
      });
    }
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
        _origin.text =
            'Ubicación actual (${next.latitude.toStringAsFixed(5)}, ${next.longitude.toStringAsFixed(5)})';
      });
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
                        infoWindow: InfoWindow(
                            title: _destination.text,
                            snippet: 'Destino seleccionado')),
                },
                polylines: _routeLines,
                style: _googleMapStyle,
              ),
            ),
            Positioned(
                top: 16,
                left: 18,
                child: _RoundAction(
                    icon: Icons.menu,
                    onPressed: () => showMenu<String>(
                          context: context,
                          position: const RelativeRect.fromLTRB(16, 76, 0, 0),
                          items: [
                            PopupMenuItem(
                                value: 'points',
                                child: const ListTile(
                                    leading: Icon(Icons.stars_outlined),
                                    title: Text('Puntos'))),
                            PopupMenuItem(
                                value: 'bonus',
                                child: const ListTile(
                                    leading: Icon(Icons.card_giftcard_outlined),
                                    title: Text('Bonificaciones'))),
                            PopupMenuItem(
                                value: 'history',
                                child: const ListTile(
                                    leading: Icon(Icons.history),
                                    title: Text('Historial'))),
                            PopupMenuItem(
                                value: 'support',
                                child: const ListTile(
                                    leading: Icon(Icons.support_agent_outlined),
                                    title: Text('Soporte'))),
                            PopupMenuItem(
                                value: 'profile',
                                child: const ListTile(
                                    leading: Icon(Icons.person_outline),
                                    title: Text('Perfil'))),
                          ],
                        ).then((value) {
                          if (!context.mounted || value == null) return;
                          final screen = value == 'points'
                              ? PointsScreen(
                                  role: 'passenger',
                                  points: _points,
                                  tier: _tier)
                              : value == 'bonus'
                                  ? BonusScreen(
                                      role: 'passenger',
                                      points: _points,
                                      tier: _tier)
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
                                          widget.user['name']?.toString() ??
                                              'Usuario IR',
                                          _points,
                                          _tier));
                          Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => screen));
                        }))),
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
                  if (_destination.text.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _NavigationCard(
                        destination: _destination.text,
                        route: _route,
                        nextStep: _nextStep(_route)),
                  ],
                ],
              ),
            ),
            DraggableScrollableSheet(
              initialChildSize: 0.43,
              minChildSize: 0.36,
              maxChildSize: 0.78,
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
                onVehicleChanged: (value) => setState(() => _vehicle = value),
                onSuggestionSelected: (place) => _selectDestination(
                    place['description'].toString(),
                    place['place_id']?.toString()),
                onNearbySelected: (place) => _selectDestination(
                    place['name'].toString(), place['place_id']?.toString()),
                onQueryChanged: _onDestinationChanged,
                fare: _route == null
                    ? null
                    : _decreeFareFor(_destination.text, _vehicle),
                onRequestRide: _requestRide,
                onSelectOffer: _selectOffer,
              ),
            ),
          ]),
        ),
      );
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
  {"elementType":"geometry","stylers":[{"color":"#18243b"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#a9b6c9"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#18243b"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#344968"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#71809a"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0e1d36"}]}
]''';

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
      required this.fare,
      required this.onVehicleChanged,
      required this.onSuggestionSelected,
      required this.onNearbySelected,
      required this.onQueryChanged,
      required this.onRequestRide,
      required this.onSelectOffer});
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
  final int? fare;
  final ValueChanged<String> onVehicleChanged;
  final ValueChanged<Map<String, dynamic>> onSuggestionSelected;
  final ValueChanged<Map<String, dynamic>> onNearbySelected;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onRequestRide;
  final void Function(int rideId, int offerId) onSelectOffer;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
            color: Color(0xFF1B1C1D),
            borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 30),
            children: [
              Center(
                  child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                          color: Colors.white38,
                          borderRadius: BorderRadius.circular(5)))),
              const SizedBox(height: 14),
              _VehiclePicker(selected: vehicle, onChanged: onVehicleChanged),
              const SizedBox(height: 14),
              _PointsCard(points: points, tier: tier),
              const SizedBox(height: 16),
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
                    prefixIcon:
                        const Icon(Icons.search, color: Colors.white, size: 31),
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
              if (nearbyPlaces.isNotEmpty) ...[
                const SizedBox(height: 18),
                const Text('Lugares cercanos',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
                ...nearbyPlaces.take(5).map((place) => _PlaceRow(
                    title: place['name'].toString(),
                    detail: _formatDistance(place['distance_meters']),
                    onTap: () => onNearbySelected(place))),
              ],
            ]),
      );
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
        height: 92,
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
                  width: 108,
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                  decoration: BoxDecoration(
                      color: active
                          ? const Color(0xFFE8F044)
                          : const Color(0xFF1B1C1D),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: active
                              ? const Color(0xFFE8F044)
                              : Colors.transparent)),
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
  const _PlaceRow({required this.title, required this.onTap, this.detail});
  final String title;
  final VoidCallback onTap;
  final String? detail;
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
                  if (detail != null)
                    Text(detail!,
                        style: const TextStyle(
                            color: Color(0xFFE8F044),
                            fontSize: 12,
                            fontWeight: FontWeight.w700))
                ]))
          ])));
}

String _formatDistance(dynamic meters) {
  final value = (meters as num?)?.toDouble();
  if (value == null) return '';
  return value < 1000
      ? '${value.round()} m'
      : '${(value / 1000).toStringAsFixed(1)} km';
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
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: const Color(0xFF303031),
            borderRadius: BorderRadius.circular(14)),
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
          const Text('PI = tarifa válida / COP 20',
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
          color: const Color(0xFF303031),
          borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.route, color: Color(0xFFE8F044)),
          const SizedBox(width: 8),
          Expanded(
              child: Text('${ride['origin']} → ${ride['destination']}',
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
            color: const Color(0xFF303031),
            borderRadius: BorderRadius.circular(14)),
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
      {required this.destination, required this.route, required this.nextStep});
  final String destination;
  final Map<String, dynamic>? route;
  final Map<String, dynamic>? nextStep;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
            color: const Color(0xFF171B1D).withValues(alpha: .95),
            borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          Icon(_maneuverIcon(nextStep?['maneuver']?.toString()),
              color: const Color(0xFFE8F044), size: 24),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(nextStep?['instruction']?.toString() ?? destination,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
                if (nextStep != null)
                  Text('${nextStep!['distance_text']} · hacia $destination',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12)),
              ])),
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
      color: const Color(0xFF171B1D),
      shape: const CircleBorder(),
      child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
              width: 58,
              height: 58,
              child: Icon(icon, color: Colors.white, size: 29))));
}
