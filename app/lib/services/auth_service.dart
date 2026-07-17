import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

/// The signed-in player as returned by `POST /api/auth/google` — profile +
/// the stats the backend provisioned.
class AuthUser {
  final String id;
  final String email;
  final String name;
  final String? picture;
  final int matchesPlayed;
  final int wins;
  final int totalPoints;

  const AuthUser({
    required this.id,
    required this.email,
    required this.name,
    this.picture,
    this.matchesPlayed = 0,
    this.wins = 0,
    this.totalPoints = 0,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        email: json['email'] as String,
        name: json['name'] as String,
        picture: json['picture'] as String?,
        matchesPlayed: (json['matches_played'] as num?)?.toInt() ?? 0,
        wins: (json['wins'] as num?)?.toInt() ?? 0,
        totalPoints: (json['total_points'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'picture': picture,
        'matches_played': matchesPlayed,
        'wins': wins,
        'total_points': totalPoints,
      };
}

enum AuthStatus { restoring, signedOut, signingIn, signedIn }

/// How a sign-in attempt ended — drives the screen's feedback snackbars.
enum SignInResult { success, cancelled, failed }

/// Google Sign-In → backend JWT session, persisted across restarts.
///
/// Flow: the Google popup yields an `idToken`; we POST it to
/// `/api/auth/google`; the backend verifies it with Google and returns OUR
/// application JWT + the player profile, which we cache in
/// `shared_preferences` so the session survives app restarts (the Google
/// token itself is used once and never stored).
///
/// Testability: [idTokenProvider] and [client] are injectable, so tests can
/// fake the Google popup and the network without any platform channels.
class AuthService extends ChangeNotifier {
  static const _prefsToken = 'auth_jwt';
  static const _prefsExpiry = 'auth_jwt_expiry';
  static const _prefsUser = 'auth_user';

  /// The backend's GOOGLE_CLIENT_ID (a *Web* OAuth client) — Google only
  /// puts an `idToken` audience we can verify server-side when the mobile
  /// sign-in names it as the serverClientId. Client IDs are public by design
  /// (they ship inside every APK), so the production value is safe as the
  /// baked-in default; override for another Google project with:
  ///   flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com
  static const _serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '572748761857-ghehmq2shdql97qgva170j7kp3i8ngb5.apps.googleusercontent.com',
  );

  final http.Client _client;
  final Future<String?> Function() _idTokenProvider;

  AuthStatus _status = AuthStatus.restoring;
  AuthUser? _user;
  String? _token;
  String _lastError = '';

  AuthService({
    http.Client? client,
    Future<String?> Function()? idTokenProvider,
  })  : _client = client ?? http.Client(),
        _idTokenProvider = idTokenProvider ?? _googleIdToken;

  AuthStatus get status => _status;
  AuthUser? get user => _user;
  String? get token => _token;
  bool get isSignedIn => _status == AuthStatus.signedIn;
  bool get isBusy => _status == AuthStatus.signingIn;

  /// Human-readable reason for the last [SignInResult.failed].
  String get lastError => _lastError;

  /// Real Google flow (overridden in tests). Returns null on user cancel.
  static Future<String?> _googleIdToken() async {
    final google = GoogleSignIn(
      scopes: const ['email'],
      serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
    );
    final account = await google.signIn();
    if (account == null) return null; // user dismissed the popup
    return (await account.authentication).idToken;
  }

  /// Load a persisted session. Call once at startup — until it completes,
  /// [status] is [AuthStatus.restoring].
  Future<void> restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_prefsToken);
      final expiry = prefs.getInt(_prefsExpiry) ?? 0;
      final userJson = prefs.getString(_prefsUser);
      // 60s of slack so we never restore a token that dies mid-request.
      final fresh =
          expiry > DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60;
      if (token != null && userJson != null && fresh) {
        _token = token;
        _user = AuthUser.fromJson(
            jsonDecode(userJson) as Map<String, dynamic>);
        _status = AuthStatus.signedIn;
      } else {
        _status = AuthStatus.signedOut;
      }
    } catch (_) {
      _status = AuthStatus.signedOut;
    }
    notifyListeners();
  }

  Future<SignInResult> signInWithGoogle() async {
    if (_status == AuthStatus.signingIn) return SignInResult.cancelled;
    _status = AuthStatus.signingIn;
    notifyListeners();

    // Step 1: the Google popup. Failures here are configuration problems
    // (SHA-1/package mismatch, Play Services), not server problems — report
    // them distinctly so they're debuggable.
    final String? idToken;
    try {
      idToken = await _idTokenProvider();
    } catch (_) {
      _lastError = 'فشل تسجيل الدخول بجوجل — اتأكد من خدمات Google وجرّب تاني';
      _status = AuthStatus.signedOut;
      notifyListeners();
      return SignInResult.failed;
    }
    if (idToken == null) {
      _status = AuthStatus.signedOut;
      notifyListeners();
      return SignInResult.cancelled;
    }

    // Step 2: exchange with our backend. Generous timeout: the Render free
    // tier sleeps after idle and a cold start can take ~a minute.
    try {
      final resp = await _client
          .post(
            Uri.parse('$apiBaseUrl/api/auth/google'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'idToken': idToken}),
          )
          .timeout(const Duration(seconds: 75));

      if (resp.statusCode != 200) {
        _lastError = _detailFrom(resp) ?? 'فشل تسجيل الدخول (${resp.statusCode})';
        _status = AuthStatus.signedOut;
        notifyListeners();
        return SignInResult.failed;
      }

      final body = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      _token = body['access_token'] as String;
      _user = AuthUser.fromJson(body['user'] as Map<String, dynamic>);
      await _persist(expiresAt: (body['expires_at'] as num).toInt());
      _status = AuthStatus.signedIn;
      notifyListeners();
      return SignInResult.success;
    } catch (e) {
      _lastError =
          'السيرفر بياخد وقته يصحى — استنى ثواني وجرّب تاني (أول محاولة بتصحّي السيرفر المجاني)';
      _status = AuthStatus.signedOut;
      notifyListeners();
      return SignInResult.failed;
    }
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn().signOut(); // best-effort; local session is the truth
    } catch (_) {}
    _token = null;
    _user = null;
    _status = AuthStatus.signedOut;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsToken);
      await prefs.remove(_prefsExpiry);
      await prefs.remove(_prefsUser);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _persist({required int expiresAt}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsToken, _token!);
    await prefs.setInt(_prefsExpiry, expiresAt);
    await prefs.setString(_prefsUser, jsonEncode(_user!.toJson()));
  }

  static String? _detailFrom(http.Response resp) {
    try {
      final body = jsonDecode(utf8.decode(resp.bodyBytes));
      if (body is Map && body['detail'] is String) return body['detail'] as String;
    } catch (_) {}
    return null;
  }
}
