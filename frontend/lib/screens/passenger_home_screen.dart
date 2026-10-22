import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'dart:async';

import '../services/api_service.dart';
import '../ui/ir_brand.dart';
import '../ui/ir_theme.dart';
import '../ui/ir_motion.dart';
import '../ui/ir_auth_layout.dart';
import '../ui/ir_format.dart';
import '../ui/ir_map_layout.dart';
import '../ui/ir_map_route.dart';
import '../ui/ir_map_symbols.dart';
import 'welcome_screen.dart';
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
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _refreshingRides = false;
  int _searchVersion = 0;
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
  double _rating = 0;
  int _ratingCount = 0;
  int _totalRides = 0;
  LatLng _location = const LatLng(10.391, -75.4794);
  LatLng? _destinationLocation;
  String? _selectedDestination;
  Map<String, dynamic>? _route;
  Map<String, dynamic>? _activeRideRoute;
  String? _activeRideRouteKey;
  StreamSubscription<Position>? _locationSubscription;
  Timer? _searchDebounce;
  Timer? _rideRefreshTimer;
  GoogleMapController? _mapController;
  IrMapSymbols? _mapSymbols;
  final DraggableScrollableController _rideSheetController =
      DraggableScrollableController();
  bool _hasInitialLocation = false;
  bool _loading = false;
  bool _menuExpanded = false;
  bool _navigationCardCondensed = false;
  bool _sheetAtTop = false;
  bool _keyboardOpen = false;
  double? _restingSheetSize;
  double? _mapSheetExtent;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadRides();
    _loadPassengerProfile();
    _loadMapSymbols();
    _startLocationTracking();
    _rideRefreshTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _loadRides());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final layout = IrMapLayout.of(context);
    final previousRestingSize = _restingSheetSize;
    _restingSheetSize = layout.passengerResting;
    final open = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (open != _keyboardOpen ||
        (previousRestingSize != null &&
            previousRestingSize != _restingSheetSize)) {
      _keyboardOpen = open;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _rideSheetController.isAttached) {
          _rideSheetController.jumpTo(open ? .90 : _restingSheetSize!);
        }
      });
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _rideRefreshTimer?.cancel();
    _locationSubscription?.cancel();
    _mapController?.dispose();
    _rideSheetController.dispose();
    _origin.dispose();
    _destination.dispose();
    super.dispose();
  }

  Future<void> _loadRides() async {
    if (_refreshingRides) return;
    _refreshingRides = true;
    try {
      final rides = await widget.api.getRides();
      if (mounted) {
        setState(() => _rides = rides
            .where((ride) =>
                !_closedReviewRideIds.contains(_asInt(ride['id'])) &&
                !_dismissedRatedRideIds.contains(_asInt(ride['id'])))
            .toList());
      }
      await _refreshActiveRideRoute();
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'No se pudieron actualizar tus viajes. Revisa tu conexión.');
      }
    } finally {
      _refreshingRides = false;
    }
  }

  Future<void> _loadMapSymbols() async {
    try {
      final symbols = await IrMapSymbols.load();
      if (mounted) setState(() => _mapSymbols = symbols);
    } catch (error) {
      debugPrint('No se pudieron preparar los iconos del mapa: $error');
    }
  }

  Future<void> _refreshActiveRideRoute() async {
    final ride = _activeRide;
    if (ride == null) {
      _activeRideRouteKey = null;
      if (mounted && _activeRideRoute != null) {
        setState(() => _activeRideRoute = null);
      }
      return;
    }
    final status = ride['status']?.toString();
    final pickup = {
      'accepted',
      'driver_selected',
      'en_route',
      'arrived',
    }.contains(status);
    final origin = pickup
        ? _ridePoint(ride, 'driver_lat', 'driver_lng')
        : (_ridePoint(ride, 'passenger_lat', 'passenger_lng') ?? _location);
    final destination = pickup
        ? (_ridePoint(ride, 'origin_lat', 'origin_lng') ??
            _ridePoint(ride, 'passenger_lat', 'passenger_lng'))
        : _ridePoint(ride, 'destination_lat', 'destination_lng');
    if (origin == null || destination == null) return;
    final key =
        '${ride['id']}:$status:${origin.latitude.toStringAsFixed(4)}:${origin.longitude.toStringAsFixed(4)}:${destination.latitude.toStringAsFixed(4)}:${destination.longitude.toStringAsFixed(4)}';
    if (key == _activeRideRouteKey) return;
    _activeRideRouteKey = key;
    try {
      final route = await widget.api.estimateRoute(
          originLat: origin.latitude,
          originLng: origin.longitude,
          destinationLat: destination.latitude,
          destinationLng: destination.longitude);
      if (mounted) setState(() => _activeRideRoute = route);
    } catch (_) {}
  }

  Future<void> _loadPassengerProfile() async {
    try {
      final profile = await widget.api.getPassengerMe();
      if (mounted) {
        setState(() {
          _points = profile['points'] ?? 0;
          _tier = profile['tier'] ?? 'Inicial';
          _rating = (profile['rating'] as num?)?.toDouble() ?? 0;
          _ratingCount = profile['rating_count'] ?? 0;
          _totalRides = profile['total_rides'] ?? 0;
        });
      }
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
          !_dismissedRatedRideIds.contains(rideId)) {
        return ride;
      }
    }
    return null;
  }

  Future<void> _selectOffer(int rideId, int offerId) async {
    try {
      await widget.api.selectRideOffer(rideId, offerId);
      await _loadRides();
      if (mounted) {
        setState(() =>
            _message = 'Conductor seleccionado. La reserva fue confirmada.');
      }
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
    try {
      await widget.api.rateRide(rideId, rating);
      _closeRideReview(rideId);
      _dismissedRatedRideIds.add(rideId);
      await _loadRides();
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _message = error.message);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
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
    });
    _clearDestination();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _rideSheetController.isAttached) {
        _rideSheetController.jumpTo(.43);
      }
    });
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
        if (mounted) {
          setState(() => _message =
              'La ruta no tiene datos suficientes para solicitar el viaje.');
        }
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
      if (mounted) {
        setState(() => _message = 'Solicitud enviada. Buscando tu conductor.');
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'No se pudo enviar la solicitud: $error');
      }
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
    final version = ++_searchVersion;
    if (query.trim().length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final suggestions = await widget.api.searchPlaces(query.trim());
        if (mounted && version == _searchVersion) {
          setState(() => _suggestions = suggestions);
        }
      } catch (_) {
        if (mounted && version == _searchVersion) {
          setState(() =>
              _message = 'No se pudo buscar el destino. Inténtalo de nuevo.');
        }
      }
    });
  }

  Future<void> _startLocationTracking() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          setState(() => _message = 'Activa la ubicación del dispositivo.');
        }
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _message =
              'Permite la ubicación para mantener tu posición activa.');
        }
        return;
      }
      await _locationSubscription?.cancel();
      final position = await Geolocator.getCurrentPosition();
      await _updateLocation(position, loadNearby: true);
      if (!_hasInitialLocation && _mapController != null) {
        if (!mounted) return;
        setState(() => _hasInitialLocation = true);
        await _animatePassengerCamera(
            _cameraForPoints([_location], maxZoom: 16));
      }
      _locationSubscription = Geolocator.getPositionStream(
              locationSettings: const LocationSettings(
                  accuracy: LocationAccuracy.high, distanceFilter: 10))
          .listen((position) => _updateLocation(position));
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'No se pudo obtener tu ubicación actual.');
      }
    }
  }

  Future<void> _recenterOnUser() async {
    await _startLocationTracking();
    if (mounted) {
      await _animatePassengerCamera(_cameraForPoints([_location], maxZoom: 16));
    }
  }

  Future<void> _animatePassengerCamera(CameraUpdate update) async {
    if (!mounted || _mapController == null) return;
    try {
      if (MediaQuery.disableAnimationsOf(context)) {
        await _mapController!.moveCamera(update);
      } else {
        await _mapController!.animateCamera(update);
      }
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo ajustar el mapa. Inténtalo de nuevo.')));
      }
    }
  }

  Future<void> _updateLocation(Position position,
      {bool loadNearby = false}) async {
    final next = LatLng(position.latitude, position.longitude);
    if (mounted) {
      setState(() {
        _location = next;
        _origin.text = 'Ubicación actual';
      });
    }
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
    await _startLocationTracking();
    if (!mounted) return;
    if (!_hasInitialLocation) {
      await _animatePassengerCamera(_cameraForPoints([_location], maxZoom: 15));
    }
  }

  void _openMenuSection(String value) {
    _scaffoldKey.currentState?.closeDrawer();
    if (value == 'logout') {
      widget.api.token = null;
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          (_) => false);
      return;
    }
    final screen = value == 'points'
        ? PointsScreen(role: 'passenger', points: _points, tier: _tier)
        : value == 'bonus'
            ? BonusScreen(role: 'passenger', points: _points, tier: _tier)
            : RoleSectionScreen(
                title: value == 'history'
                    ? 'Historial de viajes'
                    : value == 'support'
                        ? 'Soporte IR'
                        : value == 'settings'
                            ? 'Configuración'
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
    await _animatePassengerCamera(_cameraForPoints(routePoints));
  }

  CameraUpdate _cameraForPoints(Iterable<LatLng> points,
          {double maxZoom = 18}) =>
      IrMapRoute.overview(points,
          viewport: IrMapRoute.viewport(context),
          obscured: IrMapRoute.padding(context,
              _mapSheetExtent ?? IrMapLayout.of(context).passengerResting),
          maxZoom: maxZoom);

  List<LatLng> get _overviewPoints {
    final route =
        IrMapRoute.points(_activeRide != null ? _activeRideRoute : _route);
    if (route.length >= 2) return route;
    return _passengerMarkers.map((marker) => marker.position).toList();
  }

  Future<void> _showRouteOverview() async {
    final points = _overviewPoints;
    if (points.length < 2) return;
    FocusScope.of(context).unfocus();
    final minimum = IrMapLayout.of(context).passengerMinimum;
    if (_rideSheetController.isAttached) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _rideSheetController.jumpTo(minimum);
      } else {
        await _rideSheetController.animateTo(minimum,
            duration: IrMotion.transition, curve: Curves.easeOutCubic);
      }
    }
    if (!mounted) return;
    setState(() => _mapSheetExtent = minimum);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) await _animatePassengerCamera(_cameraForPoints(points));
  }

  Set<Polyline> get _routeLines {
    final activeRide = _activeRide;
    if (activeRide != null) {
      final activePoints = _routePoints(
          _activeRideRoute, _destinationLocation ?? const LatLng(0, 0));
      if (activePoints.length >= 2) {
        return {
          Polyline(
            polylineId: const PolylineId('active-ride-route'),
            points: activePoints,
            color: context.irColors.accent,
            width: 7,
            jointType: JointType.round,
          ),
        };
      }
      return {};
    }
    final points = _destinationLocation == null
        ? <LatLng>[]
        : _routePoints(_route, _destinationLocation!);
    if (points.length < 2) return {};
    return {
      Polyline(
        polylineId: const PolylineId('ride-route'),
        points: points,
        color: context.irColors.accent,
        width: 6,
        jointType: JointType.round,
      ),
    };
  }

  LatLng? _ridePoint(
      Map<String, dynamic> ride, String latitudeKey, String longitudeKey) {
    return IrMapRoute.point(ride[latitudeKey], ride[longitudeKey]);
  }

  IrMapSymbol _driverSymbol(Map<String, dynamic> ride) {
    final vehicle = ride['driver_vehicle_type']?.toString().toLowerCase() ?? '';
    if (vehicle.contains('moto')) {
      return IrMapSymbol.motorcycle;
    }
    return IrMapSymbol.car;
  }

  String _driverMarkerTitle(Map<String, dynamic> ride) {
    final vehicle = ride['driver_vehicle_type']?.toString().toLowerCase() ?? '';
    return vehicle.contains('moto')
        ? 'Moto de tu conductor'
        : 'Carro de tu conductor';
  }

  List<LatLng> _routePoints(Map<String, dynamic>? route, LatLng destination) {
    return IrMapRoute.points(route);
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
          45) {
        return step;
      }
    }
    return steps.isEmpty ? null : steps.last;
  }

  Set<Marker> get _passengerMarkers {
    final symbols = _mapSymbols;
    if (symbols == null) return {};
    final ride = _activeRide;
    final passenger = ride == null
        ? (_hasInitialLocation ? _location : null)
        : (_ridePoint(ride, 'passenger_lat', 'passenger_lng') ??
            (_hasInitialLocation ? _location : null));
    final pickup = ride == null
        ? (IrMapRoute.points(_route).firstOrNull)
        : (_ridePoint(ride, 'origin_lat', 'origin_lng') ?? passenger);
    final destination = ride == null
        ? _destinationLocation
        : _ridePoint(ride, 'destination_lat', 'destination_lng');
    final driver =
        ride == null ? null : _ridePoint(ride, 'driver_lat', 'driver_lng');
    final markers = <Marker>{};
    if (passenger != null) {
      markers.add(Marker(
        markerId: const MarkerId('current-location'),
        position: passenger,
        icon: symbols[IrMapSymbol.passenger],
        anchor: const Offset(.5, .5),
        zIndexInt: 4,
        infoWindow:
            const InfoWindow(title: 'Tú', snippet: 'Ubicación del pasajero'),
      ));
    }
    if (pickup != null &&
        (passenger == null ||
            Geolocator.distanceBetween(pickup.latitude, pickup.longitude,
                    passenger.latitude, passenger.longitude) >
                12)) {
      markers.add(Marker(
        markerId: const MarkerId('pickup-location'),
        position: pickup,
        icon: symbols[IrMapSymbol.pickup],
        anchor: const Offset(.5, .5),
        zIndexInt: 2,
        infoWindow: const InfoWindow(title: 'Punto de recogida'),
      ));
    }
    if (destination != null) {
      markers.add(Marker(
        markerId: const MarkerId('destination'),
        position: destination,
        icon: symbols[IrMapSymbol.destination],
        anchor: const Offset(.5, .5),
        zIndexInt: 2,
        infoWindow: InfoWindow(
            title: ride?['destination']?.toString() ?? _destination.text,
            snippet: 'Destino del viaje'),
      ));
    }
    if (driver != null) {
      markers.add(Marker(
        markerId: const MarkerId('driver-location'),
        position: driver,
        icon: symbols[_driverSymbol(ride!)],
        anchor: const Offset(.5, .5),
        zIndexInt: 5,
        infoWindow: InfoWindow(
            title: _driverMarkerTitle(ride),
            snippet: 'Ubicación del conductor'),
      ));
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final layout = IrMapLayout.of(context);
    return Scaffold(
      key: _scaffoldKey,
      onDrawerChanged: (open) => setState(() => _menuExpanded = open),
      drawer: Drawer(
          width: MediaQuery.sizeOf(context).width.clamp(0, 340).toDouble(),
          child: PointerInterceptor(
              child: _PassengerSideBar(
                  user: widget.user,
                  points: _points,
                  tier: _tier,
                  rating: _rating,
                  ratingCount: _ratingCount,
                  totalRides: _totalRides,
                  onClose: () => _scaffoldKey.currentState?.closeDrawer(),
                  onSectionSelected: _openMenuSection))),
      backgroundColor: context.irColors.surface,
      body: SafeArea(
        bottom: false,
        child: Stack(children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: const CameraPosition(
                  target: LatLng(10.405, -75.505), zoom: 14.5),
              onMapCreated: _onMapCreated,
              myLocationButtonEnabled: false,
              myLocationEnabled: false,
              zoomControlsEnabled: false,
              scrollGesturesEnabled: true,
              webGestureHandling: WebGestureHandling.greedy,
              zoomGesturesEnabled: true,
              rotateGesturesEnabled: true,
              tiltGesturesEnabled: true,
              markers: _passengerMarkers,
              polylines: _routeLines,
              style: context.irColors.light ? null : _googleMapStyle,
            ),
          ),
          Positioned(
              top: 18,
              right: 18,
              child: PointerInterceptor(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_overviewPoints.length >= 2) ...[
                  IrMapAction(
                      icon: Icons.route_outlined,
                      label: 'Ver recorrido completo',
                      onPressed: _showRouteOverview),
                  const SizedBox(width: 8),
                ],
                IrMapAction(
                    icon: Icons.my_location,
                    label: 'Centrar en mi ubicación',
                    onPressed: _recenterOnUser),
              ]))),
          Positioned(
            top: 84,
            left: 20,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_destination.text.isNotEmpty &&
                    !_menuExpanded &&
                    !_navigationCardCondensed &&
                    MediaQuery.viewInsetsOf(context).bottom == 0 &&
                    !{
                      'accepted',
                      'driver_selected',
                      'en_route',
                      'arrived',
                      'in_progress',
                    }.contains(_activeRide?['status'])) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(maxWidth: layout.sheetMaxWidth),
                      child: PointerInterceptor(
                        child: _NavigationCard(
                            destination: _destination.text,
                            route: _route,
                            nextStep: _nextStep(_route),
                            condensed: _navigationCardCondensed),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Positioned.fill(
            child: NotificationListener<DraggableScrollableNotification>(
              onNotification: (notification) {
                _mapSheetExtent = notification.extent;
                final condensed = notification.extent >= 0.52;
                final atTop = notification.extent >= .88;
                if ((condensed != _navigationCardCondensed ||
                        atTop != _sheetAtTop) &&
                    mounted) {
                  setState(() {
                    _navigationCardCondensed = condensed;
                    _sheetAtTop = atTop;
                  });
                }
                return false;
              },
              child: Align(
                alignment: Alignment.bottomCenter,
                child: DraggableScrollableSheet(
                  controller: _rideSheetController,
                  expand: false,
                  initialChildSize: layout.passengerResting,
                  minChildSize: layout.passengerMinimum,
                  maxChildSize: 1.0,
                  snapSizes: layout.passengerSnapSizes,
                  snap: true,
                  builder: (context, controller) => Align(
                      alignment: Alignment.bottomCenter,
                      child: ConstrainedBox(
                          constraints:
                              BoxConstraints(maxWidth: layout.sheetMaxWidth),
                          child: PointerInterceptor(
                              child: _RideSheet(
                            reserveToolbar: _sheetAtTop,
                            layout: layout,
                            controller: controller,
                            sheetController: _rideSheetController,
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
                          )))),
                ),
              ),
            ),
          ),
          Positioned(
              top: 18,
              left: 18,
              child: PointerInterceptor(
                  child: IrMapAction(
                      icon: Icons.menu,
                      label: 'Abrir menú',
                      onPressed: () =>
                          _scaffoldKey.currentState?.openDrawer()))),
        ]),
      ),
    );
  }
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
    if (rides.isEmpty) {
      return const [
        SectionItem(
            icon: Icons.inbox_outlined,
            title: 'Sin viajes todavía',
            description:
                'Tus viajes aparecerán aquí cuando completes una solicitud.')
      ];
    }
    return rides
        .map((ride) => SectionItem(
            icon: Icons.route,
            title: '${ride['origin']} → ${ride['destination']}',
            description:
                'Estado: ${irRideStatus(ride['status']?.toString())} · Tarifa: COP ${ride['final_fare'] == 0 ? ride['offer_amount'] : ride['final_fare']}'))
        .toList();
  }
  if (section == 'support') {
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
  }
  if (section == 'settings') {
    return const [
      SectionItem(
          icon: Icons.settings_outlined,
          title: 'Preferencias de la cuenta',
          description: 'Administra tus preferencias como pasajero.'),
      SectionItem(
          icon: Icons.notifications_none_outlined,
          title: 'Notificaciones',
          description: 'Configura los avisos de tus viajes.'),
    ];
  }
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
      {required this.user,
      required this.points,
      required this.tier,
      required this.rating,
      required this.ratingCount,
      required this.totalRides,
      required this.onClose,
      required this.onSectionSelected});
  final Map<String, dynamic> user;
  final int points;
  final String tier;
  final double rating;
  final int ratingCount;
  final int totalRides;
  final VoidCallback onClose;
  final ValueChanged<String> onSectionSelected;

  static const _items = [
    ('points', 'Puntos', Icons.stars_outlined),
    ('bonus', 'Bonificaciones', Icons.card_giftcard_outlined),
    ('history', 'Historial', Icons.history),
    ('support', 'Soporte', Icons.support_agent_outlined),
    ('profile', 'Perfil', Icons.person_outline),
    ('settings', 'Configuración', Icons.settings_outlined),
    ('logout', 'Cerrar sesión', Icons.logout),
  ];

  @override
  Widget build(BuildContext context) => Material(
        color: context.irColors.surface,
        elevation: 0,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              Row(children: [
                const Expanded(child: IrBrandLogo(size: 42)),
                IconButton(
                    tooltip: 'Cerrar menú',
                    onPressed: onClose,
                    icon: Icon(Icons.close, color: context.irColors.muted)),
              ]),
              const SizedBox(height: 8),
              CircleAvatar(
                  radius: 28,
                  backgroundColor: IrPalette.accent,
                  child:
                      Icon(Icons.person, color: Color(0xFF171B1D), size: 30)),
              const SizedBox(height: 10),
              Text(user['name']?.toString() ?? 'Usuario IR',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: context.irColors.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Nivel $tier · $points PI',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: context.irColors.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 4,
                children: [
                  ...List.generate(
                      5,
                      (index) => Icon(
                          index < rating.round()
                              ? Icons.star
                              : Icons.star_border,
                          color: context.irColors.accent,
                          size: 20)),
                  const SizedBox(width: 8),
                  Text(
                      ratingCount == 0
                          ? 'Sin calificaciones'
                          : '${rating.toStringAsFixed(2)} ($ratingCount)',
                      style: TextStyle(
                          color: context.irColors.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 3),
              Text('$totalRides viajes realizados',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: context.irColors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              Divider(color: context.irColors.border),
              const SizedBox(height: 8),
              ..._items.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      minVerticalPadding: 8,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      leading: Icon(item.$3,
                          color: context.irColors.accent, size: 24),
                      title: Text(item.$2,
                          style: TextStyle(
                              color: context.irColors.text,
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
      {this.reserveToolbar = false,
      required this.layout,
      required this.controller,
      required this.sheetController,
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
  final bool reserveToolbar;
  final IrMapLayout layout;
  final DraggableScrollableController sheetController;
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
        decoration: BoxDecoration(
            color: context.irColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
            border: Border(
                top: BorderSide(color: context.irColors.border, width: 1))),
        child: ListView(
            controller: controller,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
                layout.horizontalPadding,
                reserveToolbar ? 76 : 10,
                layout.horizontalPadding,
                24 + MediaQuery.viewPaddingOf(context).bottom),
            children: [
              _RideSheetHandle(controller: sheetController),
              if (activeRide != null && message != null) ...[
                IrInlineMessage(message: message!),
                const SizedBox(height: 12)
              ],
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
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 12),
                  child: Text('Elige cómo viajar',
                      style: TextStyle(
                          color: context.irColors.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.5)),
                ),
                _VehiclePicker(
                    selected: vehicle,
                    onChanged: onVehicleChanged,
                    useGrid: layout.showVehicleGrid),
                const SizedBox(height: 16),
                _PointsCard(points: points, tier: tier),
                const SizedBox(height: 14),
                TextField(
                  controller: destinationController,
                  textInputAction: TextInputAction.search,
                  style: TextStyle(
                      color: context.irColors.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                      hintText: '¿A dónde y por cuánto?',
                      hintStyle: TextStyle(
                          color: context.irColors.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w700),
                      prefixIcon: Icon(Icons.search,
                          color: context.irColors.text, size: 31),
                      suffixIcon: destinationController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Borrar destino',
                              onPressed: () {
                                destinationController.clear();
                                onQueryChanged('');
                              },
                              icon: Icon(Icons.close,
                                  color: context.irColors.muted)),
                      filled: true,
                      fillColor: context.irColors.input,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 18)),
                  onChanged: onQueryChanged,
                  onSubmitted: (_) {
                    if (!loading && route != null) onRequestRide();
                  },
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
                          style: TextStyle(color: context.irColors.accent))),
                if (destinationController.text.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  FilledButton(
                      onPressed:
                          loading || route == null ? null : onRequestRide,
                      style: FilledButton.styleFrom(
                          backgroundColor: IrPalette.accent,
                          foregroundColor: const Color(0xFF171B1D),
                          minimumSize: const Size.fromHeight(52)),
                      child: loading
                          ? const CircularProgressIndicator(
                              color: Color(0xFF171B1D))
                          : const Text('Elegir viaje',
                              style: TextStyle(fontWeight: FontWeight.w800))),
                ],
                if (destinationController.text.trim().isEmpty &&
                    nearbyPlaces.any((place) => place['place_id'] != null)) ...[
                  const SizedBox(height: 20),
                  Text('Lugares cercanos',
                      style: TextStyle(
                          color: context.irColors.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w700)),
                  ...nearbyPlaces
                      .where((place) => place['place_id'] != null)
                      .take(3)
                      .map((place) => _PlaceRow(
                          title: place['name']?.toString() ?? 'Destino cercano',
                          onTap: () => onNearbySelected(place))),
                ],
              ],
              if (rides.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text('Viajes recientes',
                    style: TextStyle(
                        color: context.irColors.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
                ...rides.take(3).map((ride) =>
                    _RecentRide(ride: ride, onSelectOffer: onSelectOffer)),
              ],
            ]),
      );
}

class _RideSheetHandle extends StatelessWidget {
  const _RideSheetHandle({required this.controller});
  final DraggableScrollableController controller;

  void _snapToNearest(BuildContext context) {
    if (!controller.isAttached) return;
    final layout = IrMapLayout.of(context);
    final size = controller.size;
    final collapsedMidpoint =
        (layout.passengerMinimum + layout.passengerResting) / 2;
    final expandedMidpoint = (layout.passengerResting + .90) / 2;
    final target = size < collapsedMidpoint
        ? layout.passengerMinimum
        : size < expandedMidpoint
            ? layout.passengerResting
            : size < .95
                ? .90
                : 1.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.jumpTo(target);
      return;
    }
    controller.animateTo(target,
        duration: IrMotion.duration(context, const Duration(milliseconds: 180)),
        curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) {
          if (!controller.isAttached) return;
          final height = MediaQuery.sizeOf(context).height;
          final nextSize =
              (controller.size - (details.primaryDelta ?? 0) / height)
                  .clamp(IrMapLayout.of(context).passengerMinimum, 1.0)
                  .toDouble();
          controller.jumpTo(nextSize);
        },
        onVerticalDragEnd: (_) => _snapToNearest(context),
        child: SizedBox(
          height: 28,
          child: Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                  color: context.irColors.border,
                  borderRadius: BorderRadius.circular(5)),
            ),
          ),
        ),
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSearchAnimation();
  }

  void _syncSearchAnimation() {
    final status = widget.ride['status']?.toString();
    final searching = status == 'searching' ||
        status == 'requested' ||
        status == 'negotiating';
    if (searching &&
        !MediaQuery.disableAnimationsOf(context) &&
        !_searchAnimation.isAnimating) {
      _searchAnimation.repeat();
    } else if ((!searching || MediaQuery.disableAnimationsOf(context)) &&
        _searchAnimation.isAnimating) {
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
    final driverAssigned = {
      'accepted',
      'driver_selected',
      'en_route',
      'arrived',
      'in_progress',
    }.contains(status);
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
    final searching = status == 'searching' ||
        status == 'requested' ||
        status == 'negotiating';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
        decoration: BoxDecoration(
            color: context.irColors.raised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.irColors.border)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.navigation_outlined,
              color: context.irColors.accent, size: 28),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(_statusTitle(status),
                    style: TextStyle(
                        color: context.irColors.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                Text(_statusDescription(status),
                    style: TextStyle(
                        color: context.irColors.muted,
                        fontSize: 15,
                        height: 1.25)),
              ])),
        ]),
      ),
      const SizedBox(height: 16),
      ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: searching
              ? AnimatedBuilder(
                  animation: _searchAnimation,
                  builder: (context, child) => LinearProgressIndicator(
                      value: _searchAnimation.value,
                      minHeight: 5,
                      backgroundColor: context.irColors.border,
                      color: context.irColors.accent))
              : LinearProgressIndicator(
                  value: _statusProgress(status),
                  minHeight: 5,
                  backgroundColor: context.irColors.border,
                  color: context.irColors.accent)),
      const SizedBox(height: 16),
      if (ride['pickup_code']?.toString().trim().isNotEmpty == true) ...[
        _PickupCodeCard(code: ride['pickup_code'].toString()),
        const SizedBox(height: 12),
      ],
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: context.irColors.raised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.irColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_vehicleLabel(ride['vehicle_type']?.toString()),
              style: TextStyle(color: context.irColors.muted, fontSize: 13)),
          const SizedBox(height: 6),
          Text(_rideMessage(status, ride),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: context.irColors.text,
                  fontSize: 20,
                  height: 1.15,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          Row(children: [
            Icon(Icons.my_location, color: context.irColors.accent, size: 20),
            const SizedBox(width: 9),
            Expanded(
                child: Text(_displayOrigin(ride['origin']?.toString()),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.irColors.muted))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.location_on, color: context.irColors.accent, size: 20),
            const SizedBox(width: 9),
            Expanded(
                child: Text(ride['destination']?.toString() ?? 'Destino',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: context.irColors.text,
                        fontWeight: FontWeight.w600))),
          ]),
          if (ride['driver_lat'] != null && ride['driver_lng'] != null) ...[
            const SizedBox(height: 12),
            _LiveDistanceRow(
              label: 'Distancia al conductor',
              distanceKm: ride['live_distance_km'],
            ),
          ],
          const SizedBox(height: 14),
          Wrap(spacing: 12, runSpacing: 6, children: [
            Text(
                'COP ${ride['final_fare'] == 0 ? ride['offer_amount'] : ride['final_fare']}',
                style: TextStyle(
                    color: context.irColors.accent,
                    fontWeight: FontWeight.w800)),
            const SizedBox(width: 12),
            Text('${ride['distance_km']} km · ${ride['duration_minutes']} min',
                style: TextStyle(color: context.irColors.muted)),
          ]),
        ]),
      ),
      if (driverAssigned) ...[
        const SizedBox(height: 12),
        _DriverInfoPanel(ride: ride),
      ],
      if (offers.isNotEmpty) ...[
        const SizedBox(height: 18),
        Text('Ofertas de conductores',
            style: TextStyle(
                color: context.irColors.text,
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
        backgroundColor: context.irColors.surface,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        useSafeArea: true,
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
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              22, 18, 22, 20 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                    color: context.irColors.border,
                    borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 20),
            Text('¿Quieres cancelar el viaje?',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: context.irColors.text,
                    fontSize: 24,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Align(
                alignment: Alignment.centerLeft,
                child: Text('¿Por qué quieres cancelar? Opcional',
                    style: TextStyle(
                        color: context.irColors.muted, fontSize: 15))),
            const SizedBox(height: 10),
            RadioGroup<String>(
              groupValue: _reason,
              onChanged: (value) => setState(() => _reason = value),
              child: Column(
                children: _reasons
                    .map((reason) => RadioListTile<String>(
                          value: reason,
                          activeColor: context.irColors.accent,
                          contentPadding: EdgeInsets.zero,
                          title: Text(reason,
                              style: TextStyle(color: context.irColors.text)),
                        ))
                    .toList(),
              ),
            ),
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
              child: Text('Conservar mi viaje',
                  style: TextStyle(color: context.irColors.muted)),
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
            color: context.irColors.raised,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.irColors.border)),
        child: Row(children: [
          CircleAvatar(
              backgroundColor: IrPalette.accent,
              foregroundColor: Color(0xFF171B1D),
              child: Icon(Icons.person, size: 20)),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(offer['driver_name']?.toString() ?? 'Conductor IR',
                    style: TextStyle(
                        color: context.irColors.text,
                        fontWeight: FontWeight.w700)),
                Text('${offer['amount']} COP · ${offer['status']}',
                    style:
                        TextStyle(color: context.irColors.muted, fontSize: 12)),
              ])),
          if (enabled)
            Column(children: [
              TextButton(
                  onPressed: onSelect,
                  style: TextButton.styleFrom(
                      foregroundColor: context.irColors.accent),
                  child: const Text('Aceptar')),
              TextButton(
                  onPressed: onReject,
                  style: TextButton.styleFrom(
                      foregroundColor: context.irColors.muted),
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
      Icon(Icons.near_me_outlined, color: context.irColors.accent, size: 20),
      const SizedBox(width: 9),
      Expanded(
          child: Text('$label: $distance km',
              style: TextStyle(
                  color: context.irColors.text, fontWeight: FontWeight.w700))),
    ]);
  }
}

