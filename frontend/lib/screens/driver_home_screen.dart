import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import '../ui/ir_theme.dart';
import 'bonus_screen.dart';
import 'points_screen.dart';
import 'role_section_screen.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key, required this.api, required this.user});
  final ApiService api;
  final Map<String, dynamic> user;

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  String _status = 'offline';
  int _walletBalance = 0;
  int _reservedBalance = 0;
  int _points = 0;
  String _tier = 'Inicial';
  String _vehicleType = 'carro';
  LatLng _driverLocation = const LatLng(10.391, -75.4794);
  StreamSubscription<Position>? _locationSubscription;
  bool _locationPermissionChecked = false;
  bool _isLoading = true;
  bool _menuExpanded = false;
  List<Map<String, dynamic>> _availableRides = [];
  List<Map<String, dynamic>> _myRides = [];
  final Set<int> _dismissedRatedRideIds = <int>{};
  final Set<int> _closedReviewRideIds = <int>{};
  Timer? _refreshTimer;
  Timer? _countdownTimer;
  bool _refreshing = false;
  GoogleMapController? _mapController;
  int _sheetVersion = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _startDriverLocationTracking();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      if (_status == 'available') _loadAvailableRides();
      _loadMyRides();
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _availableRides = _availableRides
            .where((ride) => (ride['remaining_seconds'] as num? ?? 0) > 0)
            .map((ride) {
          final updated = Map<String, dynamic>.from(ride);
          updated['remaining_seconds'] =
              (updated['remaining_seconds'] as num).toInt() - 1;
          return updated;
        }).toList();
      });
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _countdownTimer?.cancel();
    _locationSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await widget.api.getDriverMe();
      if (!mounted) return;
      setState(() {
        _status = profile['status'];
        _walletBalance = profile['wallet_balance'];
        _reservedBalance = profile['reserved_balance'];
        _points = profile['points'] ?? 0;
        _tier = profile['tier'] ?? 'Inicial';
        _vehicleType =
            profile['vehicle_type']?.toString().toLowerCase() ?? 'carro';
        _isLoading = false;
      });
      if (_status == 'available') {
        _loadAvailableRides();
      }
      _loadMyRides();
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMyRides() async {
    try {
      final rides = await widget.api.getDriverRides();
      if (mounted) {
        setState(() => _myRides = rides
            .where((ride) =>
                !_closedReviewRideIds.contains(_rideId(ride)) &&
                !_dismissedRatedRideIds.contains(_rideId(ride)))
            .toList());
      }
      final active = _activeRideData;
      if (active != null) await _publishDriverLocation(active['id'] as int);
    } catch (_) {}
  }

  Future<void> _publishDriverLocation(int rideId) async {
    try {
      final position = await _currentDriverPosition();
      if (position == null) return;
      await widget.api.updateRideLocation(
        rideId: rideId,
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (_) {}
  }

  Future<Position?> _currentDriverPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    if (!_locationPermissionChecked) {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) return null;
      _locationPermissionChecked = true;
    }
    return Geolocator.getCurrentPosition();
  }

  Future<void> _startDriverLocationTracking() async {
    final position = await _currentDriverPosition();
    if (position == null || !mounted) return;
    setState(() {
      _driverLocation = LatLng(position.latitude, position.longitude);
    });
    _locationSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen((position) {
      if (mounted) {
        setState(() {
          _driverLocation = LatLng(position.latitude, position.longitude);
        });
      }
      final active = _activeRideData;
      if (active != null) {
        widget.api
            .updateRideLocation(
              rideId: active['id'] as int,
              latitude: position.latitude,
              longitude: position.longitude,
            )
            .catchError((_) => <String, dynamic>{});
      }
    });
  }

  Future<void> _advanceRide(
      Map<String, dynamic> ride, String nextStatus) async {
    try {
      await widget.api.driverUpdateRideStatus(ride['id'] as int, nextStatus);
      await _loadMyRides();
      await _loadProfile();
    } on ApiException catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _ratePassenger(int rideId, int rating) async {
    _closeRideReview(rideId);
    try {
      await widget.api.rateRide(rideId, rating);
      _dismissedRatedRideIds.add(rideId);
      if (mounted) {
        setState(() {
          _status = 'available';
          _reservedBalance = 0;
        });
      }
      await _loadMyRides();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _skipPassengerRating(int rideId) async {
    _closeRideReview(rideId);
    _dismissedRatedRideIds.add(rideId);
    if (mounted) {
      setState(() {
        _status = 'available';
        _reservedBalance = 0;
      });
    }
    await _loadMyRides();
  }

  void _closeRideReview(int rideId) {
    _closedReviewRideIds.add(rideId);
    _dismissedRatedRideIds.add(rideId);
    if (mounted) {
      setState(() {
        _myRides = _myRides.where((ride) => _rideId(ride) != rideId).toList();
        _sheetVersion++;
      });
    }
  }

  int? _rideId(Map<String, dynamic> ride) =>
      int.tryParse(ride['id']?.toString() ?? '');

  Future<void> _recenterDriverMap() async {
    await _mapController
        ?.animateCamera(CameraUpdate.newLatLngZoom(_driverLocation, 16));
  }

  Future<void> _verifyPickupCode(int rideId) async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Código del pasajero'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Código de encuentro'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('Iniciar viaje')),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.trim().isEmpty) return;
    try {
      await widget.api.verifyRidePickupCode(rideId, code);
      await _loadMyRides();
      await _loadProfile();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _loadAvailableRides() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final rides = await widget.api.getDriverAvailableRides();
      if (mounted)
        setState(() {
          _availableRides = rides;
        });
    } catch (e) {
      // error handling
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _toggleStatus() async {
    if (_status != 'offline' && _status != 'available') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'No puedes cambiar disponibilidad durante un viaje activo.')));
      return;
    }
    final newStatus = _status == 'offline' ? 'available' : 'offline';
    try {
      await widget.api.updateDriverStatus(newStatus);
      setState(() {
        _status = newStatus;
      });
      if (newStatus == 'available') {
        _loadAvailableRides();
      } else {
        setState(() => _availableRides = []);
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No fue posible actualizar tu estado: $error')));
      }
    }
  }

  Future<void> _makeOffer(int rideId, int estimatedPrice) async {
    int offerAmount = estimatedPrice;

    final int? result = await showDialog<int>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Hacer oferta'),
            content: TextField(
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Monto COP'),
              onChanged: (val) =>
                  offerAmount = int.tryParse(val) ?? offerAmount,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, offerAmount),
                child: const Text('Ofertar'),
              ),
            ],
          );
        });

    if (result != null) {
      try {
        await widget.api.driverRideOffer(rideId, result);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Oferta enviada con éxito')));
        _loadAvailableRides();
        _loadMyRides();
      } catch (e) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _acceptRide(int rideId) async {
    try {
      await widget.api.driverAcceptRide(rideId);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aceptaste el precio propuesto.')));
      await _loadAvailableRides();
      await _loadMyRides();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _rejectRide(int rideId) async {
    try {
      await widget.api.driverRejectRide(rideId);
      await _loadAvailableRides();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _rechargeWallet() async {
    try {
      await widget.api.driverWalletRecharge(50000);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recargaste \$50,000 COP')));
      _loadProfile();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Theme(
          data: irDarkTheme(),
          child:
              const Scaffold(body: Center(child: CircularProgressIndicator())));
    }

    return Theme(
      data: irDarkTheme(),
      child: Scaffold(
        backgroundColor: IrPalette.surface,
        body: SafeArea(
          bottom: false,
          child: Stack(children: [
            Positioned.fill(
                child: GoogleMap(
              initialCameraPosition: const CameraPosition(
                  target: LatLng(10.391, -75.4794), zoom: 13.8),
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              onMapCreated: (controller) => _mapController = controller,
              webGestureHandling: WebGestureHandling.greedy,
              scrollGesturesEnabled: true,
              zoomGesturesEnabled: true,
              rotateGesturesEnabled: true,
              tiltGesturesEnabled: true,
              markers: _driverMarkers,
              style: _driverMapStyle,
            )),
            Positioned(
                top: 12,
                right: 16,
                child: _DriverRoundAction(
                    icon: Icons.my_location, onPressed: _recenterDriverMap)),
            Positioned(
                top: 82,
                left: 18,
                right: 18,
                child:
                    _DriverStatusPill(status: _status, onTap: _toggleStatus)),
            Positioned.fill(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: DraggableScrollableSheet(
                    key: ValueKey('driver-ride-sheet-$_sheetVersion'),
                    expand: false,
                    initialChildSize: .52,
                    minChildSize: .40,
                    maxChildSize: .90,
                    snapSizes: const [.52, .90],
                    snap: true,
                    builder: (context, controller) => Container(
                          decoration: const BoxDecoration(
                              color: IrPalette.surface,
                              borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(28))),
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
                                          borderRadius:
                                              BorderRadius.circular(4)))),
                              const SizedBox(height: 14),
                              _DriverWalletPanel(
                                  wallet: _walletBalance,
                                  reserved: _reservedBalance,
                                  available: _status == 'available',
                                  onRecharge: _rechargeWallet),
                              const SizedBox(height: 12),
                              _DriverPointsPanel(points: _points, tier: _tier),
                              const SizedBox(height: 16),
                              _driverContent(),
                            ],
                          ),
                        )),
              ),
            ),
            if (_menuExpanded)
              Positioned.fill(
                  child: GestureDetector(
                      onTap: () => setState(() => _menuExpanded = false),
                      child: Container(
                          color: Colors.black.withValues(alpha: .44)))),
            AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                top: 0,
                bottom: 0,
                left: _menuExpanded ? 0 : -324,
                width: 308,
                child: _DriverSideBar(
                    onClose: () => setState(() => _menuExpanded = false),
                    onSectionSelected: (value) {
                      setState(() => _menuExpanded = false);
                      _openDriverSection(context, value);
                    })),
            Positioned(
                top: 12,
                left: 16,
                child: _DriverRoundAction(
                    icon: _menuExpanded ? Icons.close : Icons.menu,
                    onPressed: () =>
                        setState(() => _menuExpanded = !_menuExpanded))),
          ]),
        ),
      ),
    );
  }

  Set<Marker> get _driverMarkers {
    final markers = <Marker>{};
    final isMoto = _vehicleType.contains('moto');
    markers.add(Marker(
      markerId: const MarkerId('driver-current-location'),
      position: _driverLocation,
      icon: BitmapDescriptor.defaultMarkerWithHue(
          isMoto ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueAzure),
      infoWindow: InfoWindow(
          title: isMoto ? 'Moto del conductor' : 'Carro del conductor',
          snippet: 'Ubicación actual en tiempo real'),
    ));
    for (final ride in _availableRides) {
      final lat =
          _coordinate(ride['passenger_lat']) ?? _coordinate(ride['origin_lat']);
      final lng =
          _coordinate(ride['passenger_lng']) ?? _coordinate(ride['origin_lng']);
      if (lat != null && lng != null) {
        markers.add(Marker(
            markerId: MarkerId('request-${ride['id']}'),
            position: LatLng(lat, lng),
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueYellow),
            infoWindow: InfoWindow(
                title: 'Solicitud de ${ride['passenger_name']}',
                snippet:
                    '${ride['distance_km']} km · COP ${ride['offer_amount']}')));
      }
    }
    final active = _activeRideData;
    if (active != null) {
      final lat = _coordinate(active['origin_lat']);
      final lng = _coordinate(active['origin_lng']);
      if (lat != null && lng != null) {
        markers.add(Marker(
            markerId: const MarkerId('active-pickup'),
            position: LatLng(lat, lng),
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueYellow),
            infoWindow: const InfoWindow(title: 'Punto de recogida')));
      }
      final passengerLat = _coordinate(active['passenger_lat']);
      final passengerLng = _coordinate(active['passenger_lng']);
      if (passengerLat != null && passengerLng != null) {
        markers.add(Marker(
          markerId: const MarkerId('passenger-location'),
          position: LatLng(passengerLat, passengerLng),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'Ubicación del pasajero'),
        ));
      }
    }
    return markers;
  }

  Map<String, dynamic>? get _activeRideData {
    for (final ride in _myRides) {
      if (!{'validated', 'cancelled', 'completed'}.contains(ride['status']) &&
          !_dismissedRatedRideIds.contains(ride['id'])) {
        return ride;
      }
    }
    return null;
  }

  double? _coordinate(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  void _openDriverSection(BuildContext context, String value) {
    final screen = value == 'points'
        ? PointsScreen(role: 'driver', points: _points, tier: _tier)
        : value == 'bonus'
            ? BonusScreen(role: 'driver', points: _points, tier: _tier)
            : RoleSectionScreen(
                title: value == 'history'
                    ? 'Historial de viajes'
                    : value == 'support'
                        ? 'Soporte IR'
                        : 'Perfil',
                role: 'driver',
                items: _driverSectionItems(value));
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  List<SectionItem> _driverSectionItems(String section) {
    if (section == 'history') {
      if (_myRides.isEmpty)
        return const [
          SectionItem(
              icon: Icons.inbox_outlined,
              title: 'Sin viajes asignados',
              description: 'Los viajes seleccionados aparecerán aquí.')
        ];
      return _myRides
          .map((ride) => SectionItem(
              icon: Icons.route,
              title: '${_passengerOriginLabel(ride)} → ${ride['destination']}',
              description:
                  'Estado: ${ride['status']} · Tarifa: COP ${ride['final_fare'] == 0 ? ride['offer_amount'] : ride['final_fare']}'))
          .toList();
    }
    if (section == 'support')
      return const [
        SectionItem(
            icon: Icons.help_outline,
            title: 'Centro de ayuda',
            description: 'Consulta soporte operativo y crea un caso.'),
        SectionItem(
            icon: Icons.security_outlined,
            title: 'Centro de seguridad',
            description:
                'La seguridad tiene prioridad sobre la continuidad del viaje.')
      ];
    return [
      SectionItem(
          icon: Icons.person_outline,
          title: widget.user['name']?.toString() ?? 'Conductor IR',
          description: 'Rol: conductor'),
      SectionItem(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Bolsa IR',
          description: 'Disponible: COP ${_walletBalance - _reservedBalance}')
    ];
  }

  Widget _driverContent() {
    if (_status == 'offline') {
      return const Center(
          child: Text('Estás desconectado. Conéctate para recibir viajes.'));
    }
    final active = _activeRideCard();
    if (active != null) return active;
    if (_availableRides.isEmpty)
      return const Center(child: Text('Buscando viajes cercanos...'));
    return Column(
      children: _availableRides.map((ride) {
        final passengerOrigin = _passengerOriginLabel(ride);
        return Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$passengerOrigin ➔ ${ride['destination']}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                  '${ride['passenger_name']} · ${ride['vehicle_type']}\nPrecio propuesto: \$${ride['offer_amount']} · Estimado: \$${ride['estimated_price']}\n${ride['distance_km']} km · ${ride['duration_minutes']} min · ${ride['remaining_seconds']} s restantes'),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: ElevatedButton.icon(
                        onPressed: () => _acceptRide(ride['id'] as int),
                        icon: const Icon(Icons.check),
                        label: const Text('Aceptar'))),
                const SizedBox(width: 8),
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: () => _makeOffer(
                            ride['id'] as int, ride['estimated_price'] as int),
                        icon: const Icon(Icons.local_offer_outlined),
                        label: const Text('Contraoferta'))),
              ]),
              SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                      onPressed: () => _rejectRide(ride['id'] as int),
                      icon: const Icon(Icons.close),
                      label: const Text('Rechazar'))),
            ]),
          ),
        );
      }).toList(),
    );
  }

  Widget? _activeRideCard() {
    Map<String, dynamic>? ride;
    for (final candidate in _myRides) {
      final rideId = _rideId(candidate);
      if (candidate['status'] != 'cancelled' &&
          !(candidate['status'] == 'validated' &&
              candidate['driver_rating'] != null) &&
          !_closedReviewRideIds.contains(rideId) &&
          !_dismissedRatedRideIds.contains(rideId)) {
        ride = candidate;
        break;
      }
    }
    if (ride == null) return null;
    final status = ride['status'].toString();
    if (status == 'validated') {
      return _DriverReviewPanel(
          ride: ride, onRate: _ratePassenger, onSkip: _skipPassengerRating);
    }
    final next = <String, String>{
      'en_route': 'arrived',
      'arrived': 'in_progress',
      'in_progress': 'completed',
      'completed': 'validated',
    }[status];
    final labels = {
      'en_route': 'Marcar llegada',
      'arrived': 'Iniciar viaje',
      'in_progress': 'Finalizar viaje',
      'completed': 'Validar viaje'
    };
    return Padding(
        padding: const EdgeInsets.all(12),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            status == 'completed'
                                ? 'Resumen de tu viaje'
                                : 'Viaje asignado',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 10),
                        Text(
                            '${_passengerOriginLabel(ride)} → ${ride['destination']}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        Text('Pasajero: ${ride['passenger_name']}'),
                        Text(
                            'Tarifa acordada: COP ${ride['final_fare'] == 0 ? ride['offer_amount'] : ride['final_fare']}'),
                        Text(
                            '${ride['distance_km']} km · ${ride['duration_minutes']} min'),
                        if (ride['passenger_lat'] != null &&
                            ride['passenger_lng'] != null)
                          _LiveDistanceRow(
                              label: 'Distancia al pasajero',
                              distanceKm: ride['live_distance_km']),
                        const SizedBox(height: 14),
                        Chip(label: Text('Estado: $status')),
                        if (status == 'accepted')
                          SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                  onPressed: () =>
                                      _verifyPickupCode(ride!['id'] as int),
                                  icon: const Icon(Icons.verified_outlined),
                                  label: const Text(
                                      'Introducir código e iniciar'))),
                        if (next != null)
                          SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                  onPressed: () => _advanceRide(ride!, next),
                                  icon: const Icon(Icons.arrow_forward),
                                  label: Text(labels[status]!))),
                        if (status == 'completed')
                          const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                  'El débito y los PI se aplican únicamente después de validar el viaje.',
                                  style: TextStyle(color: Colors.black54))),
                      ]))),
          const Card(
              child: ListTile(
                  leading: Icon(Icons.security_outlined),
                  title: Text('Centro de seguridad'),
                  subtitle: Text(
                      'Reporta un problema o solicita ayuda durante el viaje.'))),
        ]));
  }

  String _passengerOriginLabel(Map<String, dynamic> ride) {
    final locationLabel = ride['passenger_location_label']?.toString().trim();
    if (locationLabel != null &&
        locationLabel.isNotEmpty &&
        locationLabel != 'Ubicación actual') {
      return locationLabel;
    }
    final latitude = _coordinate(ride['passenger_lat']);
    final longitude = _coordinate(ride['passenger_lng']);
    if (latitude != null && longitude != null) {
      return 'Ubicación actual del pasajero';
    }
    return ride['origin']?.toString() ?? 'Ubicación del pasajero';
  }
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
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        const Icon(Icons.near_me_outlined, color: IrPalette.accent, size: 19),
        const SizedBox(width: 8),
        Text('$label: $distance km',
            style: const TextStyle(
                color: IrPalette.text, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _DriverReviewPanel extends StatefulWidget {
  const _DriverReviewPanel(
      {required this.ride, required this.onRate, required this.onSkip});

  final Map<String, dynamic> ride;
  final void Function(int rideId, int rating) onRate;
  final Future<void> Function(int rideId) onSkip;

  @override
  State<_DriverReviewPanel> createState() => _DriverReviewPanelState();
}

class _DriverReviewPanelState extends State<_DriverReviewPanel> {
  bool _showRating = false;

  @override
  Widget build(BuildContext context) {
    final rideId = widget.ride['id'] as int;
    if (_showRating) {
      return _DriverRatingPanel(
          rideId: rideId,
          personName:
              widget.ride['passenger_name']?.toString() ?? 'Pasajero IR',
          existingRating: widget.ride['driver_rating'],
          onRate: widget.onRate,
          onSkip: widget.onSkip);
    }
    final fare = widget.ride['final_fare'] == 0
        ? widget.ride['offer_amount']
        : widget.ride['final_fare'];
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Resumen de tu viaje',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Text(
                  '${_passengerOriginLabelFor(widget.ride)} → ${widget.ride['destination']}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('Pasajero: ${widget.ride['passenger_name']}'),
              Text('Tarifa final: COP $fare'),
              Text(
                  '${widget.ride['distance_km']} km · ${widget.ride['duration_minutes']} min'),
              const SizedBox(height: 14),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                      onPressed: () => setState(() => _showRating = true),
                      child: const Text('Continuar'))),
            ])));
  }
}

