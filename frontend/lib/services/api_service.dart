import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_auth.dart';
import 'face_verification.dart';

class ApiService {
  ApiService({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? _defaultBaseUrl,
        _client = client;

  final String baseUrl;
  final http.Client? _client;
  String? token;
  final _pendingGets = <String, Future<http.Response>>{};

  Future<Map<String, dynamic>> getDriverCompensation(
      {bool plan = false}) async {
    final response = await _get(
        Uri.parse('$baseUrl/driver/compensation/${plan ? 'plan/' : ''}'),
        headers: _headers);
    final data = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(_errorMessage(data,
          'No se pudo cargar el plan de compensación. Inténtalo de nuevo.'));
    }
    return data as Map<String, dynamic>;
  }

  bool get usesSupabase => AppAuth.enabled;
  static final _faceGateEvents = StreamController<void>.broadcast();
  static DateTime? _lastFaceGateEvent;
  Stream<void> get faceVerificationRequiredEvents => _faceGateEvents.stream;

  static const _configuredBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get _defaultBaseUrl {
    if (_configuredBaseUrl.isNotEmpty) return _configuredBaseUrl;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return 'http://127.0.0.1:8000/api';
    }
    return 'http://10.0.2.2:8000/api';
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    if (usesSupabase) {
      try {
        await AppAuth.client!.auth
            .signInWithPassword(email: username.trim(), password: password);
        return await getCurrentUser();
      } on AuthException catch (error) {
        if (error.code == 'invalid_credentials') {
          final response = await _post(
              Uri.parse('$baseUrl/auth/legacy-migrate/'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'username': username, 'password': password}));
          if (response.statusCode == 202) {
            final result = _decode(response);
            try {
              await resendConfirmation(result['confirmation_email'].toString());
            } on ApiException {
              throw EmailConfirmationRequired(
                  'Tu cuenta está vinculada. Solicita de nuevo el correo de confirmación.');
            }
            throw EmailConfirmationRequired(result['detail'].toString());
          }
        }
        throw ApiException(AppAuth.errorMessage(error));
      }
    }
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
    if (usesSupabase) {
      try {
        final result = await AppAuth.client!.auth.signUp(
            email: identifier.trim(),
            password: password,
            emailRedirectTo: AppAuth.redirectUrl,
            data: {
              'full_name': name,
              'ir_onboarding': {
                'name': name,
                'role': role,
              },
            });
        if (result.session == null) {
          throw EmailConfirmationRequired(
              'Revisa tu correo y confirma tu cuenta para continuar.');
        }
        return await getCurrentUser();
      } on AuthException catch (error) {
        throw ApiException(AppAuth.errorMessage(error));
      }
    }
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
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/profile/photo/'))
          ..headers.addAll(_headers)
          ..files.add(
              http.MultipartFile.fromBytes('photo', bytes, filename: filename));
    final response = await _mutate(() async {
      final streamed = await (_client?.send(request) ?? request.send());
      return http.Response.fromStream(streamed);
    });
    final data = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(_errorMessage(data, 'No se pudo guardar la foto.'));
    }
    return data['photo_url']?.toString();
  }

  Future<FaceVerificationStatus> getFaceVerificationStatus() async {
    final response =
        await _get(Uri.parse('$baseUrl/profile/face/'), headers: _headers);
    return FaceVerificationStatus.fromJson(_faceResponse(response));
  }

  Future<FaceVerificationStatus> enrollFace({
    required Uint8List documentBytes,
    required String documentFilename,
    required Uint8List selfieBytes,
    required String selfieFilename,
    required String consentVersion,
  }) async {
    final challenge = await _faceChallenge('enroll');
    final request = http.MultipartRequest(
        'POST', Uri.parse('$baseUrl/profile/face/enroll/'))
      ..headers.addAll(_headers)
      ..fields.addAll({
        'consent': 'true',
        'consent_version': consentVersion,
        'challenge_token': challenge,
      })
      ..files.addAll([
        _faceImage('document', documentBytes, documentFilename),
        _faceImage('selfie', selfieBytes, selfieFilename),
      ]);
    return FaceVerificationStatus.fromJson(
        _faceResponse(await _sendFaceImage(request)));
  }

  Future<FaceVerificationResult> verifyFace({
    required Uint8List selfieBytes,
    required String selfieFilename,
  }) async {
    final challenge = await _faceChallenge('verify');
    final request = http.MultipartRequest(
        'POST', Uri.parse('$baseUrl/profile/face/verify/'))
      ..headers.addAll(_headers)
      ..fields['challenge_token'] = challenge
      ..files.add(_faceImage('selfie', selfieBytes, selfieFilename));
    return FaceVerificationResult.fromJson(
        _faceResponse(await _sendFaceImage(request)));
  }

  Future<void> revokeFaceEnrollment() async {
    final response =
        await _delete(Uri.parse('$baseUrl/profile/face/'), headers: _headers);
    if (response.statusCode != 204) _faceResponse(response);
    _lastFaceGateEvent = DateTime.now();
    _faceGateEvents.add(null);
  }

  Future<String> _faceChallenge(String purpose) async {
    final response = await _post(
      Uri.parse('$baseUrl/profile/face/challenge/'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'purpose': purpose}),
    );
    final data = _faceResponse(response);
    final challenge = data['challenge_token'];
    if (challenge is! String || challenge.isEmpty) {
      throw FaceVerificationException(
          'No pudimos preparar la comprobación. Intenta de nuevo.',
          code: 'invalid_challenge');
    }
    return challenge;
  }

  http.MultipartFile _faceImage(
      String field, Uint8List bytes, String filename) {
    var subtype = 'jpeg';
    if (bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      subtype = 'png';
    } else if (bytes.length >= 12 &&
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
      subtype = 'webp';
    }
    return http.MultipartFile.fromBytes(field, bytes,
        filename: filename, contentType: MediaType('image', subtype));
  }

  Future<http.Response> _sendFaceImage(http.MultipartRequest request) async {
    try {
      return await (() async {
        final streamed = await (_client?.send(request) ?? request.send());
        return http.Response.fromStream(streamed);
      })()
          .timeout(const Duration(seconds: 75));
    } on TimeoutException {
      throw FaceVerificationException(
          'La comprobación está tardando más de lo esperado. Vuelve a intentarlo.',
          code: 'service_unavailable');
    } on http.ClientException {
      throw FaceVerificationException(
          'No hay conexión con IR. Revisa tu conexión e intenta de nuevo.',
          code: 'service_unavailable');
    } finally {
      _pendingGets.clear();
    }
  }

  Map<String, dynamic> _faceResponse(http.Response response) {
    final data = _decode(response);
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        data is Map) {
      return Map<String, dynamic>.from(data);
    }
    throw FaceVerificationException(
        _errorMessage(data, 'No pudimos completar la comprobación facial.'),
        code: data is Map ? data['code']?.toString() : null);
  }

  Future<void> deleteProfilePhoto() async {
    final response =
        await _delete(Uri.parse('$baseUrl/profile/photo/'), headers: _headers);
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
      throw ApiException(
          _errorMessage(data, 'No se pudieron cargar los vehículos cercanos.'));
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
      throw ApiException(
          _errorMessage(data, 'No se pudo actualizar tu disponibilidad.'));
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
      throw ApiException(
          _errorMessage(data, 'No se pudo cargar el historial de cartera.'));
    }
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<http.Response> _request(Future<http.Response> Function() send) async {
    try {
      final response = await send().timeout(const Duration(seconds: 20));
      if (response.statusCode == 403) {
        final data = _decode(response);
        final now = DateTime.now();
        if (data is Map &&
            data['code'] == 'face_verification_required' &&
            (_lastFaceGateEvent == null ||
                now.difference(_lastFaceGateEvent!).inMilliseconds >= 500)) {
          _lastFaceGateEvent = now;
          _faceGateEvents.add(null);
        }
      }
      return response;
    } on TimeoutException {
      throw ApiException(
          'IR tardó demasiado en responder. Inténtalo de nuevo.');
    } on http.ClientException {
      throw ApiException(
          'No hay conexión con IR. Revisa tu conexión e inténtalo de nuevo.');
    }
  }

  Future<http.Response> _get(Uri uri, {Map<String, String>? headers}) async {
    final names = headers?.keys.toList() ?? <String>[];
    names.sort();
    final key = jsonEncode([
      uri.toString(),
      {for (final name in names) name: headers![name]}
    ]);
    final existing = _pendingGets[key];
    if (existing != null) return existing;
    // Share only an in-flight read. Completed responses are never cached.
    final pending = _request(() =>
        _client?.get(uri, headers: headers) ?? http.get(uri, headers: headers));
    _pendingGets[key] = pending;
    try {
      return await pending;
    } finally {
      if (identical(_pendingGets[key], pending)) _pendingGets.remove(key);
    }
  }

  Future<http.Response> _mutate(Future<http.Response> Function() send) async {
    try {
      return await _request(send);
    } finally {
      // A read started before a write must not absorb the next refresh.
      _pendingGets.clear();
    }
  }

  Future<http.Response> _post(Uri uri,
          {Map<String, String>? headers, Object? body}) =>
      _mutate(() =>
          _client?.post(uri, headers: headers, body: body) ??
          http.post(uri, headers: headers, body: body));
  Future<http.Response> _patch(Uri uri,
          {Map<String, String>? headers, Object? body}) =>
      _mutate(() =>
          _client?.patch(uri, headers: headers, body: body) ??
          http.patch(uri, headers: headers, body: body));
  Future<http.Response> _delete(Uri uri, {Map<String, String>? headers}) =>
      _mutate(() =>
          _client?.delete(uri, headers: headers) ??
          http.delete(uri, headers: headers));

  Map<String, String> get _headers {
    if (usesSupabase) {
      final accessToken = AppAuth.client!.auth.currentSession?.accessToken;
      return {
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      };
    }
    return {
      if (token != null) 'Authorization': 'Token $token',
      'Accept': 'application/json'
    };
  }

  Future<Map<String, dynamic>> getCurrentUser() async {
    final response =
        await _get(Uri.parse('$baseUrl/auth/me/'), headers: _headers);
    final data = _decode(response);
    if (response.statusCode == 409) {
      if (data is Map && data['code'] == 'legacy_link_required') {
        throw LegacyAccountLinkRequiredException();
      }
      throw ProfileRequiredException();
    }
    if (response.statusCode != 200) {
      throw ApiException(_errorMessage(data, 'No pudimos cargar tu perfil.'));
    }
    return data as Map<String, dynamic>;
  }

  Future<void> completeProfile(Map<String, dynamic> profile) async {
    final response = await _post(Uri.parse('$baseUrl/auth/profile/'),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode(profile));
    if (response.statusCode != 200 && response.statusCode != 201) {
      if (response.statusCode == 409 &&
          _decode(response)['code'] == 'legacy_link_required') {
        throw LegacyAccountLinkRequiredException();
      }
      throw ApiException(
          _errorMessage(_decode(response), 'Revisa los datos del perfil.'));
    }
  }

  Future<void> linkLegacyAccount(String password) async {
    final response = await _post(Uri.parse('$baseUrl/auth/link-legacy/'),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode({'password': password}));
    if (response.statusCode != 200) {
      throw ApiException(
          _errorMessage(_decode(response), 'No pudimos vincular tu cuenta.'));
    }
  }

  Future<void> signInWithGoogle() async {
    if (!await isGoogleSignInAvailable()) {
      throw ApiException(
          'El acceso con Google aún no está disponible. Usa tu correo.');
    }
    try {
      final opened = await AppAuth.client!.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: AppAuth.redirectUrl);
      if (!opened) throw ApiException('No pudimos abrir el acceso de Google.');
    } on AuthException catch (error) {
      throw ApiException(AppAuth.errorMessage(error));
    }
  }

  Future<bool> isGoogleSignInAvailable() async {
    final response = await _get(
        Uri.parse('${AppAuth.supabaseUrl}/auth/v1/settings'),
        headers: {'apikey': AppAuth.publishableKey});
    if (response.statusCode != 200) {
      throw ApiException(
          'No pudimos comprobar el acceso con Google. Intenta de nuevo.');
    }
    final settings = _decode(response);
    return settings is Map &&
        settings['external'] is Map &&
        settings['external']['google'] == true;
  }

  Future<void> resetPassword(String email) async {
    try {
      await AppAuth.client!.auth
          .resetPasswordForEmail(email.trim(), redirectTo: AppAuth.redirectUrl);
    } on AuthException catch (error) {
      throw ApiException(AppAuth.errorMessage(error));
    }
  }

  Future<void> resendConfirmation(String email) async {
    try {
      await AppAuth.client!.auth.resend(
          type: OtpType.signup,
          email: email.trim(),
          emailRedirectTo: AppAuth.redirectUrl);
    } on AuthException catch (error) {
      throw ApiException(AppAuth.errorMessage(error));
    }
  }

  Future<void> signOut() async {
    if (usesSupabase) await AppAuth.client!.auth.signOut();
    token = null;
    _pendingGets.clear();
  }

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

class EmailConfirmationRequired extends ApiException {
  EmailConfirmationRequired(super.message);
}

class FaceVerificationException extends ApiException {
  FaceVerificationException(super.message, {this.code});
  final String? code;
}

class ProfileRequiredException extends ApiException {
  ProfileRequiredException() : super('Completa tu perfil para continuar.');
}

class LegacyAccountLinkRequiredException extends ProfileRequiredException {}