class _PickupCodeCard extends StatelessWidget {
  const _PickupCodeCard({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        decoration: BoxDecoration(
            color: IrPalette.accent, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          const Icon(Icons.qr_code_2, color: Color(0xFF171B1D), size: 28),
          const SizedBox(width: 10),
          Expanded(
              child: Text('Código: $code',
                  style: const TextStyle(
                      color: Color(0xFF171B1D),
                      fontSize: 16,
                      fontWeight: FontWeight.w800))),
          IconButton(
              tooltip: 'Copiar código',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Código copiado.')));
              },
              icon: const Icon(Icons.copy, color: Color(0xFF171B1D))),
        ]),
      );
}

class _RideCompletionPanel extends StatelessWidget {
  const _RideCompletionPanel({required this.ride, required this.onContinue});

  final Map<String, dynamic> ride;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 22),
        decoration: BoxDecoration(
            color: context.irColors.raised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.irColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Resumen de tu viaje',
              style: TextStyle(
                  color: context.irColors.text,
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
                      backgroundColor: IrPalette.accent,
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
        Icon(icon, color: context.irColors.accent, size: 20),
        const SizedBox(width: 9),
        Expanded(
            child: RichText(
                text: TextSpan(
                    style: TextStyle(color: context.irColors.muted),
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
            color: context.irColors.raised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.irColors.border)),
        child: Column(children: [
          Text(widget.title,
              style: TextStyle(
                  color: context.irColors.text,
                  fontSize: 21,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          CircleAvatar(
              radius: 34,
              backgroundColor: IrPalette.accent,
              child: Icon(Icons.person, color: Color(0xFF171B1D), size: 34)),
          const SizedBox(height: 10),
          Text(widget.personName,
              style: TextStyle(
                  color: context.irColors.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Wrap(
              alignment: WrapAlignment.center,
              children: List.generate(
                  5,
                  (index) => IconButton(
                        onPressed: widget.rideId == null
                            ? null
                            : () => setState(() => _rating = index + 1),
                        icon: Icon(
                            index < _rating ? Icons.star : Icons.star_border,
                            color: index < _rating
                                ? context.irColors.accent
                                : context.irColors.muted,
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
                  backgroundColor: IrPalette.accent,
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
  Widget build(BuildContext context) {
    final vehicleType = _value(ride['driver_vehicle_type']);
    final isMoto = vehicleType.toLowerCase().contains('moto');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: context.irColors.raised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.irColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Tu conductor',
            style: TextStyle(
                color: context.irColors.text,
                fontSize: 17,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
              radius: 25,
              backgroundColor: IrPalette.accent,
              child: Icon(Icons.person, color: Color(0xFF171B1D), size: 28)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(_value(ride['driver_name']),
                    style: TextStyle(
                        color: context.irColors.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(isMoto ? 'Moto' : 'Carro',
                    style: TextStyle(color: context.irColors.muted)),
              ])),
          Container(
              width: 76,
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: context.irColors.raised,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.irColors.border)),
              child: Icon(isMoto ? Icons.two_wheeler : Icons.directions_car,
                  color: context.irColors.accent, size: 38)),
        ]),
        const SizedBox(height: 12),
        Text('Tipo: $vehicleType'),
        Text('Marca: ${_value(ride['driver_vehicle_brand'])}'),
        Text('Color: ${_value(ride['driver_vehicle_color'])}'),
        Text('Placa: ${_value(ride['driver_vehicle_plate'])}'),
        const SizedBox(height: 12),
        Text('Código de encuentro: ${_value(ride['pickup_code'])}',
            style: TextStyle(
                color: context.irColors.accent, fontWeight: FontWeight.w800)),
      ]),
    );
  }
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
  const _VehiclePicker(
      {required this.selected, required this.onChanged, required this.useGrid});
  final String selected;
  final ValueChanged<String> onChanged;
  final bool useGrid;
  static const options = [
    ('economy', 'Viaje', Icons.directions_car),
    ('moto', 'Moto', Icons.two_wheeler),
    ('plus', 'Viaje+', Icons.directions_car_filled),
    ('comfort', 'Comfort', Icons.ac_unit)
  ];

  @override
  Widget build(BuildContext context) {
    final height = 86 + MediaQuery.textScalerOf(context).scale(16) * 1.5;
    if (useGrid) {
      return SizedBox(
        height: height,
        child: Row(children: [
          for (var index = 0; index < options.length; index++) ...[
            if (index > 0) const SizedBox(width: 10),
            Expanded(child: _option(context, options[index], null)),
          ],
        ]),
      );
    }
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final active = options[index].$1 == selected;
          final width = MediaQuery.textScalerOf(context).scale(16) > 22
              ? (active ? 144.0 : 120.0)
              : (active ? 116.0 : 88.0);
          return _option(context, options[index], width);
        },
      ),
    );
  }

  Widget _option(
      BuildContext context, (String, String, IconData) option, double? width) {
    final active = option.$1 == selected;
    return Semantics(
      selected: active,
      button: true,
      label: option.$2,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => onChanged(option.$1),
        child: AnimatedContainer(
          duration:
              IrMotion.duration(context, const Duration(milliseconds: 180)),
          width: width,
          padding: const EdgeInsets.fromLTRB(8, 11, 8, 9),
          decoration: BoxDecoration(
            color: active ? IrPalette.accent : context.irColors.raised,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color:
                    active ? context.irColors.accent : context.irColors.border),
          ),
          child: Column(children: [
            Icon(option.$3,
                color:
                    active ? const Color(0xFF171B1D) : context.irColors.muted,
                size: 34),
            const SizedBox(height: 4),
            Text(option.$2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: active
                        ? const Color(0xFF171B1D)
                        : context.irColors.muted,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
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
            Icon(Icons.location_on_outlined,
                color: context.irColors.muted, size: 29),
            const SizedBox(width: 17),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: TextStyle(
                          color: context.irColors.text,
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
        Icon(Icons.my_location_outlined,
            color: context.irColors.muted, size: 29),
        const SizedBox(width: 17),
        Expanded(
            child: Text(origin,
                style: TextStyle(
                    color: context.irColors.muted,
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
            color: context.irColors.raised,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.irColors.border)),
        child: Row(children: [
          Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: IrPalette.accent,
                  borderRadius: BorderRadius.circular(13)),
              child: const Icon(Icons.stars, color: IrPalette.ink, size: 23)),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('ProMaster pasajero',
                    style:
                        TextStyle(color: context.irColors.muted, fontSize: 12)),
                Text('$points PI · Nivel $tier',
                    style: TextStyle(
                        color: context.irColors.text,
                        fontWeight: FontWeight.w800)),
              ])),
          Text('COP 20 = 1 PI',
              style: TextStyle(color: context.irColors.muted, fontSize: 10)),
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
          color: context.irColors.raised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.irColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.route, color: context.irColors.accent),
          const SizedBox(width: 8),
          Expanded(
              child: Text(
                  '${_displayOrigin(ride['origin']?.toString())} → ${ride['destination']}',
                  style: TextStyle(
                      color: context.irColors.text,
                      fontWeight: FontWeight.w700))),
          Text(irMoney(ride['offer_amount']),
              style: TextStyle(
                  color: context.irColors.accent, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 4),
        Text(
            'Estado: ${irRideStatus(ride['status']?.toString())} · ${ride['distance_km']} km · ${ride['duration_minutes']} min',
            style: TextStyle(color: context.irColors.muted, fontSize: 12)),
        if (offers.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Ofertas privadas',
              style: TextStyle(
                  color: context.irColors.text, fontWeight: FontWeight.w700)),
          ...offers.map((offer) => Row(children: [
                Expanded(
                    child: Text(
                        '${offer['driver_name']} · ${offer['amount']} COP',
                        style: TextStyle(
                            color: context.irColors.muted, fontSize: 12))),
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
            color: context.irColors.raised,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.irColors.border)),
        child: Row(children: [
          Icon(Icons.route, color: context.irColors.accent),
          const SizedBox(width: 10),
          Expanded(
              child: Text(
                  '${route['distance_text'] ?? '${route['distance_km']} km'}  ·  ${route['duration_text'] ?? '${route['duration_minutes']} min'}',
                  style: TextStyle(
                      color: context.irColors.text,
                      fontWeight: FontWeight.w700))),
          Text(irMoney(fare),
              style: TextStyle(
                  color: context.irColors.accent, fontWeight: FontWeight.w800)),
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
        duration: IrMotion.duration(context, const Duration(milliseconds: 180)),
        curve: Curves.easeOutCubic,
        padding:
            EdgeInsets.symmetric(horizontal: 16, vertical: condensed ? 7 : 12),
        decoration: BoxDecoration(
            color: context.irColors.surface.withValues(alpha: .97),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.irColors.border)),
        child: Row(children: [
          Icon(_maneuverIcon(nextStep?['maneuver']?.toString()),
              color: context.irColors.accent, size: condensed ? 20 : 24),
          SizedBox(width: condensed ? 8 : 12),
          Expanded(
              child: Text(destination,
                  maxLines: condensed ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: context.irColors.text,
                      fontSize: condensed ? 14 : 15,
                      fontWeight: FontWeight.w800))),
          if (route != null)
            Text(route!['duration_text']?.toString() ?? '',
                style: TextStyle(
                    color: context.irColors.accent,
                    fontWeight: FontWeight.w800)),
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