String _passengerOriginLabelFor(Map<String, dynamic> ride) {
  final label = ride['passenger_location_label']?.toString().trim();
  if (label != null && label.isNotEmpty && label != 'Ubicación actual') {
    return label;
  }
  return ride['origin']?.toString() ?? 'Ubicación del pasajero';
}

class _DriverRatingPanel extends StatefulWidget {
  const _DriverRatingPanel(
      {required this.rideId,
      required this.personName,
      required this.existingRating,
      required this.onRate,
      required this.onSkip});
  final int rideId;
  final String personName;
  final dynamic existingRating;
  final void Function(int rideId, int rating) onRate;
  final Future<void> Function(int rideId) onSkip;

  @override
  State<_DriverRatingPanel> createState() => _DriverRatingPanelState();
}

class _DriverRatingPanelState extends State<_DriverRatingPanel> {
  int _rating = 0;

  @override
  void initState() {
    super.initState();
    _rating = (widget.existingRating as num?)?.toInt() ?? 0;
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
          child: Column(children: [
            const Text('Califica al pasajero',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            const CircleAvatar(
                radius: 34,
                backgroundColor: IrPalette.accent,
                child: Icon(Icons.person, color: IrPalette.ink, size: 34)),
            const SizedBox(height: 10),
            Text(widget.personName,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                    5,
                    (index) => IconButton(
                          onPressed: widget.existingRating == null
                              ? () => setState(() => _rating = index + 1)
                              : null,
                          icon: Icon(
                              index < _rating ? Icons.star : Icons.star_border,
                              color: index < _rating
                                  ? IrPalette.accent
                                  : IrPalette.muted,
                              size: 34),
                          tooltip: '${index + 1} estrellas',
                        ))),
            FilledButton(
                onPressed: widget.existingRating == null && _rating > 0
                    ? () => widget.onRate(widget.rideId, _rating)
                    : null,
                child: Text(widget.existingRating == null
                    ? 'Guardar calificación'
                    : 'Calificación enviada')),
            TextButton(
                onPressed: widget.existingRating == null
                    ? () => widget.onSkip(widget.rideId)
                    : null,
                child: const Text('Omitir por ahora')),
          ]),
        ),
      );
}

