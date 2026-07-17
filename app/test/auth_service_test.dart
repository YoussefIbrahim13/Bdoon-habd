import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:el_hakem/services/auth_service.dart';

Map<String, dynamic> _userJson() => {
      'id': 'player-1',
      'email': 'p@example.com',
      'name': 'Test Player',
      'picture': null,
      'matches_played': 0,
      'wins': 0,
      'total_points': 0,
    };

int _freshExpiry() =>
    DateTime.now().millisecondsSinceEpoch ~/ 1000 + 7 * 24 * 3600;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('successful sign-in stores the JWT + user and goes signedIn',
      () async {
    late Map<String, dynamic> sentBody;
    final auth = AuthService(
      idTokenProvider: () async => 'google-id-token',
      client: MockClient((req) async {
        expect(req.url.path, '/api/auth/google');
        sentBody = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'access_token': 'app-jwt-123',
            'token_type': 'bearer',
            'expires_at': _freshExpiry(),
            'user': _userJson(),
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await auth.signInWithGoogle();
    expect(result, SignInResult.success);
    expect(sentBody['idToken'], 'google-id-token');
    expect(auth.isSignedIn, isTrue);
    expect(auth.token, 'app-jwt-123');
    expect(auth.user!.name, 'Test Player');

    // Persisted: a fresh service restores the same session.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auth_jwt'), 'app-jwt-123');
    final restored = AuthService(idTokenProvider: () async => null);
    await restored.restoreSession();
    expect(restored.isSignedIn, isTrue);
    expect(restored.user!.id, 'player-1');
  });

  test('cancelled Google popup → cancelled, stays signed out', () async {
    final auth = AuthService(
      idTokenProvider: () async => null,
      client: MockClient((_) async => http.Response('unreachable', 500)),
    );
    expect(await auth.signInWithGoogle(), SignInResult.cancelled);
    expect(auth.status, AuthStatus.signedOut);
  });

  test('backend rejection surfaces its Arabic-ready detail', () async {
    final auth = AuthService(
      idTokenProvider: () async => 'bad-token',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'detail': 'Invalid or expired Google token.'}),
          401,
        ),
      ),
    );
    expect(await auth.signInWithGoogle(), SignInResult.failed);
    expect(auth.lastError, 'Invalid or expired Google token.');
    expect(auth.isSignedIn, isFalse);
  });

  test('expired persisted session restores as signed out', () async {
    SharedPreferences.setMockInitialValues({
      'auth_jwt': 'stale-jwt',
      'auth_jwt_expiry': DateTime.now().millisecondsSinceEpoch ~/ 1000 - 10,
      'auth_user': jsonEncode(_userJson()),
    });
    final auth = AuthService(idTokenProvider: () async => null);
    await auth.restoreSession();
    expect(auth.status, AuthStatus.signedOut);
  });

  test('signOut clears the persisted session', () async {
    SharedPreferences.setMockInitialValues({
      'auth_jwt': 'jwt',
      'auth_jwt_expiry': _freshExpiry(),
      'auth_user': jsonEncode(_userJson()),
    });
    final auth = AuthService(idTokenProvider: () async => null);
    await auth.restoreSession();
    expect(auth.isSignedIn, isTrue);

    await auth.signOut();
    expect(auth.status, AuthStatus.signedOut);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auth_jwt'), isNull);
  });
}
