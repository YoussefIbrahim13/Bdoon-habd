import 'country.dart';

/// One player as seen inside an online room.
class OnlinePlayer {
  final String id;
  final String name;
  final String? picture;
  final int score;
  final bool connected;

  const OnlinePlayer({
    required this.id,
    required this.name,
    this.picture,
    this.score = 0,
    this.connected = true,
  });

  factory OnlinePlayer.fromJson(Map<String, dynamic> json) => OnlinePlayer(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        picture: json['picture'] as String?,
        score: (json['score'] as num?)?.toInt() ?? 0,
        connected: json['connected'] as bool? ?? true,
      );

  OnlinePlayer copyWith({int? score, bool? connected}) => OnlinePlayer(
        id: id,
        name: name,
        picture: picture,
        score: score ?? this.score,
        connected: connected ?? this.connected,
      );
}

/// The AI's advisory verdict on a submitted fact.
class OnlineVerdict {
  final String verdict; // "true" | "false" | "unreliable"
  final String explanation;

  const OnlineVerdict({required this.verdict, required this.explanation});

  factory OnlineVerdict.fromJson(Map<String, dynamic> json) => OnlineVerdict(
        verdict: json['verdict'] as String? ?? 'unreliable',
        explanation: json['explanation'] as String? ?? '',
      );
}

/// Typed mirror of the server's WebSocket protocol (see backend
/// app/websocket.py). Every inbound JSON message parses into exactly one of
/// these; unknown event types fall through to [UnknownEvent] so a newer
/// server can't crash an older client.
sealed class GameEvent {
  const GameEvent();

  static GameEvent parse(Map<String, dynamic> json) {
    switch (json['event'] as String?) {
      case 'room_state':
        return RoomSnapshot(
          roomCode: json['room_code'] as String,
          hostId: json['host_id'] as String,
          phase: json['phase'] as String,
          totalRounds: (json['total_rounds'] as num?)?.toInt() ?? 5,
          difficulty: json['difficulty'] as String? ?? 'progressive',
          roundNumber: (json['round_number'] as num?)?.toInt() ?? 0,
          currentPlayerId: json['current_player_id'] as String?,
          country: json['current_country'] == null
              ? null
              : Country.fromJson(
                  json['current_country'] as Map<String, dynamic>),
          fact: json['current_fact'] as String?,
          verdict: json['ai_verdict'] == null
              ? null
              : OnlineVerdict.fromJson(
                  json['ai_verdict'] as Map<String, dynamic>),
          players: [
            for (final p in json['players'] as List<dynamic>? ?? [])
              OnlinePlayer.fromJson(p as Map<String, dynamic>),
          ],
        );
      case 'player_joined':
        return PlayerJoined(
          player:
              OnlinePlayer.fromJson(json['player'] as Map<String, dynamic>),
          reconnected: json['reconnected'] as bool? ?? false,
        );
      case 'player_left':
        return PlayerLeft(
          player:
              OnlinePlayer.fromJson(json['player'] as Map<String, dynamic>),
        );
      case 'host_changed':
        return HostChanged(hostId: json['host_id'] as String);
      case 'game_started':
        return GameStarted(
          turnOrder: [...(json['turn_order'] as List<dynamic>).cast<String>()],
          totalRounds: (json['total_rounds'] as num?)?.toInt() ?? 5,
          difficulty: json['difficulty'] as String? ?? 'progressive',
        );
      case 'settings_updated':
        return SettingsUpdated(
          totalRounds: (json['total_rounds'] as num).toInt(),
          difficulty: json['difficulty'] as String? ?? 'progressive',
        );
      case 'next_turn':
        return NextTurn(
          round: (json['round'] as num).toInt(),
          totalRounds: (json['total_rounds'] as num?)?.toInt() ?? 0,
          playerId: json['player_id'] as String,
          country: Country.fromJson(
              (json['country'] as Map).cast<String, dynamic>()),
        );
      case 'fact_submitted':
        return FactSubmitted(
          playerId: json['player_id'] as String,
          fact: json['fact'] as String,
        );
      case 'ai_verdict':
        return AiVerdictEvent(
          verdict: OnlineVerdict(
            verdict: json['verdict'] as String? ?? 'unreliable',
            explanation: json['explanation'] as String? ?? '',
          ),
          votesNeeded: (json['votes_needed'] as num?)?.toInt() ?? 0,
        );
      case 'voting_update':
        return VotingUpdate(
          votesCast: (json['votes_cast'] as num).toInt(),
          votesNeeded: (json['votes_needed'] as num).toInt(),
        );
      case 'round_ended':
        final votes = (json['votes'] as Map?)?.cast<String, dynamic>();
        return RoundEnded(
          playerId: json['player_id'] as String,
          awarded: json['awarded'] as bool,
          fact: json['fact'] as String? ?? '',
          trueVotes: (votes?['true'] as num?)?.toInt() ?? 0,
          falseVotes: (votes?['false'] as num?)?.toInt() ?? 0,
          scores: _scores(json['scores']),
        );
      case 'game_over':
        return GameOver(
          winner: json['winner'] == null
              ? null
              : OnlinePlayer.fromJson(
                  (json['winner'] as Map).cast<String, dynamic>()),
          reason: json['reason'] as String?,
          scores: _scores(json['scores']),
        );
      case 'error':
        return ServerError(detail: json['detail'] as String? ?? 'خطأ غير معروف');
      default:
        return UnknownEvent(raw: json);
    }
  }