class _DriverRoundAction extends StatelessWidget {
  const _DriverRoundAction({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
        color: IrPalette.surface,
        shape: const CircleBorder(),
        child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: IrPalette.border)),
                child: Icon(icon, color: IrPalette.text, size: 27))),
      );
}

class _DriverSideBar extends StatelessWidget {
  const _DriverSideBar(
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
        color: IrPalette.surface,
        elevation: 10,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 78, 16, 20),
            children: [
              Row(children: [
                const Expanded(
                    child: Text('IR',
                        style: TextStyle(
                            color: IrPalette.accent,
                            fontSize: 28,
                            fontWeight: FontWeight.w900))),
                IconButton(
                    tooltip: 'Cerrar menú',
                    onPressed: onClose,
                    icon: const Icon(Icons.close, color: IrPalette.muted)),
              ]),
              const Divider(color: IrPalette.border),
              const SizedBox(height: 8),
              ..._items.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      minVerticalPadding: 8,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      leading: Icon(item.$3, color: IrPalette.accent, size: 24),
                      title: Text(item.$2,
                          style: const TextStyle(
                              color: IrPalette.text,
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

class _DriverStatusPill extends StatelessWidget {
  const _DriverStatusPill({required this.status, required this.onTap});
  final String status;
  final VoidCallback onTap;

  bool get available => status == 'available';
  bool get reserved => status == 'reserved_for_trip';

  @override
  Widget build(BuildContext context) => Material(
        color: IrPalette.surface.withValues(alpha: .95),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: available
                              ? IrPalette.accent
                              : reserved
                                  ? IrPalette.accent
                                  : const Color(0xFF777A7B),
                          shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(
                          available
                              ? 'Disponible para recibir viajes'
                              : reserved
                                  ? 'Viaje reservado en curso'
                                  : 'Conectarte para recibir viajes',
                          style: const TextStyle(
                              color: IrPalette.text,
                              fontWeight: FontWeight.w700))),
                  Text(
                      available
                          ? 'ACTIVO'
                          : reserved
                              ? 'EN VIAJE'
                              : 'OFFLINE',
                      style: TextStyle(
                          color: available || reserved
                              ? IrPalette.accent
                              : IrPalette.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w800)),
                ]))),
      );
}

