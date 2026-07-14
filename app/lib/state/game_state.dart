import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../models/country.dart';

enum GamePhase { setup, playing, matchOver }

/// Why the last round ended — lets the UI show the right feedback.
enum RoundEndReason { ruledFalse, timeout }

/// In-session game state only (no persistence, per the v1 spec).
/// The app tracks turns, score, and the per-turn countdown; the human judge
/// runs the actual round.
class GameState extends ChangeNotifier {
  /// Strict per-turn limit (seconds).
  static const int turnDuration = 30;

  /// Low-time warning threshold (seconds) — UI turns neon-red / pulses below it.
  static const int dangerThreshold = 5;

  List<String> playerNames = ['لاعب ١', 'لاعب ٢'];
  List<int> scores = [0, 0];
  int targetScore = 5;

  List<Country> _deck = [];
  int _deckIndex = 0;
  int currentPlayer = 0;
  int roundNumber = 1;
  GamePhase phase = GamePhase.setup;

  /// Set after a round ends: index of the round winner + why it ended.
  int? lastRoundWinner;
  RoundEndReason? lastRoundEndReason;

  /// Monotonic count of scored rounds. The UI watches this to fire one-shot
  /// round-end feedback for BOTH manual (غلط!) and automatic (timeout) losses.
  int roundsCompleted = 0;

  // --- Turn countdown ---
  int secondsLeft = turnDuration;
  bool isPaused = false;
  Timer? _timer;

  Country? get currentCountry =>
      _deck.isEmpty ? null : _deck[_deckIndex % _deck.length];

  String get currentPlayerName => playerNames[currentPlayer];

  /// True while the countdown is in its final [dangerThreshold] seconds.
  bool get isDanger => secondsLeft <= dangerThreshold;

  double get timeProgress => secondsLeft / turnDuration; // 1.0 → 0.0

  int? get matchWinner {
    if (scores[0] >= targetScore) return 0;
    if (scores[1] >= targetScore) return 1;
    return null;
  }

  void startGame({
    required List<String> names,
    required int target,
    required List<Country> countries,
  }) {
    playerNames = names;
    targetScore = target;
    scores = [0, 0];
    _deck = List.of(countries)..shuffle(Random());
    _deckIndex = 0;
    currentPlayer = 0;
    roundNumber = 1;
    roundsCompleted = 0;
    lastRoundWinner = null;
    lastRoundEndReason = null;
    phase = GamePhase.playing;
    _startTurnTimer();
    notifyListeners();
  }

  /// The current speaker's fact was accepted — pass the turn (resets the clock).
  void nextTurn() {
    currentPlayer = 1 - currentPlayer;
    _startTurnTimer();
    notifyListeners();
  }

  /// The judge ruled the current speaker's fact false — opponent scores.
  void ruleFalse() => _endRoundAsLoss(RoundEndReason.ruledFalse);

  /// Swap the country without scoring; gives the current player a fresh clock.
  void skipCountry() {
    _deckIndex++;
    _startTurnTimer();
    notifyListeners();
  }

  void backToSetup() {
    _stopTimer();
    phase = GamePhase.setup;
    notifyListeners();
  }

  // --- Timer control -------------------------------------------------------

  /// Manual pause/resume toggle for the human Judge.
  void togglePause() {
    if (phase != GamePhase.playing) return;
    isPaused = !isPaused;
    notifyListeners();
  }

  /// Pause without toggling (e.g. auto-pause while the Smart Judge is open).
  void pause() {
    if (phase != GamePhase.playing || isPaused) return;
    isPaused = true;
    notifyListeners();
  }

  void resume() {
    if (phase != GamePhase.playing || !isPaused) return;
    isPaused = false;
    notifyListeners();
  }

  void _startTurnTimer() {
    _timer?.cancel();
    secondsLeft = turnDuration;
    isPaused = false;
    _timer = Timer.periodic(const Duration(seconds: 1), _onTick);
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _onTick(Timer _) {
    if (isPaused || phase != GamePhase.playing) return;
    secondsLeft--;
    if (secondsLeft <= 0) {
      secondsLeft = 0;
      // Strong, unmistakable "time's up" jolt in the Judge's hand.
      HapticFeedback.heavyImpact();
      // Strict timeout: same outcome as being ruled false — the current player
      // loses the round and the opponent takes the point.
      _endRoundAsLoss(RoundEndReason.timeout);
    } else {
      // Heartbeat: a light tick on each of the final [dangerThreshold] seconds
      // (fires exactly when the ring turns neon-red). Fire-and-forget — the
      // platform-channel call is async and never blocks the UI/raster thread.
      if (secondsLeft <= dangerThreshold) {
        HapticFeedback.lightImpact();
      }
      notifyListeners();
    }
  }

  /// Award the round to the opponent of [currentPlayer], then advance to the
  /// next round (loser speaks first) or end the match. Shared by the manual
  /// "غلط!" ruling and the automatic timeout.
  void _endRoundAsLoss(RoundEndReason reason) {
    if (phase != GamePhase.playing) return;
    final winner = 1 - currentPlayer;
    scores[winner]++;
    lastRoundWinner = winner;
    lastRoundEndReason = reason;
    roundsCompleted++;

    if (matchWinner != null) {
      phase = GamePhase.matchOver;
      _stopTimer();
    } else {
      roundNumber++;
      _deckIndex++;
      // currentPlayer already points at the loser, who starts the next round.
      _startTurnTimer();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }
}
