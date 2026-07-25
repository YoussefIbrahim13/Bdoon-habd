import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_service.dart';

/// A person in the friends system (friend or pending sender).
class Friend {
  final String id;
  final String name;
  final String? picture;

  /// True when the friend has a live socket somewhere (invitable now).
  final bool online;

  const Friend(
      {required this.id, required this.name, this.picture, this.online = false});

  factory Friend.fromJson(Map<String, dynamic> json) => Friend(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'لاعب',
        picture: json['picture'] as String?,
        online: json['online'] as bool? ?? false,
      );
}

/// One incoming pending request (its id + who sent it).
class PendingRequest {
  final String requestId;
  final Friend sender;

  const PendingRequest({required this.requestId, required this.sender});

  factory PendingRequest.fromJson(Map<String, dynamic> json) => PendingRequest(
        requestId: json['request_id'] as String,
        sender: Friend.fromJson(json['sender'] as Map<String, dynamic>),
      );
}

/// REST client for `/api/friends`. Stateless; the app JWT is passed in per
/// call by the state layer.
class FriendshipService {
  final http.Client _client;

  FriendshipService({http.Client? client})
      : _client = client ?? http.Client();

  Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  /// Throws [FriendshipException] with the backend's Arabic detail on non-2xx.
  Never _fail(http.Response resp) {
    String detail = 'حصل خطأ (${resp.statusCode})';
    try {
      final body = jsonDecode(utf8.decode(resp.bodyBytes));
      if (body is Map && body['detail'] is String) {
        detail = body['detail'] as String;
      }
    } catch (_) {}
    throw FriendshipException(detail);
  }

  /// Returns the new relationship string (e.g. "pending_outgoing").
  Future<String> sendRequest(
      {required String token, required String receiverId}) async {
    final resp = await _client
        .post(Uri.parse('$apiBaseUrl/api/friends/request'),
            headers: _headers(token),
            body: jsonEncode({'receiver_id': receiverId}))
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) _fail(resp);
    return (jsonDecode(utf8.decode(resp.bodyBytes))
        as Map<String, dynamic>)['relationship'] as String;
  }

  Future<void> respond({
    required String token,
    required String requestId,
    required bool accept,
  }) async {
    final resp = await _client
        .post(Uri.parse('$apiBaseUrl/api/friends/respond'),
            headers: _headers(token),
            body: jsonEncode({
              'request_id': requestId,
              'action': accept ? 'ACCEPT' : 'REJECT',
            }))
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) _fail(resp);
  }

  Future<List<Friend>> friends({required String token}) async {
    final resp = await _client
        .get(Uri.parse('$apiBaseUrl/api/friends'), headers: _headers(token))
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) _fail(resp);
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
    return data
        .map((e) => Friend.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<PendingRequest>> pending({required String token}) async {
    final resp = await _client
        .get(Uri.parse('$apiBaseUrl/api/friends/pending'),
            headers: _headers(token))
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) _fail(resp);
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
    return data
        .map((e) => PendingRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

class FriendshipException implements Exception {
  final String message;
  FriendshipException(this.message);
  @override
  String toString() => message;
}
