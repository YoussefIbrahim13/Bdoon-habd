import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:el_hakem/services/auth_service.dart';
import 'package:el_hakem/services/friendship_service.dart';
import 'package:el_hakem/state/friendship_state.dart';

/// Signed-in AuthService with a fixed token (no Google flow).
Future<AuthService> _signedInAuth() async {
  SharedPreferences.setMockInitialValues({
    'auth_jwt': 'jwt-token',
    'auth_jwt_expiry':
        DateTime.now().millisecondsSinceEpoch ~/ 1000 + 7 * 24 * 3600,
    'auth_user': jsonEncode({
      'id': 'me', 'email': 'me@x.com', 'name': 'Me', 'picture': null,
      'matches_played': 0, 'wins': 0, 'total_points': 0,
    }),
  });
  final auth = AuthService(idTokenProvider: () async => null);
  await auth.restoreSession();
  return auth;
}

FriendshipService _service(MockClientHandler handler) =>
    FriendshipService(client: MockClient(handler));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('refresh loads friends + pending and marks relationships', () async {
    final auth = await _signedInAuth();
    final state = FriendshipState(
      auth: auth,
      service: _service((req) async {
        if (req.url.path == '/api/friends') {
          return http.Response(
            jsonEncode([
              {'id': 'bob', 'name': 'Bob', 'picture': null},
            ]),
            200,
          );
        }
        if (req.url.path == '/api/friends/pending') {
          return http.Response(
            jsonEncode([
              {'request_id': 'r1',
               'sender': {'id': 'carol', 'name': 'Carol', 'picture': null}},
            ]),
            200,
          );
        }
        return http.Response('[]', 200);
      }),
    );

    await state.refresh();
    expect(state.friends.single.id, 'bob');
    expect(state.relationshipWith('bob'), FriendState.friends);
    expect(state.pendingCount, 1);
    expect(state.relationshipWith('stranger'), FriendState.none);
  });

  test('sendRequest goes none → sending → pendingOutgoing', () async {
    final auth = await _signedInAuth();
    Map<String, dynamic>? sent;
    final state = FriendshipState(
      auth: auth,
      service: _service((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
            jsonEncode({'relationship': 'pending_outgoing',
                        'request_id': 'r9'}), 200);
      }),
    );

    final future = state.sendRequest('bob');
    expect(state.relationshipWith('bob'), FriendState.sending);
    await future;
    expect(sent!['receiver_id'], 'bob');
    expect(state.relationshipWith('bob'), FriendState.pendingOutgoing);
  });

  test('sendRequest reconciles to friends on "already friends" 409', () async {
    final auth = await _signedInAuth();
    final state = FriendshipState(
      auth: auth,
      service: _service((req) async => http.Response(
            jsonEncode({'detail': 'انتوا أصحاب بالفعل 🤝'}),
            409,
            // Arabic body → must declare UTF-8 or http encodes it as latin1.
            headers: {'content-type': 'application/json; charset=utf-8'},
          )),
    );
    await state.sendRequest('bob');
    expect(state.relationshipWith('bob'), FriendState.friends);
    expect(state.errorsSeen, 1);
  });

  test('accept removes the pending row and adds a friend', () async {
    final auth = await _signedInAuth();
    final state = FriendshipState(
      auth: auth,
      service: _service((req) async {
        if (req.url.path == '/api/friends/pending') {
          return http.Response(
            jsonEncode([
              {'request_id': 'r1',
               'sender': {'id': 'carol', 'name': 'Carol', 'picture': null}},
            ]),
            200,
          );
        }
        if (req.url.path == '/api/friends') return http.Response('[]', 200);
        return http.Response('{}', 200); // respond
      }),
    );
    await state.refresh();
    expect(state.pendingCount, 1);

    await state.respond('r1', accept: true);
    expect(state.pendingCount, 0);
    expect(state.relationshipWith('carol'), FriendState.friends);
    expect(state.friends.any((f) => f.id == 'carol'), isTrue);
  });

  test('respond rolls back the pending row on network failure', () async {
    final auth = await _signedInAuth();
    var respondCall = false;
    final state = FriendshipState(
      auth: auth,
      service: _service((req) async {
        if (req.url.path == '/api/friends/pending') {
          return http.Response(
            jsonEncode([
              {'request_id': 'r1',
               'sender': {'id': 'carol', 'name': 'Carol', 'picture': null}},
            ]),
            200,
          );
        }
        if (req.url.path == '/api/friends') return http.Response('[]', 200);
        respondCall = true;
        return http.Response('{"detail":"boom"}', 500);
      }),
    );
    await state.refresh();
    await state.respond('r1', accept: false);
    expect(respondCall, isTrue);
    expect(state.pendingCount, 1); // rolled back
    expect(state.errorsSeen, 1);
  });

  test('onIncomingRequest adds a live request without a refetch', () async {
    final auth = await _signedInAuth();
    final state = FriendshipState(auth: auth, service: _service((_) async =>
        http.Response('[]', 200)));
    state.onIncomingRequest(const PendingRequest(
      requestId: 'r5',
      sender: Friend(id: 'dave', name: 'Dave'),
    ));
    expect(state.pendingCount, 1);
    // Idempotent: the same push twice doesn't double-add.
    state.onIncomingRequest(const PendingRequest(
      requestId: 'r5',
      sender: Friend(id: 'dave', name: 'Dave'),
    ));
    expect(state.pendingCount, 1);
  });
}