class _DriverWalletPanel extends StatelessWidget {
  const _DriverWalletPanel(
      {required this.wallet,
      required this.reserved,
      required this.available,
      required this.onRecharge});
  final int wallet;
  final int reserved;
  final bool available;
  final VoidCallback onRecharge;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: IrPalette.raised,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: IrPalette.border)),
        child: Row(children: [
          const Icon(Icons.account_balance_wallet_outlined,
              color: IrPalette.accent, size: 27),
          const SizedBox(width: 11),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Bolsa IR · COP $wallet',
                    style: const TextStyle(
                        color: IrPalette.text, fontWeight: FontWeight.w800)),
                Text(
                    'Disponible COP ${wallet - reserved} · Reservado COP $reserved',
                    style:
                        const TextStyle(color: IrPalette.muted, fontSize: 12)),
              ])),
          TextButton(
              onPressed: onRecharge,
              style: TextButton.styleFrom(foregroundColor: IrPalette.accent),
              child: const Text('Recargar')),
        ]),
      );
}

class _DriverPointsPanel extends StatelessWidget {
  const _DriverPointsPanel({required this.points, required this.tier});
  final int points;
  final String tier;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
            color: IrPalette.ink, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Icon(Icons.stars, color: IrPalette.accent, size: 28),
          const SizedBox(width: 10),
          Expanded(
              child: Text('$points PI · Nivel $tier',
                  style: const TextStyle(
                      color: IrPalette.text, fontWeight: FontWeight.w800))),
          const Icon(Icons.card_giftcard, color: IrPalette.accent),
        ]),
      );
}

const _driverMapStyle = '''[
  {"elementType":"geometry","stylers":[{"color":"#11151b"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#aeb7c2"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#11151b"}]},
  {"featureType":"poi","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#28333e"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#626b75"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#091017"}]}
]''';
