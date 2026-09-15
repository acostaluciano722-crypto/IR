import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  ApiService({String? baseUrl})
      : baseUrl = baseUrl ?? _defaultBaseUrl;

  final String baseUrl;
  String? token;

  static String get _defaultBaseUrl {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return 'http://localhost:8000/api';
    }
    return 'http://10.0.2.2:8000/api';
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    final data = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(data['detail']?.toString() ?? 'No fue posible iniciar sesion.');
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
    final response = await http.post(
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
      throw ApiException(data['detail']?.toString() ?? 'No fue posible crear la cuenta.');
    }
    token = data['token'] as String;
    return data['user'] as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getRides() async {
    final response = await http.get(Uri.parse('$baseUrl/rides/'), headers: _headers);
    final data = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(data['detail']?.toString() ?? 'No fue posible cargar tus viajes.');
    }
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> searchPlaces(String query) async {
    final response = await http.get(
      Uri.parse('$baseUrl/places/search/').replace(queryParameters: {'input': query}),
      headers: _headers,
    );
    final data = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(data['detail']?.toString() ?? 'No fue posible buscar lugares.');
    }
    return (data['predictions'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> placeDetails(String placeId) async {
    final uri = Uri.parse('$baseUrl/places/details/').replace(queryParameters: {'place_id': placeId});
    final response = await http.get(uri, headers: _headers);
    final data = _decode(response);
    if (response.statusCode != 200) throw ApiException(data['detail']?.toString() ?? 'No fue posible obtener el lugar.');
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> estimateRoute({required double originLat, required double originLng, required double destinationLat, required double destinationLng}) async {
    final uri = Uri.parse('$baseUrl/routes/estimate/').replace(queryParameters: {'origin_lat': '$originLat', 'origin_lng': '$originLng', 'destination_lat': '$destinationLat', 'destination_lng': '$destinationLng'});
    final response = await http.get(uri, headers: _headers);
    final data = _decode(response);
    if (response.statusCode != 200) throw ApiException(data['detail']?.toString() ?? 'No fue posible calcular la ruta.');
    return data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> nearbyPlaces(double latitude, double longitude) async {
    final uri = Uri.parse('$baseUrl/places/nearby/').replace(queryParameters: {'lat': '$latitude', 'lng': '$longitude'});
    final response = await http.get(uri, headers: _headers);
    final data = _decode(response);
    if (response.statusCode != 200) throw ApiException(data['detail']?.toString() ?? 'No fue posible cargar lugares cercanos.');
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
    final response = await http.post(
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
      throw ApiException(data['detail']?.toString() ?? 'No fue posible solicitar el viaje.');
    }
    return data as Map<String, dynamic>;
  }

  Map<String, String> get _headers => {
        'Authorization': 'Token $token',
        'Accept': 'application/json',
      };

  dynamic _decode(http.Response response) {
    if (response.body.isEmpty) return <String, dynamic>{};
    return jsonDecode(response.body);
  }
}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
