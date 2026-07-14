import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:el_hakem/models/country.dart';
import 'package:el_hakem/state/game_state.dart';

List<Country> _deck() => List.generate(
      5,
      (i) => Country(code: 'C$i', nameEn: 'Country$i', nameAr: 'دولة$i'),
    );

void main() {
  // testWidgets runs in a fake-async zone, so tester.pump(Duration) advances
  // GameState's Timer.periodic deterministically.

  testWidgets('accepted fact: no point, same country, next active player',
      (tester) async {
    final g = GameState()
      ..startGame(names: ['A', 'B', 'C', 'D'], target: 3, countries: _deck());
    final country = g.currentCountry;

    g.acceptFact();
    expect(g.scores, [0, 0, 0, 0]); // truths never score directly
    expect(g.currentPlayer, 1); // clockwise
    expect(g.currentCountry, same(country)); // SAME country
    expect(g.secondsLeft, 30); // fresh clock

    g.dispose();
  });

  testWidgets('wrong fact eliminates the speaker; same country stays up',
      (tester) async {
    final g = GameState()
      ..startGame(names: ['A', 'B', 'C', 'D'], target: 3, countries: _deck());
    final country = g.currentCountry;

    g.acceptFact(); // A ok → B
    g.ruleFalse(); // B busts → eliminated
    expect(g.eliminated, [false, true, false, false]);
    expect(g.lastEliminated, 1);
    expect(g.lastRoundEndReason, RoundEndReason.ruledFalse);
    expect(g.eliminationsCompleted, 1);
    expect(g.roundsCompleted, 0); // round still going
    expect(g.scores, [0, 0, 0, 0]);
    expect(g.currentPlayer, 2); // next ACTIVE player
    expect(g.currentCountry, same(country)); // round keeps its country
    expect(g.roundNumber, 1);

    g.dispose();
  });

  testWidgets('rotation skips eliminated players', (tester) async {
    final g = GameState()
      ..startGame(names: ['A', 'B', 'C', 'D'], target: 3, countries: _deck());

    g.acceptFact(); // A → B
    g.ruleFalse(); // B out → C
    g.acceptFact(); // C ok → D (B skipped is next check on wrap)
    expect(g.currentPlayer, 3);
    g.acceptFact(); // D ok → wraps past nobody → A
    expect(g.currentPlayer, 0);
    g.acceptFact(); // A ok → skips eliminated B → C
    expect(g.currentPlayer, 2);

    g.dispose();
  });

  testWidgets(
      'last player standing scores; round resets everyone on a new country',
      (tester) async {
    final g = GameState()
      ..startGame(names: ['A', 'B', 'C', 'D'], target: 3, countries: _deck());
    final firstCountry = g.currentCountry;

    g.ruleFalse(); // A out → B
    g.ruleFalse(); // B out → C
    expect(g.activeCount, 2);

    g.ruleFalse(); // C out → only D remains → D wins the round
    expect(g.scores, [0, 0, 0, 1]);
    expect(g.lastRoundWinner, 3);
    expect(g.roundsCompleted, 1);
    expect(g.eliminationsCompleted, 3);
    expect(g.roundNumber, 2);
    expect(g.eliminated, [false, false, false, false]); // all reset to active
    expect(g.currentCountry, isNot(same(firstCountry))); // fresh country
    expect(g.currentPlayer, 3); // round winner opens the next round
    expect(g.secondsLeft, 30);

    g.dispose();
  });

  testWidgets('2 players: strict 30s timeout ends the round immediately',
      (tester) async {
    final g = GameState()
      ..startGame(names: ['A', 'B'], target: 3, countries: _deck());
    expect(g.secondsLeft, 30);
    expect(g.currentPlayer, 0);

    await tester.pump(const Duration(seconds: 29));
    expect(g.secondsLeft, 1);
    expect(g.isDanger, isTrue); // ≤ 5s

    await tester.pump(const Duration(seconds: 1)); // hits 0 → timeout
    // With 2 players, one elimination leaves one player standing → point.
    expect(g.lastEliminated, 0);
    expect(g.lastRoundEndReason, RoundEndReason.timeout);
    expect(g.scores, [0, 1]);
    expect(g.lastRoundWinner, 1);
    expect(g.roundNumber, 2);
    expect(g.eliminated, [false, false]); // fresh round
    expect(g.currentPlayer, 1); // winner opens the next round
    expect(g.secondsLeft, 30);

    g.dispose();
  });

  testWidgets('reaching the target ends the match and stops the timer',
      (tester) async {
    final g = GameState()
      ..startGame(names: ['A', 'B', 'C', 'D'], target: 1, countries: _deck());

    g.ruleFalse(); // A out
    g.ruleFalse(); // B out
    g.ruleFalse(); // C out → D last standing, hits target 1
    expect(g.scores, [0, 0, 0, 1]);
    expect(g.matchWinner, 3);
    expect(g.phase, GamePhase.matchOver);

    // Timer is stopped: further elapsed time changes nothing.
    final frozen = g.secondsLeft;
    await tester.pump(const Duration(seconds: 5));
    expect(g.secondsLeft, frozen);
    expect(g.phase, GamePhase.matchOver);

    g.dispose();
  });

  testWidgets('passTurn consumes the pass and rotates without eliminating',
      (tester) async {
    final g = GameState()
      ..startGame(names: ['A', 'B', 'C', 'D'], target: 3, countries: _deck());
    final country = g.currentCountry;

    await tester.pump(const Duration(seconds: 10));
    expect(g.secondsLeft, 20);
    expect(g.canPass, isTrue);

    g.passTurn(); // A spends their pass
    expect(g.hasPassed, [true, false, false, false]);
    expect(g.eliminated, [false, false, false, false]); // NOT an elimination
    expect(g.scores, [0, 0, 0, 0]);
    expect(g.currentPlayer, 1); // clockwise to the next active player
    expect(g.currentCountry, same(country)); // same round, same country
    expect(g.secondsLeft, 30); // fresh clock for the next speaker

    g.dispose();
  });

  testWidgets('a player cannot pass twice in the same round', (tester) async {
    final g = GameState()
      ..startGame(names: ['A', 'B', 'C'], target: 3, countries: _deck());

    g.passTurn(); // A passes → B
    g.acceptFact(); // B ok → C
    g.acceptFact(); // C ok → A (pass already spent)
    expect(g.currentPlayer, 0);
    expect(g.canPass, isFalse);

    g.passTurn(); // no-op: pass already used this round
    expect(g.currentPlayer, 0); // turn did NOT move
    expect(g.hasPassed, [true, false, false]);

    g.dispose();
  });

  testWidgets('pass rotation skips eliminated players', (tester) async {
    final g = GameState()
      ..startGame(names: ['A', 'B', 'C', 'D'], target: 3, countries: _deck());

    g.acceptFact(); // A → B
    g.ruleFalse(); // B eliminated → C
    g.passTurn(); // C passes → skips B's seat... next active is D
    expect(g.hasPassed, [false, false, true, false]);
    expect(g.currentPlayer, 3);

    g.passTurn(); // D passes → wraps, skipping eliminated B → A
    expect(g.currentPlayer, 0);
    expect(g.hasPassed, [false, false, true, true]);

    g.dispose();
  });

  testWidgets('passes reset when a new round starts', (tester) async {
    final g = GameState()
      ..startGame(names: ['A', 'B', 'C'], target: 3, countries: _deck());

    g.passTurn(); // A spends pass → B
    g.ruleFalse(); // B out → C
    g.ruleFalse(); // C out → A last standing, round ends
    expect(g.scores, [1, 0, 0]);
    expect(g.roundNumber, 2);
    expect(g.hasPassed, [false, false, false]); // fresh passes for all
    expect(g.canPass, isTrue); // A (round winner, speaking first) can pass

    g.dispose();
  });

  testWidgets('pause freezes the countdown; resume continues it',
      (tester) async {
    final g = GameState()
      ..startGame(names: ['A', 'B'], target: 3, countries: _deck());

    await tester.pump(const Duration(seconds: 5));
    expect(g.secondsLeft, 25);

    g.togglePause();
    await tester.pump(const Duration(seconds: 10));
    expect(g.secondsLeft, 25); // frozen while paused

    g.togglePause(); // resume
    await tester.pump(const Duration(seconds: 3));
    expect(g.secondsLeft, 22);

    g.dispose();
  });

  testWidgets('turn pass and skip reset the clock to 30', (tester) async {
    final g = GameState()
      ..startGame(names: ['A', 'B'], target: 3, countries: _deck());

    await tester.pump(const Duration(seconds: 10));
    expect(g.secondsLeft, 20);

    g.acceptFact();
    expect(g.currentPlayer, 1);
    expect(g.secondsLeft, 30);

    await tester.pump(const Duration(seconds: 8));
    expect(g.secondsLeft, 22);
    g.skipCountry();
    expect(g.secondsLeft, 30); // fresh country, fresh clock

    g.dispose();
  });

  testWidgets('haptics: light tick each of the final 5s, heavy on timeout',
      (tester) async {
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String? ?? 'vibrate');
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final g = GameState()
      ..startGame(names: ['A', 'B'], target: 3, countries: _deck());

    int countOf(String type) => haptics.where((h) => h.contains(type)).length;

    // Down to 6s — outside the danger window, no haptics yet.
    await tester.pump(const Duration(seconds: 24));
    expect(g.secondsLeft, 6);
    expect(countOf('lightImpact'), 0);

    // 5 → 1: one light tick per second (fires as the ring turns neon-red).
    await tester.pump(const Duration(seconds: 5));
    expect(g.secondsLeft, 1);
    expect(countOf('lightImpact'), 5);
    expect(countOf('heavyImpact'), 0);

    // Hit 0: a single heavy impact, and the timeout elimination is applied.
    await tester.pump(const Duration(seconds: 1));
    expect(countOf('heavyImpact'), 1);
    expect(countOf('lightImpact'), 5); // no extra light tick at 0
    expect(g.lastRoundEndReason, RoundEndReason.timeout);

    g.dispose();
  });
}
