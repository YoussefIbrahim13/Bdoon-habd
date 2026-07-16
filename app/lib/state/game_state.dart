import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../models/country.dart';

enum GamePhase { setup, playing, matchOver }

/// Why a player was eliminated from the round — lets the UI show the right
/// feedback.
enum RoundEndReason { ruledFalse, timeout }

/// In-session game state only (no persistence, per the v1 spec).
///
/// Elimination Round System for 2–[maxPlayers] players (default
/// [defaultPlayers]):
/// - Every round starts with a fresh country and ALL players active.
/// - Active players take turns clockwise on the SAME country.
/// - Fact ruled TRUE → no points; the turn passes clockwise to the next
///   active player, still on the same country.
/// - Fact ruled FALSE or the clock hits 0 → the speaker is eliminated from
///   the current round; the same country stays up and the turn passes to the
///   next remaining active player.
/// - When only ONE active player remains, they score 1 point, everyone is
///   reset to active, a new country is drawn, and the round winner opens the
///   next round.
/// - First player to reach [targetScore] wins the match.
class GameState extends ChangeNotifier {
  /// Strict per-turn limit (seconds).
  static const int turnDuration = 30;

  /// Early warning threshold (seconds) — the timer shifts from neon blue to
  /// urgent red and starts pulsing below it.
  static const int warnThreshold = 10;

  /// Critical threshold (seconds) — the pulse accelerates and haptic
  /// heartbeat ticks fire below it.
  static const int dangerThreshold = 5;

  static const int minPlayers = 2;
  static const int maxPlayers = 4;
  static const int defaultPlayers = 4;

  static const List<String> _defaultNames = [
    'لاعب ١',
    'لاعب ٢',
    'لاعب ٣',
    'لاعب ٤',
  ];

  int totalPlayers = defaultPlayers;
  List<String> playerNames = List.of(_defaultNames);
  List<int> scores = List.filled(defaultPlayers, 0);
  int targetScore = 5;

  /// Per-player elimination flags for the CURRENT round. Reset to all-false
  /// when a new round starts. (Mutated in place — UI selectors must watch the
  /// scalar elements, e.g. `eliminated[i]`, never the list itself.)
  List<bool> eliminated = List.filled(defaultPlayers, false);

  /// One "تخطي" (pass) per player per round: true once player i has spent
  /// theirs. Reset alongside [eliminated] at every round/match start.
  /// (Also mutated in place — select the scalar elements.)
  List<bool> hasPassed = List.filled(defaultPlayers, false);

  List<Country> _deck = [];
  int _deckIndex = 0;
  int currentPlayer = 0;
  int roundNumber = 1;
  GamePhase phase = GamePhase.setup;

  /// Set after each elimination: who was knocked out of the round + why.
  int? lastEliminated;
  RoundEndReason? lastRoundEndReason;

  /// Set when a round completes: the last player standing (they scored).
  int? lastRoundWinner;

  /// Monotonic counters the UI watches to fire one-shot feedback:
  /// [eliminationsCompleted] ticks on every knockout (manual غلط! and
  /// timeout alike); [roundsCompleted] ticks when a round ends with a winner.
  int eliminationsCompleted = 0;
  int roundsCompleted = 0;

  // --- Turn countdown ---
  int secondsLeft = turnDuration;
  bool isPaused = false;
  Timer? _timer;

  Country? get currentCountry =>
      _deck.isEmpty ? null : _deck[_deckIndex % _deck.length];

  String get currentPlayerName => playerNames[currentPlayer];

  /// Players still in the current round.
  int get activeCount => eliminated.where((e) => !e).length;

  bool isEliminated(int player) => eliminated[player];

  /// Whether the current speaker can still spend their pass this round.
  bool get canPass => phase == GamePhase.playing && !hasPassed[currentPlayer];

  /// True while the countdown is in its final [warnThreshold] seconds —
  /// drives the blue→red shift and the start of the pulse.
  bool get isWarn => secondsLeft <= warnThreshold;

  /// True while the countdown is in its final [dangerThreshold] seconds —
  /// drives the accelerated pulse and haptic ticks.
  bool get isDanger => secondsLeft <= dangerThreshold;

  double get timeProgress => secondsLeft / turnDuration; // 1.0 → 0.0

  /// Index of the first player to have reached [targetScore], or null while
  /// the match is still open.
  int? get matchWinner {
    for (var i = 0; i < totalPlayers; i++) {
      if (scores[i] >= targetScore) return i;
    }
    return null;
  }

  /// Below this many countries, a difficulty filter is ignored — a party
  /// deck that thin would repeat flags constantly.
  static const int minDeckSize = 8;

  /// The difficulty this match was started with (null = all countries).
  CountryDifficulty? difficulty;

