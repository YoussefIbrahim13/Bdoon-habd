import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/game_events.dart';
import 'api_service.dart';

/// Abstraction over one live room socket, so the state layer (and tests)
/// never touch WebSocketChannel directly.
abstract class GameSocketConnection {
  /// Parsed server events. Ends with a [SocketClosed] exactly once, whether
  /// the server closed us (app-level 44xx codes), the network dropped, or
  /// [close] was called locally.
  Stream<GameEvent> get events;

  void send(Map<String, dynamic> action);

  Future<void> close();
}

/// Creates room-socket connections and reserves rooms over REST.
///
/// The stored app JWT rides the WS handshake as a `?token=` query parameter
/// (WebSocket clients cannot set HTTP headers).
class GameWebSocketService {
  final http.Client _client;

  GameWebSocketService({http.Client? client})
      : _client = client ?? http.Client();

  /// wss:// twin of the REST base URL.
  static String get wsBaseUrl => apiBaseUrl
      .replaceFirst('https://', 'wss://')
      .replaceFirst('http://', 'ws://');

  /// `POST /api/rooms` — reserve a room; returns its 6-digit code.
  /// Generous timeout: the free-tier server may be cold-starting.
  Future<String> createRoom({
    required String token,
    int targetScore = 5,
  }) async {
    final resp = await _client
        .post(
          Uri.parse('$apiBaseUrl/api/rooms'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'target_score': targetScore}),
        )
        .timeout(const Duration(seconds: 75));
    if (resp.statusCode != 200) {
      throw Exception('فشل إنشاء الأوضة (${resp.statusCode})');
    }
    final body = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    return body['room_code'] as String;
  }

  /// Open the room socket. Returns immediately; failures surface on the
  /// event stream (as [ServerError] and/or [SocketClosed]).
  GameSocketConnection connect({
    required String roomCode,
    required String token,
  }) {
    final uri = Uri.parse('$wsBaseUrl/ws/game/$roomCode?token=$token');
    return _ChannelConnection(WebSocketChannel.connect(uri));
  }
}

class _ChannelConnection implements GameSocketConnection {
  final WebSocketChannel _channel;
  final _controller = StreamController<GameEvent>.broadcast();
  bool _closedEmitted = false;

  _ChannelConnection(this._channel) {
    _channel.stream.listen(
      (raw) {
        try {
          final json = jsonDecode(raw as String) as Map<String, dynamic>;
          _controller.add(GameEvent.parse(json));
        } catch (_) {
          // A malformed frame must never kill the whole session.
        }
      },
      onError: (Object _) => _emitClosed(),
      onDone: _emitClosed,
      cancelOnError: false,
    );
  }

  void _emitClosed() {
    if (_closedEmitted || _controller.isClosed) return;
    _closedEmitted = true;
    _controller.add(SocketClosed(code: _channel.closeCode));
    _controller.close();
  }

  @override
  Stream<GameEvent> get events => _controller.stream;

  @override
  void send(Map<String, dynamic> action) =>
      _channel.sink.add(jsonEncode(action));

  @override
  Future<void> close() async {
    await _channel.sink.close();
    _emitClosed();
  }
}
