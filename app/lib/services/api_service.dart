import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/country.dart';

/// Backend client. Point it at the FastAPI server with:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000   (Android emulator)
///   flutter run --dart-define=API_BASE_URL=http://192.168.x.x:8000 (real phone, same Wi-Fi)
const String _baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class ApiService {
  final http.Client _client = http.Client();

  Future<List<Country>> fetchCountries() async {
    final resp = await _client
        .get(Uri.parse('$_baseUrl/countries'))
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      throw ApiException('فشل تحميل الدول (${resp.statusCode})');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
    return data
        .map((e) => Country.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Verdict> verifyFact({
    required String countryCode,
    required String claim,
  }) async {
    final resp = await _client
        .post(
          Uri.parse('$_baseUrl/verify-fact'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'country': countryCode, 'claim': claim}),
        )
        .timeout(const Duration(seconds: 90));
    if (resp.statusCode != 200) {
      String detail = 'فشل التحقق (${resp.statusCode})';
      try {
        final body = jsonDecode(utf8.decode(resp.bodyBytes));
        if (body is Map && body['detail'] is String) {
          detail = body['detail'] as String;
        }
      } catch (_) {}
      throw ApiException(detail);
    }
    return Verdict.fromJson(
      jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>,
    );
  }
}