  /// [names] length picks the player count for this match (2–[maxPlayers]).
  ///
  /// [difficulty] filters the deck to matching countries; null plays the
  /// whole world. If the filter leaves fewer than [minDeckSize] countries,
  /// the full list is used instead.
  void startGame({
    required List<String> names,
    required int target,
    required List<Country> countries,
    CountryDifficulty? difficulty,
  }) {
    assert(
      names.length >= minPlayers && names.length <= maxPlayers,
      'startGame expects $minPlayers–$maxPlayers player names',
    );
    this.difficulty = difficulty;
    final filtered = difficulty == null
        ? countries
        : countries.where((c) => c.difficulty == difficulty).toList();
    final pool = filtered.length >= minDeckSize ? filtered : countries;
    totalPlayers = names.length.clamp(minPlayers, maxPlayers);
    playerNames = List.of(names.take(totalPlayers));
    targetScore = target;
    scores = List.filled(totalPlayers, 0);
    eliminated = List.filled(totalPlayers, false);
    hasPassed = List.filled(totalPlayers, false);
    _deck = List.of(pool)..shuffle(Random());
    _deckIndex = 0;
    currentPlayer = 0;
    roundNumber = 1;
    eliminationsCompleted = 0;
    roundsCompleted = 0;
    lastEliminated = null;
    lastRoundEndReason = null;
    lastRoundWinner = null;
    phase = GamePhase.playing;
    _startTurnTimer();
    notifyListeners();
  }

  /// The judge ruled the current speaker's fact TRUE — no points yet; the
  /// turn passes clockwise to the next active player on the SAME country.
  void acceptFact() {
    if (phase != GamePhase.playing) return;
    currentPlayer = _nextActive(currentPlayer);
    _startTurnTimer();
    notifyListeners();
  }

  /// The judge ruled the current speaker's fact false — they are eliminated
  /// from this round.
  void ruleFalse() => _eliminateCurrent(RoundEndReason.ruledFalse);

  /// The current speaker spends their one pass for this round: no
  /// elimination, no point — the turn simply moves clockwise to the next
  /// active player with a fresh clock. No-op if the pass is already spent.
  void passTurn() {
    if (!canPass) return;
    hasPassed[currentPlayer] = true;
    currentPlayer = _nextActive(currentPlayer);
    _startTurnTimer();
    notifyListeners();
  }

  /// Swap the country without any elimination; gives the current player a
  /// fresh clock. (Round eliminations carry over — only the country changes.)
  void skipCountry() {
    _deckIndex++;
    _startTurnTimer();
    notifyListeners();
  }

  void backToSetup() {
    resetGame();
  }

  /// Hard reset to a fresh lobby-ready state.
  ///
  /// Used when leaving an active match abruptly (for example from the
  /// in-game "end match" action) so no timer or round state leaks past exit.
  void resetGame() {
    _stopTimer();
    totalPlayers = defaultPlayers;
    playerNames = List.of(_defaultNames);
    scores = List.filled(defaultPlayers, 0);
    targetScore = 5;
    eliminated = List.filled(defaultPlayers, false);
    hasPassed = List.filled(defaultPlayers, false);
    _deck = [];
    _deckIndex = 0;
    difficulty = null;
    currentPlayer = 0;
    roundNumber = 1;
    secondsLeft = turnDuration;
    isPaused = false;
    eliminationsCompleted = 0;
    roundsCompleted = 0;
    lastEliminated = null;
    lastRoundEndReason = null;
    lastRoundWinner = null;
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
      // Strict timeout: same outcome as being ruled false — eliminated from
      // the round.
      _eliminateCurrent(RoundEndReason.timeout);
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

  // --- Elimination round engine --------------------------------------------

  /// Next non-eliminated player clockwise from [from] (exclusive).
  int _nextActive(int from) {
    var i = from;
    do {
      i = (i + 1) % totalPlayers;
    } while (eliminated[i]);
    return i;
  }

  /// Knock the current speaker out of the round. If only one active player
  /// remains, they win the round (1 point) and a new round begins; otherwise
  /// the SAME country stays up for the next active player.
  void _eliminateCurrent(RoundEndReason reason) {
    if (phase != GamePhase.playing) return;
    eliminated[currentPlayer] = true;
    lastEliminated = currentPlayer;
    lastRoundEndReason = reason;
    eliminationsCompleted++;

    if (activeCount == 1) {
      _endRound(winner: _nextActive(currentPlayer));
    } else {
      currentPlayer = _nextActive(currentPlayer);
      _startTurnTimer();
    }
    notifyListeners();
  }

  /// Last player standing scores; either the match ends or everyone resets
  /// to active on a fresh country, with the round winner speaking first.
  void _endRound({required int winner}) {
    scores[winner]++;
    lastRoundWinner = winner;
    roundsCompleted++;

    if (matchWinner != null) {
      phase = GamePhase.matchOver;
      _stopTimer();
      return;
    }
    roundNumber++;
    _deckIndex++;
    for (var i = 0; i < totalPlayers; i++) {
      eliminated[i] = false;
      hasPassed[i] = false; // everyone's pass comes back with the new country
    }
    currentPlayer = winner;
    _startTurnTimer();
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }
}
