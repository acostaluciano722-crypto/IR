import 'dart:async';

import 'package:flutter/material.dart';
import '../services/api_service.dart';
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
  bool _isLoading = true;
  List<Map<String, dynamic>> _availableRides = [];
  List<Map<String, dynamic>> _myRides = [];
  Timer? _refreshTimer;
  Timer? _countdownTimer;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _refreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted && _status == 'available') _loadAvailableRides();
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
      if (mounted) setState(() => _myRides = rides);
    } catch (_) {}
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
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('IR Conductor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_wallet),
            onPressed: _rechargeWallet,
          ),
          PopupMenuButton<String>(
            tooltip: 'ProMaster',
            onSelected: (value) {
              final screen = value == 'points'
                  ? PointsScreen(role: 'driver', points: _points, tier: _tier)
                  : value == 'bonus'
                      ? BonusScreen(
                          role: 'driver', points: _points, tier: _tier)
                      : RoleSectionScreen(
                          title: value == 'history'
                              ? 'Historial de viajes'
                              : value == 'support'
                                  ? 'Soporte IR'
                                  : 'Perfil',
                          role: 'driver',
                          items: _driverSectionItems(value));
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => screen));
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'points',
                  child: ListTile(
                      leading: Icon(Icons.stars_outlined),
                      title: Text('Puntos'))),
              PopupMenuItem(
                  value: 'bonus',
                  child: ListTile(
                      leading: Icon(Icons.card_giftcard_outlined),
                      title: Text('Bonificaciones'))),
              PopupMenuItem(
                  value: 'history',
                  child: ListTile(
                      leading: Icon(Icons.history), title: Text('Historial'))),
              PopupMenuItem(
                  value: 'support',
                  child: ListTile(
                      leading: Icon(Icons.support_agent_outlined),
                      title: Text('Soporte'))),
              PopupMenuItem(
                  value: 'profile',
                  child: ListTile(
                      leading: Icon(Icons.person_outline),
                      title: Text('Perfil'))),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[200],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bolsa IR: \$$_walletBalance',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('Reservado: \$$_reservedBalance',
                        style: const TextStyle(color: Colors.red)),
                    Text('Disponible: \$${_walletBalance - _reservedBalance}',
                        style: const TextStyle(color: Colors.green)),
                  ],
                ),
                Switch(
                  value: _status == 'available',
                  onChanged: (val) => _toggleStatus(),
                ),
                Flexible(
                    child: Text(_status.toUpperCase(),
                        overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Card(
              color: const Color(0xFF171B1D),
              child: ListTile(
                leading: const Icon(Icons.stars, color: Color(0xFFE8F044)),
                title: Text('$_points PI · Nivel $_tier',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800)),
                subtitle: const Text(
                    'PI conductor = débito válido consumido / COP 10',
                    style: TextStyle(color: Colors.white70, fontSize: 11)),
                trailing: IconButton(
                    tooltip: 'Bonificaciones',
                    icon: const Icon(Icons.card_giftcard,
                        color: Color(0xFFE8F044)),
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => BonusScreen(
                                role: 'driver',
                                points: _points,
                                tier: _tier)))),
              ),
            ),
          ),
          Expanded(
            child: _driverContent(),
          ),
        ],
      ),
    );
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
    return ListView.builder(
      itemCount: _availableRides.length,
      itemBuilder: (context, index) {
        final ride = _availableRides[index];
        return Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${ride['origin']} ➔ ${ride['destination']}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                  '${ride['passenger_name']} · ${ride['vehicle_type']}\nPrecio propuesto: \$${ride['offer_amount']} · Estimado: \$${ride['estimated_price']}\n${ride['distance_km']} km · ${ride['duration_minutes']} min · ${ride['remaining_seconds']} s restantes'),
              const SizedBox(height: 10),
              SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                      onPressed: () => _makeOffer(
                          ride['id'] as int, ride['estimated_price'] as int),
                      icon: const Icon(Icons.local_offer_outlined),
                      label: const Text('Hacer oferta'))),
            ]),
          ),
        );
      },
    );
  }

  Widget? _activeRideCard() {
    Map<String, dynamic>? ride;
    for (final candidate in _myRides) {
      if (candidate['status'] != 'validated' &&
          candidate['status'] != 'cancelled') {
        ride = candidate;
        break;
      }
    }
    if (ride == null) return null;
    final status = ride['status'].toString();
    final next = <String, String>{
      'driver_selected': 'en_route',
      'en_route': 'arrived',
      'arrived': 'in_progress',
      'in_progress': 'completed',
      'completed': 'validated',
    }[status];
    final labels = {
      'driver_selected': 'Iniciar ruta al pasajero',
      'en_route': 'Marcar llegada',
      'arrived': 'Iniciar viaje',
      'in_progress': 'Finalizar viaje',
      'completed': 'Validar viaje'
    };
    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Viaje asignado',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    Text('${ride['origin']} → ${ride['destination']}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('Pasajero: ${ride['passenger_name']}'),
                    Text(
                        'Tarifa acordada: COP ${ride['final_fare'] == 0 ? ride['offer_amount'] : ride['final_fare']}'),
                    Text(
                        '${ride['distance_km']} km · ${ride['duration_minutes']} min'),
                    const SizedBox(height: 14),
                    Chip(label: Text('Estado: $status')),
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
    ]);
  }
}
