import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';

class AuthService {
  static const String _baseUrl = '$apiBaseUrl/auth';
  static const String _tokenKey = 'access_token';
  static const String _tokenTypeKey = 'token_type';
  static const String _expiryKey = 'token_expiry';

  /// Sends POST request to /api/auth/login and stores the token locally.
  static Future<void> login({
    required String username,
    required String password,
  }) async {
    final uri = Uri.parse('$_baseUrl/login');

    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'username': username.trim(),
            'password': password,
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final accessToken = data['accessToken'] as String?;
      final tokenType = (data['tokenType'] as String?) ?? 'Bearer';
      final expiresInMinutes =
          (data['expiresInMinutes'] as num?)?.toInt() ?? 60;

      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('Server did not return a valid accessToken.');
      }

      final expiryTime = DateTime.now()
          .add(Duration(minutes: expiresInMinutes))
          .millisecondsSinceEpoch;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, accessToken);
      await prefs.setString(_tokenTypeKey, tokenType);
      await prefs.setInt(_expiryKey, expiryTime);
    } else if (response.statusCode == 401 || response.statusCode == 400) {
      throw Exception('Invalid username or password.');
    } else {
      throw Exception(
        'Login failed (Status ${response.statusCode}): ${response.body}',
      );
    }
  }

  /// Checks if a non-expired accessToken exists locally.
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final expiry = prefs.getInt(_expiryKey);

    if (token == null || token.isEmpty || expiry == null) {
      return false;
    }

    if (DateTime.now().millisecondsSinceEpoch >= expiry) {
      await logout();
      return false;
    }

    return true;
  }

  /// Retrieves the stored Bearer header for authenticated API calls.
  static Future<Map<String, String>> getAuthHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final tokenType = prefs.getString(_tokenTypeKey) ?? 'Bearer';

    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': '$tokenType $token',
    };
  }

  /// Clears stored token data.
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_tokenTypeKey);
    await prefs.remove(_expiryKey);
  }
}
