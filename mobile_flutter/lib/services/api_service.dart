import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/driver.dart';
import '../models/verification_result.dart';
import 'api_config.dart';
import 'auth_service.dart';

/// Error raised by [ApiService] for non-success responses.
class ApiException implements Exception {
  final int? statusCode;
  final String message;

  /// Decoded response body, when the server returned JSON.
  final Map<String, dynamic>? body;

  const ApiException(this.statusCode, this.message, [this.body]);

  bool get isUnauthorized => statusCode == 401;

  bool get isConflict => statusCode == 409;

  /// The licence status reported with a duplicate-registration response.
  String? get duplicateStatus => body?['status'] as String?;

  @override
  String toString() => message;
}

/// Every call attaches the JWT stored by [AuthService] and transparently
/// maps the backend's error payloads into [ApiException].
class ApiService {
  ApiService._();

  static const Duration _timeout = Duration(seconds: 20);

  /// Registers a scanned driver licence. Throws an [ApiException] with
  /// `isConflict` when the licence number already exists.
  static Future<Driver> registerDriver({
    required String licenseId,
    required String fullName,
    String? dateOfBirth,
    String? licenseType,
    String? expiryDate,
    String? qrRawData,
    String? ocrRawText,
  }) async {
    final data = await _request(
      'POST',
      '/drivers',
      body: {
        'licenseId': licenseId,
        'fullName': fullName,
        'dateOfBirth': dateOfBirth,
        'licenseType': licenseType,
        'expiryDate': expiryDate,
        'qrRawData': qrRawData,
        'ocrRawText': ocrRawText,
      },
    );

    return Driver.fromJson(data as Map<String, dynamic>);
  }

  /// All registered drivers, newest first.
  static Future<List<Driver>> getDrivers() async {
    final data = await _request('GET', '/drivers');

    return (data as List<dynamic>)
        .map((item) => Driver.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  static Future<void> deleteDriver(String driverId) async {
    await _request('DELETE', '/drivers/$driverId');
  }

  /// Checks whether a licence is registered, and whether it has expired.
  static Future<VerificationResult> verifyLicense(String licenseId) async {
    final data = await _request(
      'POST',
      '/verification/verify',
      body: {'licenseId': licenseId},
    );

    return VerificationResult.fromJson(data as Map<String, dynamic>);
  }

  static Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$apiBaseUrl$path');
    final headers = await AuthService.getAuthHeaders();

    late final http.Response response;

    try {
      final request = http.Request(method, uri)
        ..headers.addAll(headers)
        ..body = body == null ? '' : jsonEncode(body);

      final streamed = await request.send().timeout(_timeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const ApiException(
        null,
        'The server took too long to respond. Check your connection.',
      );
    } on Exception {
      throw ApiException(
        null,
        'Could not reach the server at $apiBaseUrl. '
        'Make sure the backend is running and reachable from this device.',
      );
    }

    final decoded = _decode(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    if (response.statusCode == 401) {
      throw ApiException(
        401,
        _messageFrom(decoded) ??
            'Your session has expired. Please sign in again.',
        decoded is Map<String, dynamic> ? decoded : null,
      );
    }

    throw ApiException(
      response.statusCode,
      _messageFrom(decoded) ?? 'Request failed (HTTP ${response.statusCode}).',
      decoded is Map<String, dynamic> ? decoded : null,
    );
  }

  static dynamic _decode(String body) {
    if (body.trim().isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  static String? _messageFrom(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      final message = decoded['message'] ?? decoded['title'];
      if (message is String && message.trim().isNotEmpty) {
        return message;
      }
    }
    return null;
  }
}
