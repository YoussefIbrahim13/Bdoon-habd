import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/country.dart';
import '../models/game_events.dart';
import '../services/game_socket_service.dart';

/// Client mirror of the server's room state machine, plus connection states.
enum OnlinePhase {
  connecting,
  lobby,
  awaitingFact,
  evaluating,
  awaitingVotes,
  gameOver,
  disconnected,
}

/// One resolved round, kept for the UI's one-shot result banner.
class RoundResult {
  final String playerId;
  final bool awarded;
  final String fact;
  final int trueVotes;
  final int falseVotes;

  const RoundResult({
    required this.playerId,
    required this.awarded,
    required this.fact,
    required this.trueVotes,
    required this.falseVotes,
  });
}

/// Reactive room state driven entirely by server events — a reducer over
/// [GameEvent]s. All game truth lives on the server; this class only mirrors
/// it, records one-shot feedback counters for the UI, and sends actions.
///
/// Owns the socket: create one instance per GameRoomScreen and let the
/// provider dispose it — dispose closes the channel and cancels the
/// subscription, so leaving the screen always cleans up the connection.
class GameRoomState extends ChangeNotifier {
  final String myId;
  final String token;
  final GameWebSocketService _service;

  GameSocketConnection? _conn;
  StreamSubscription<GameEvent>? _sub;
  bool _disposed = false;

  OnlinePhase phase = OnlinePhase.connecting;
  String roomCode = '';
  String hostId = '';
  int totalRounds = 5;
  String difficulty = 'progressive';
  int roundNumber = 0;
  List<OnlinePlayer> players = [];
  String? currentPlayerId;
  Country? country;
  String? submittedFact;
  OnlineVerdict? verdict;
  int votesCast = 0;
  int votesNeeded = 0;
  bool myVoteCast = false;
  OnlinePlayer? winner;
  String? gameOverReason;

  /// Server-authoritative turn clock: the moment the current speaker's time
  /// runs out (null outside AWAITING_FACT). The UI animates toward it
  /// locally; the SERVER decides the actual timeout.
  DateTime? turnDeadline;
  int turnTotalSeconds = 30;

  /// One-shot UI feedback: bump counters + payloads the screen listens to.
  RoundResult? lastRoundResult;
  int roundsCompleted = 0;
  String? lastTimedOutPlayerId;
  int timeoutsSeen = 0;
  String lastError = '';
  int errorsSeen = 0;

  /// Human-readable reason once [phase] is [OnlinePhase.disconnected].
  String disconnectReason = '';

  GameRoomState({
    required this.myId,
    required this.token,
    GameWebSocketService? service,
  }) : _service = service ?? GameWebSocketService();

  bool get iAmHost => myId == hostId;
  bool get isMyTurn => currentPlayerId == myId;

  /// Self-voting is server-blocked; mirror it so the UI hides the buttons.
  bool get canVote =>
      phase == OnlinePhase.awaitingVotes && !isMyTurn && !myVoteCast;
  OnlinePlayer? playerById(String? id) =>
      players.where((p) => p.id == id).firstOrNull;
  OnlinePlayer? get currentPlayer => playerById(currentPlayerId);

  // -- Connection lifecycle ------------------------------------------------

  /// Reserve a fresh room, then join it. Returns the room code.
  Future<String> createAndJoin({
    int totalRounds = 5,
    String difficulty = 'progressive',
  }) async {
    final code = await _service.createRoom(
        token: token, totalRounds: totalRounds, difficulty: difficulty);
    join(code);
    return code;
  }

