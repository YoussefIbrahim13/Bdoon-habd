import 'package:flutter/foundation.dart';

import '../services/auth_service.dart';
import '../services/friendship_service.dart';

/// Per-player relationship as the UI needs it for the add-friend button.
enum FriendState { none, pendingOutgoing, friends, sending }

/// App-wide friends state: the accepted list, incoming pending requests, and
/// a per-player relationship map that drives the add-friend button on the
/// podium. Backed by [FriendshipService]; reads the JWT from [AuthService].
///
/// Register once (app root) and refresh on entering social surfaces.
class FriendshipState extends ChangeNotifier {
  final AuthService auth;
  final FriendshipService _service;

  List<Friend> friends = [];
  List<PendingRequest> pending = [];

  /// player_id → how I relate to them (drives the button). Absent = unknown
  /// (treated as [FriendState.none]).
  final Map<String, FriendState> _relationship = {};

  String lastError = '';
  int errorsSeen = 0;

  FriendshipState({
    required this.auth,
    FriendshipService? service,
  }) : _service = service ?? FriendshipService();

  String? get _token => auth.token;

  int get pendingCount => pending.length;

  FriendState relationshipWith(String playerId) =>
      _relationship[playerId] ?? FriendState.none;

  /// Load friends + pending and rebuild the relationship map. Safe to call on
  /// entering the hub / post-game screen; silently no-ops when signed out.
  Future<void> refresh() async {
    final token = _token;
    if (token == null) return;
    try {
      final results = await Future.wait([
        _service.friends(token: token),
        _service.pending(token: token),
      ]);
      friends = results[0] as List<Friend>;
      pending = results[1] as List<PendingRequest>;
      _relationship
        ..clear()
        ..addEntries(friends.map((f) => MapEntry(f.id, FriendState.friends)));
      notifyListeners();
    } catch (_) {
      // Non-fatal: leave state as-is (offline / cold server).
    }
  }

  Future<void> sendRequest(String receiverId) async {
    final token = _token;
    if (token == null || _relationship[receiverId] == FriendState.sending) {
      return;
    }
    _relationship[receiverId] = FriendState.sending;
    notifyListeners();
    try {
      await _service.sendRequest(token: token, receiverId: receiverId);
      _relationship[receiverId] = FriendState.pendingOutgoing;
    } on FriendshipException catch (e) {
      // Reconcile the button with the server's reason so it never sticks on
      // the spinner: "already friends" → friends, otherwise fall back.
      _relationship[receiverId] =
          e.message.contains('أصحاب') ? FriendState.friends : FriendState.none;
      _pushError(e.message);
    } catch (_) {
      _relationship[receiverId] = FriendState.none;
      _pushError('تعذّر إرسال الطلب — جرّب تاني.');
    }
    notifyListeners();
  }

  Future<void> respond(String requestId, {required bool accept}) async {
    final token = _token;
    if (token == null) return;
    // Optimistic removal from the pending list.
    final removed = pending.where((p) => p.requestId == requestId).toList();
    pending = pending.where((p) => p.requestId != requestId).toList();
    notifyListeners();
    try {
      await _service.respond(
          token: token, requestId: requestId, accept: accept);
      if (accept && removed.isNotEmpty) {
        final sender = removed.first.sender;
        _relationship[sender.id] = FriendState.friends;
        if (!friends.any((f) => f.id == sender.id)) friends = [...friends, sender];
      }
    } catch (e) {
      pending = [...pending, ...removed]; // rollback on failure
      _pushError('تعذّر الرد على الطلب — جرّب تاني.');
    }
    notifyListeners();
  }

  /// Called when a `friend_request_received` push arrives over a game socket,
  /// so the pending badge updates live without a refetch.
  void onIncomingRequest(PendingRequest request) {
    if (pending.any((p) => p.requestId == request.requestId)) return;
    pending = [request, ...pending];
    notifyListeners();
  }

  void _pushError(String message) {
    lastError = message;
    errorsSeen++;
  }
}
