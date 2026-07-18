import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:el_hakem/models/game_events.dart';
import 'package:el_hakem/services/game_socket_service.dart';
import 'package:el_hakem/state/game_room_state.dart';

/// Fake socket: test drives the inbound stream, records outbound actions.
class FakeConnection implements GameSocketConnection {
  final controller = StreamController<GameEvent>.broadcast();
  final sent = <Map<String, dynamic>>[];
  bool closed = false;

  @override
  Stream<GameEvent> get events => controller.stream;

  @override
  void send(Map<String, dynamic> action) => sent.add(action);

  @override
  Future<void> close() async {
    closed = true;
    if (!controller.isClosed) {
      controller.add(const SocketClosed());
      await controller.close();
    }
  }
}

class FakeService extends GameWebSocketService {
  final FakeConnection connection;
  String? requestedRoom;

  FakeService(this.connection)
      : super(client: MockClient((_) async => http.Response('{}', 500)));

  @override
  GameSocketConnection connect(
      {required String roomCode, required String token}) {
    requestedRoom = roomCode;
    return connection;
  }
}

Map<String, dynamic> _country() =>
    {'code': 'EG', 'name_en': 'Egypt', 'name_ar': 'مصر', 'flag_png': null};

void main() {
  late FakeConnection conn;
  late GameRoomState room;

  setUp(() {
    conn = FakeConnection();
    room = GameRoomState(
        myId: 'me', token: 'jwt', service: FakeService(conn));
    room.join('123456');
  });

  tearDown(() => room.dispose());

  Future<void> emit(Map<String, dynamic> json) async {
    conn.controller.add(GameEvent.parse(json));
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> emitLobbySnapshot() => emit({
        'event': 'room_state',
        'room_code': '123456',
        'host_id': 'me',
        'phase': 'lobby',
        'total_rounds': 2,
        'difficulty': 'easy',
        'round_number': 0,
        'current_player_id': null,
        'current_country': null,
        'current_fact': null,
        'ai_verdict': null,
        'votes_cast': 0,
        'players': [
          {'id': 'me', 'name': 'Me', 'picture': null, 'score': 0,
           'connected': true},
        ],
      });

  test('snapshot populates the lobby and host flag', () async {
    expect(room.phase, OnlinePhase.connecting);
    await emitLobbySnapshot();
    expect(room.phase, OnlinePhase.lobby);
    expect(room.iAmHost, isTrue);
    expect(room.totalRounds, 2);
    expect(room.difficulty, 'easy');
    expect(room.players.single.id, 'me');
  });

  test('settings sync: host sends the action, broadcast mutates state',
      () async {
    await emitLobbySnapshot();
    room.updateSettings(totalRounds: 10, difficulty: 'hard');
    expect(conn.sent.last, {
      'action': 'update_settings',
      'total_rounds': 10,
      'difficulty': 'hard',
    });
    // Local state only changes when the server confirms:
    expect(room.totalRounds, 2);
    await emit({'event': 'settings_updated', 'total_rounds': 10,
        'difficulty': 'hard'});
    expect(room.totalRounds, 10);
    expect(room.difficulty, 'hard');
  });

  test('full round: turn → fact → verdict → votes → scores', () async {
    await emitLobbySnapshot();
    await emit({'event': 'player_joined', 'reconnected': false,
        'player': {'id': 'p2', 'name': 'Guest', 'picture': null,
                   'score': 0, 'connected': true}});
    expect(room.players.length, 2);

    room.startGame();
    expect(conn.sent.last, {'action': 'start_game'});

    await emit({'event': 'game_started', 'turn_order': ['me', 'p2'],
        'total_rounds': 2, 'difficulty': 'easy'});
    await emit({'event': 'next_turn', 'round': 1, 'total_rounds': 2,
        'player_id': 'me', 'country': _country()});
    expect(room.phase, OnlinePhase.awaitingFact);
    expect(room.isMyTurn, isTrue);
    expect(room.country!.code, 'EG');

    room.submitFact('عاصمتها القاهرة');
    expect(conn.sent.last,
        {'action': 'submit_fact', 'text': 'عاصمتها القاهرة'});
    await emit({'event': 'fact_submitted', 'player_id': 'me',
        'fact': 'عاصمتها القاهرة'});
    expect(room.phase, OnlinePhase.evaluating);

    await emit({'event': 'ai_verdict', 'verdict': 'true',
        'explanation': 'صح', 'votes_needed': 2});
    expect(room.phase, OnlinePhase.awaitingVotes);
    expect(room.verdict!.verdict, 'true');
    // Speaker can never vote on their own fact.
    expect(room.isMyTurn, isTrue);
    expect(room.canVote, isFalse);

    room.submitVote(true);
    expect(room.myVoteCast, isTrue);
    expect(conn.sent.last, {'action': 'submit_vote', 'accept': true});
    room.submitVote(true); // locked after first vote
    expect(conn.sent.where((m) => m['action'] == 'submit_vote').length, 1);

    await emit({'event': 'voting_update', 'votes_cast': 1,
        'votes_needed': 2});
    expect(room.votesCast, 1);

    await emit({'event': 'round_ended', 'player_id': 'me', 'awarded': true,
        'fact': 'عاصمتها القاهرة', 'votes': {'true': 3, 'false': 0},
        'scores': {'me': 1, 'p2': 0}});
    expect(room.roundsCompleted, 1);
    expect(room.lastRoundResult!.awarded, isTrue);
    expect(room.playerById('me')!.score, 1);

    // Next round resets per-turn state, including the vote lock; as a
    // non-speaker this round, voting is now open to me.
    await emit({'event': 'next_turn', 'round': 2, 'total_rounds': 2,
        'player_id': 'p2', 'country': _country()});
    expect(room.phase, OnlinePhase.awaitingFact);
    expect(room.isMyTurn, isFalse);
    expect(room.myVoteCast, isFalse);
    expect(room.verdict, isNull);
    await emit({'event': 'ai_verdict', 'verdict': 'false',
        'explanation': '', 'votes_needed': 1});
    expect(room.canVote, isTrue);
  });

  test('game over records the winner and final scores', () async {
    await emitLobbySnapshot();
    await emit({'event': 'game_over',
        'winner': {'id': 'me', 'name': 'Me', 'picture': null, 'score': 2,
                   'connected': true},
        'scores': {'me': 2}});
    expect(room.phase, OnlinePhase.gameOver);
    expect(room.winner!.id, 'me');
    expect(room.playerById('me')!.score, 2);
  });

  test('server rule errors bump the counter and unlock voting', () async {
    await emitLobbySnapshot();
    room.submitVote(true);
    expect(room.myVoteCast, isTrue);
    await emit({'event': 'error', 'detail': 'مش وقت التصويت دلوقتي.'});
    expect(room.errorsSeen, 1);
    expect(room.lastError, contains('التصويت'));
    expect(room.myVoteCast, isFalse); // rejection re-opens the buttons
  });

  test('close codes map to readable disconnect reasons', () async {
    await emitLobbySnapshot();
    conn.controller.add(const SocketClosed(code: 4404));
    await Future<void>.delayed(Duration.zero);
    expect(room.phase, OnlinePhase.disconnected);
    expect(room.disconnectReason, contains('موجودة'));
  });

  test('disconnect after game over keeps the podium visible', () async {
    await emitLobbySnapshot();
    await emit({'event': 'game_over', 'winner': null, 'scores': {}});
    conn.controller.add(const SocketClosed(code: 1000));
    await Future<void>.delayed(Duration.zero);
    expect(room.phase, OnlinePhase.gameOver); // not overwritten
  });

  test('dispose closes the socket', () async {
    await emitLobbySnapshot();
    room.dispose();
    expect(conn.closed, isTrue);
    // Guard the tearDown double-dispose.
    room = GameRoomState(
        myId: 'me', token: 'jwt', service: FakeService(FakeConnection()));
  });
}