  /// Open the socket to an existing room and start reducing its events.
  void join(String code) {
    roomCode = code;
    phase = OnlinePhase.connecting;
    _notify();
    _conn = _service.connect(roomCode: code, token: token);
    _sub = _conn!.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _conn?.close();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // -- Outbound actions ----------------------------------------------------

  void startGame() => _conn?.send({'action': 'start_game'});

  /// Host-only lobby knobs; the server validates and broadcasts
  /// `settings_updated`, which is what actually mutates local state.
  void updateSettings({int? totalRounds, String? difficulty}) =>
      _conn?.send({
        'action': 'update_settings',
        'total_rounds': ?totalRounds,
        'difficulty': ?difficulty,
      });

  void submitFact(String text) =>
      _conn?.send({'action': 'submit_fact', 'text': text});

  void submitVote(bool accept) {
    if (myVoteCast) return;
    myVoteCast = true; // optimistic; a server rejection re-opens via error
    _conn?.send({'action': 'submit_vote', 'accept': accept});
    _notify();
  }

  // -- Event reducer -------------------------------------------------------

  void _onEvent(GameEvent event) {
    switch (event) {
      case RoomSnapshot():
        _applySnapshot(event);
      case PlayerJoined(:final player):
        players = [
          ...players.where((p) => p.id != player.id),
          player,
        ];
      case PlayerLeft(:final player):
        if (phase == OnlinePhase.lobby) {
          players = [...players.where((p) => p.id != player.id)];
        } else {
          players = [
            for (final p in players)
              p.id == player.id ? p.copyWith(connected: false) : p,
          ];
        }
      case HostChanged(:final hostId):
        this.hostId = hostId;
      case GameStarted(:final totalRounds, :final difficulty):
        this.totalRounds = totalRounds;
        this.difficulty = difficulty;
      case SettingsUpdated(:final totalRounds, :final difficulty):
        this.totalRounds = totalRounds;
        this.difficulty = difficulty;
      case NextTurn(:final round, :final playerId, :final country,
            :final turnSeconds):
        roundNumber = round;
        currentPlayerId = playerId;
        this.country = country;
        submittedFact = null;
        verdict = null;
        votesCast = 0;
        votesNeeded = 0;
        myVoteCast = false;
        turnTotalSeconds = turnSeconds;
        turnDeadline = DateTime.now().add(Duration(seconds: turnSeconds));
        phase = OnlinePhase.awaitingFact;
      case FactSubmitted(:final fact):
        submittedFact = fact;
        turnDeadline = null; // the fact beat the clock
        phase = OnlinePhase.evaluating;
      case TurnTimedOut(:final playerId):
        lastTimedOutPlayerId = playerId;
        timeoutsSeen++;
        turnDeadline = null;
      case AiVerdictEvent(:final verdict, :final votesNeeded):
        this.verdict = verdict;
        this.votesNeeded = votesNeeded;
        phase = OnlinePhase.awaitingVotes;
      case VotingUpdate(:final votesCast, :final votesNeeded):
        this.votesCast = votesCast;
        this.votesNeeded = votesNeeded;
      case RoundEnded():
        lastRoundResult = RoundResult(
          playerId: event.playerId,
          awarded: event.awarded,
          fact: event.fact,
          trueVotes: event.trueVotes,
          falseVotes: event.falseVotes,
        );
        roundsCompleted++;
        _applyScores(event.scores);
      case GameOver(:final winner, :final reason, :final scores):
        this.winner = winner;
        gameOverReason = reason;
        _applyScores(scores);
        phase = OnlinePhase.gameOver;
      case ServerError(:final detail):
        lastError = detail;
        errorsSeen++;
        myVoteCast = false; // a rejected vote must not lock the buttons
      case SocketClosed(:final code):
        if (phase != OnlinePhase.gameOver) {
          phase = OnlinePhase.disconnected;
          disconnectReason = switch (code) {
            4401 => 'الجلسة انتهت — سجل دخولك تاني.',
            4404 => 'الأوضة دي مش موجودة — اتأكد من الكود.',
            4409 => lastError.isNotEmpty ? lastError : 'الأوضة كاملة العدد.',
            _ => 'الاتصال بالسيرفر اتقطع.',
          };
        }
      case UnknownEvent():
        break; // forward-compatibility: ignore what we don't know
    }
    _notify();
  }

  void _applySnapshot(RoomSnapshot snap) {
    roomCode = snap.roomCode;
    hostId = snap.hostId;
    totalRounds = snap.totalRounds;
    difficulty = snap.difficulty;
    roundNumber = snap.roundNumber;
    turnTotalSeconds = snap.turnSeconds;
    turnDeadline = snap.turnSecondsLeft == null
        ? null
        : DateTime.now().add(Duration(seconds: snap.turnSecondsLeft!));
    currentPlayerId = snap.currentPlayerId;
    country = snap.country;
    submittedFact = snap.fact;
    verdict = snap.verdict;
    players = snap.players;
    phase = switch (snap.phase) {
      'lobby' => OnlinePhase.lobby,
      'awaiting_fact' => OnlinePhase.awaitingFact,
      'evaluating' => OnlinePhase.evaluating,
      'awaiting_votes' => OnlinePhase.awaitingVotes,
      'finished' => OnlinePhase.gameOver,
      _ => OnlinePhase.lobby,
    };
  }

  void _applyScores(Map<String, int> scores) {
    players = [
      for (final p in players) p.copyWith(score: scores[p.id] ?? p.score),
    ];
  }
}
