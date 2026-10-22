import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  ApiService({String? baseUrl}) : baseUrl = baseUrl ?? _defaultBaseUrl;

  final String baseUrl;
  String? token;

  static const _configuredBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get _defaultBaseUrl {
    if (_configuredBaseUrl.isNotEmpty) return _configuredBaseUrl;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return 'http://127.0.0.1:8000/api';
    }
    return 'http://10.0.2.2:8000/api';
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await _post(
      Uri.parse('$baseUrl/auth/login/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    final data = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(data is Map
          ? data['detail']?.toString() ?? 'No fue posible iniciar sesion.'
          : 'No fue posible iniciar sesion. (HTTP ${response.statusCode})');
    }
    token = data['token'] as String;
    return data['user'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> register({
    required String name,
    required String identifier,
    required String phone,
    required String role,
    required String password,
    String documentNumber = '',
    String vehicleType = '',
    String vehiclePlate = '',
  }) async {
    final response = await _post(
      Uri.parse('$baseUrl/auth/register/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'identifier': identifier,
        'phone': phone,
        'role': role,
        'password': password,
        'document_number': documentNumber,
        'vehicle_type': vehicleType,
        'vehicle_plate': vehiclePlate,
      }),
    );
    final data = _decode(response);
    if (response.statusCode != 201) {
      throw ApiException(
          _errorMessage(data, 'No fue posible crear la cuenta.'));
    }
    token = data['token'] as String;
    return data['user'] as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getRides() async {
    final response =
        await _get(Uri.parse('$baseUrl/rides/'), headers: _headers);
    final data = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(
          data['detail']?.toString() ?? 'No fue posible cargar tus viajes.');
    }
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> updateRideLocation({
    required int rideId,
    required double latitude,
    required double longitude,
  }) async {
    final response = await _post(
      Uri.parse('$baseUrl/rides/$rideId/location/'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'latitude': latitude, 'longitude': longitude}),
    );
    final data = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(_errorMessage(data,
          'No fue posible actualizar tu ubicación. (HTTP ${response.statusCode})'));
    }
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getPassengerMe() async {
    final response =
        await _get(Uri.parse('$baseUrl/passenger/me/'), headers: _headers);
    final data = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(
          data['detail']?.toString() ?? 'No fue posible cargar tus puntos.');
    }
    return data as Map<String, dynamic>;
  }

  Future<String?> uploadProfilePhoto({
    required Uint8List bytes,
    required String filename,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/profile/photo/'))
      ..headers.addAll(_headers)
      ..files.add(http.MultipartFile.fromBytes('photo', bytes, filename: filename));
    final response = await _request(() async {
      final streamed = await request.send();
      return http.Response.fromStream(streamed);
    });
    final data = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(_errorMessage(data, 'No se pudo guardar la foto.'));
    }
    return data['photo_url']?.toString();
  }

  Future<void> deleteProfilePhoto() async {
    final response = await _request(() => http.delete(
          Uri.parse('$baseUrl/profile/photo/'),
          headers: _headers,
        ));
    if (response.statusCode != 204) {
      final data = _decode(response);
      throw ApiException(_errorMessage(data, 'No se pudo quitar la foto.'));
    }
  }

  Future<List<Map<String, dynamic>>> getNearbyDrivers({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/nearby/').replace(queryParameters: {
      'lat': latitude.toString(),
      'lng': longitude.toString(),
    });
    final response = await _get(uri, headers: _headers);
    final data = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(_errorMessage(data, 'No se pudieron cargar los vehículos cercanos.'));
    }
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<void> publishDriverPresence({
    required double latitude,
    required double longitude,
  }) async {
    final response = await _post(
      Uri.parse('$baseUrl/driver/presence/'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'latitude': latitude, 'longitude': longitude}),
    );
    if (response.statusCode != 200) {
      final data = _decode(response);
      throw ApiException(_errorMessage(data, 'No se pudo actualizar tu disponibilidad.'));
    }
  }

  Future<List<Map<String, dynamic>>> searchPlaces(String query) async {
    final response = await _get(
      Uri.parse('$baseUrl/places/search/')
          .replace(queryParameters: {'input': query}),
      headers: _headers,
    );
    final data = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(
          data['detail']?.toString() ?? 'No fue posible buscar lugares.');
    }
    return (data['predictions'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> placeDetails(String placeId) async {
    final uri = Uri.parse('$baseUrl/places/details/')
        .replace(queryParameters: {'place_id': placeId});
    final response = await _get(uri, headers: _headers);
    final data = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(
          data['detail']?.toString() ?? 'No fue posible obtener el lugar.');
    }
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> estimateRoute(
      {required double originLat,
      required double originLng,
      required double destinationLat,
      required double destinationLng}) async {
    final uri =
        Uri.parse('$baseUrl/routes/estimate/').replace(queryParameters: {
      'origin_lat': '$originLat',
      'origin_lng': '$originLng',
      'destination_lat': '$destinationLat',
      'destination_lng': '$destinationLng'
    });
    final response = await _get(uri, headers: _headers);
    final data = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(
          data['detail']?.toString() ?? 'No fue posible calcular la ruta.');
    }
    return data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> nearbyPlaces(
      double latitude, double longitude) async {
    final uri = Uri.parse('$baseUrl/places/nearby/')
        .replace(queryParameters: {'lat': '$latitude', 'lng': '$longitude'});
    final response = await _get(uri, headers: _headers);
    final data = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(data['detail']?.toString() ??
          'No fue posible cargar lugares cercanos.');
    }
    return (data['places'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> requestRide({
    required String origin,
    required String destination,
    required String vehicleType,
    required int offerAmount,
    required int estimatedPrice,
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
    required double distanceKm,
    required int durationMinutes,
  }) async {
    final response = await _post(
      Uri.parse('$baseUrl/rides/'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'origin': origin,
        'destination': destination,
        'vehicle_type': vehicleType,
        'offer_amount': offerAmount,
        'estimated_price': estimatedPrice,
        'origin_lat': originLat,
        'origin_lng': originLng,
        'destination_lat': destinationLat,
        'destination_lng': destinationLng,
        'distance_km': distanceKm,
        'duration_minutes': durationMinutes,
      }),
    );
    final data = _decode(response);
    if (response.statusCode != 201) {
      throw ApiException(_errorMessage(data,
          'No fue posible solicitar el viaje. (HTTP ${response.statusCode})'));
    }
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getDriverMe() async {
    final response =
        await _get(Uri.parse('$baseUrl/driver/me/'), headers: _headers);
    final data = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(
          data['detail']?.toString() ?? 'Error al cargar perfil de conductor.');
    }
    return data as Map<String, dynamic>;
  }

  Future<void> updateDriverStatus(String status) async {
    final response = await _patch(
      Uri.parse('$baseUrl/driver/me/'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'status': status}),
    );
    if (response.statusCode != 200) {
      throw ApiException('Error al actualizar estado.');
    }
  }

  Future<List<Map<String, dynamic>>> getDriverAvailableRides() async {
    final response = await _get(Uri.parse('$baseUrl/driver/rides/available/'),
        headers: _headers);
    final data = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException('Error al buscar viajes disponibles.');
    }
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getDriverRides() async {
    final response =
        await _get(Uri.parse('$baseUrl/driver/rides/mine/'), headers: _headers);
    final data = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(data is Map
          ? data['detail']?.toString() ?? 'No fue posible cargar tus viajes.'
          : 'No fue posible cargar tus viajes.');
    }
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> driverRideOffer(int rideId, int amount) async {
    final response = await _post(
      Uri.parse('$baseUrl/driver/rides/$rideId/offers/'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'amount': amount}),
    );
    final data = _decode(response);
    if (response.statusCode != 201) {
      throw ApiException(data['detail']?.toString() ?? 'Error al ofertar.');
    }
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> driverAcceptRide(int rideId) async {
    final response = await _post(
      Uri.parse('$baseUrl/driver/rides/$rideId/accept/'),
      headers: _headers,
    );
    final data = _decode(response);
    if (response.statusCode != 201) {
      throw ApiException(_errorMessage(data,
          'No fue posible aceptar la solicitud. (HTTP ${response.statusCode})'));
    }
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> selectRideOffer(int rideId, int offerId) async {
    final response = await _post(
      Uri.parse('$baseUrl/rides/$rideId/offers/$offerId/select/'),
      headers: _headers,
    );
    final data = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(
          data['detail']?.toString() ?? 'La oferta ya no está disponible.');
    }
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> rejectRideOffer(int rideId, int offerId) async {
    final response = await _post(
      Uri.parse('$baseUrl/rides/$rideId/offers/$offerId/reject/'),
      headers: _headers,
    );
    final data = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(_errorMessage(data,
          'No fue posible rechazar la oferta. (HTTP ${response.statusCode})'));
    }
    return data as Map<String, dynamic>;
  }

  Future<void> driverRejectRide(int rideId) async {
    final response = await _post(
        Uri.parse('$baseUrl/driver/rides/$rideId/reject/'),
        headers: _headers);
    final data = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(_errorMessage(data,
          'No fue posible rechazar la solicitud. (HTTP ${response.statusCode})'));
    }
  }

  Future<Map<String, dynamic>> cancelRide(int rideId,
      {String reason = ''}) async {
    final response = await _post(
      Uri.parse('$baseUrl/rides/$rideId/cancel/'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'reason': reason}),
    );
    final data = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(_errorMessage(data,
          'No fue posible cancelar el viaje. (HTTP ${response.statusCode})'));
    }
    return data as Map<String, dynamic>;
  }

  Future<void> driverUpdateRideStatus(int rideId, String status) async {
    final response = await _post(
      Uri.parse('$baseUrl/driver/rides/$rideId/status/'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'status': status}),
    );
    if (response.statusCode != 200) {
      throw ApiException('Error al actualizar estado del viaje.');
    }
  }

  Future<void> verifyRidePickupCode(int rideId, String code) async {
    final response = await _post(
      Uri.parse('$baseUrl/driver/rides/$rideId/verify-code/'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'code': code}),
    );
    final data = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(_errorMessage(data,
          'No fue posible iniciar el viaje. (HTTP ${response.statusCode})'));
    }
  }

  Future<void> rateRide(int rideId, int rating) async {
    final response = await _post(
      Uri.parse('$baseUrl/rides/$rideId/rating/'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'rating': rating}),
    );
    final data = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(_errorMessage(data,
          'No fue posible guardar la calificación. (HTTP ${response.statusCode})'));
    }
  }

  Future<Map<String, dynamic>> driverWalletRecharge(int amount) async {
    final response = await _post(
      Uri.parse('$baseUrl/driver/wallet/recharge/'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'amount': amount}),
    );
    final data = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(_errorMessage(data, 'Error al registrar la recarga.'));
    }
    return data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getDriverWalletTransactions() async {
    final response = await _get(
      Uri.parse('$baseUrl/driver/wallet/transactions/'),
      headers: _headers,
    );
    final data = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(_errorMessage(data, 'No se pudo cargar el historial de cartera.'));
    }
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<http.Response> _request(Future<http.Response> Function() send) async {
    try {
      return await send().timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw ApiException(
          'IR tardó demasiado en responder. Inténtalo de nuevo.');
    } on http.ClientException {
      throw ApiException(
          'No hay conexión con IR. Revisa tu conexión e inténtalo de nuevo.');
    }
  }

  Future<http.Response> _get(Uri uri, {Map<String, String>? headers}) =>
      _request(() => http.get(uri, headers: headers));
  Future<http.Response> _post(Uri uri,
          {Map<String, String>? headers, Object? body}) =>
      _request(() => http.post(uri, headers: headers, body: body));
  Future<http.Response> _patch(Uri uri,
          {Map<String, String>? headers, Object? body}) =>
      _request(() => http.patch(uri, headers: headers, body: body));

  Map<String, String> get _headers => {
        'Authorization': 'Token $token',
        'Accept': 'application/json',
      };

  dynamic _decode(http.Response response) {
    if (response.body.isEmpty) return <String, dynamic>{};
    try {
      return jsonDecode(response.body);
    } catch (_) {
      return <String, dynamic>{
        'detail':
            'Respuesta inválida del servidor (HTTP ${response.statusCode}).'
      };
    }
  }

  String _errorMessage(dynamic data, String fallback) {
    if (data is Map && data['detail'] != null) {
      return data['detail'].toString();
    }
    if (data is Map) {
      final messages = <String>[];
      data.forEach((field, value) {
        if (value is List) {
          messages.add('$field: ${value.map(_flattenError).join(' ')}');
        } else if (value != null) {
          messages.add('$field: ${_flattenError(value)}');
        }
      });
      if (messages.isNotEmpty) return messages.join('\n');
    }
    return fallback;
  }

  String _flattenError(dynamic value) {
    if (value is Map) {
      return value.values.map(_flattenError).join(' ');
    }
    if (value is List) return value.map(_flattenError).join(' ');
    return value.toString();
  }
}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