  /// Tolerant score-map parsing (raw JSON maps arrive untyped).
  static Map<String, int> _scores(Object? raw) => {
        for (final e in ((raw as Map?) ?? const {}).entries)
          e.key as String: (e.value as num).toInt(),
      };
}

class RoomSnapshot extends GameEvent {
  final String roomCode;
  final String hostId;
  final String phase;
  final int totalRounds;
  final String difficulty;
  final int roundNumber;
  final String? currentPlayerId;
  final Country? country;
  final String? fact;
  final OnlineVerdict? verdict;
  final List<OnlinePlayer> players;

  const RoomSnapshot({
    required this.roomCode,
    required this.hostId,
    required this.phase,
    required this.totalRounds,
    required this.difficulty,
    required this.roundNumber,
    required this.currentPlayerId,
    required this.country,
    required this.fact,
    required this.verdict,
    required this.players,
  });
}

class PlayerJoined extends GameEvent {
  final OnlinePlayer player;
  final bool reconnected;
  const PlayerJoined({required this.player, required this.reconnected});
}

class PlayerLeft extends GameEvent {
  final OnlinePlayer player;
  const PlayerLeft({required this.player});
}

class HostChanged extends GameEvent {
  final String hostId;
  const HostChanged({required this.hostId});
}

class GameStarted extends GameEvent {
  final List<String> turnOrder;
  final int totalRounds;
  final String difficulty;
  const GameStarted({
    required this.turnOrder,
    required this.totalRounds,
    required this.difficulty,
  });
}

/// Host changed the lobby knobs — every client's UI syncs from this.
class SettingsUpdated extends GameEvent {
  final int totalRounds;
  final String difficulty;
  const SettingsUpdated(
      {required this.totalRounds, required this.difficulty});
}

class NextTurn extends GameEvent {
  final int round;
  final int totalRounds;
  final String playerId;
  final Country country;
  const NextTurn({
    required this.round,
    required this.totalRounds,
    required this.playerId,
    required this.country,
  });
}

class FactSubmitted extends GameEvent {
  final String playerId;
  final String fact;
  const FactSubmitted({required this.playerId, required this.fact});
}

class AiVerdictEvent extends GameEvent {
  final OnlineVerdict verdict;
  final int votesNeeded;
  const AiVerdictEvent({required this.verdict, required this.votesNeeded});
}

class VotingUpdate extends GameEvent {
  final int votesCast;
  final int votesNeeded;
  const VotingUpdate({required this.votesCast, required this.votesNeeded});
}

class RoundEnded extends GameEvent {
  final String playerId;
  final bool awarded;
  final String fact;
  final int trueVotes;
  final int falseVotes;
  final Map<String, int> scores;

  const RoundEnded({
    required this.playerId,
    required this.awarded,
    required this.fact,
    required this.trueVotes,
    required this.falseVotes,
    required this.scores,
  });
}

class GameOver extends GameEvent {
  final OnlinePlayer? winner;
  final String? reason;
  final Map<String, int> scores;
  const GameOver(
      {required this.winner, required this.reason, required this.scores});
}

class ServerError extends GameEvent {
  final String detail;
  const ServerError({required this.detail});
}

/// Synthesized locally by the socket service when the connection dies —
/// never sent by the server. [code] is the WS close code (4401 unauthorized,
/// 4404 room not found, 4409 room full, or a transport-level code).
class SocketClosed extends GameEvent {
  final int? code;
  const SocketClosed({this.code});
}

class UnknownEvent extends GameEvent {
  final Map<String, dynamic> raw;
  const UnknownEvent({required this.raw});
}
