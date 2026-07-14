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

  testWidgets('strict 30s timeout awards the point to the opponent',
      (tester) async {
    final g = GameState()
      ..startGame(names: ['A', 'B'], target: 3, countries: _deck());
    expect(g.secondsLeft, 30);
    expect(g.currentPlayer, 0);

    await tester.pump(const Duration(seconds: 29));
    expect(g.secondsLeft, 1);
    expect(g.isDanger, isTrue); // ≤ 5s

    await tester.pump(const Duration(seconds: 1)); // hits 0 → timeout
    expect(g.scores, [0, 1]); // opponent scored, not a neutral pass
    expect(g.lastRoundEndReason, RoundEndReason.timeout);
    expect(g.roundNumber, 2);
    expect(g.secondsLeft, 30); // reset for the new round

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

  testWidgets('turn switch and skip reset the clock to 30', (tester) async {
    final g = GameState()
      ..startGame(names: ['A', 'B'], target: 3, countries: _deck());

    await tester.pump(const Duration(seconds: 10));
    expect(g.secondsLeft, 20);

    g.nextTurn();
    expect(g.currentPlayer, 1);
    expect(g.secondsLeft, 30);

    await tester.pump(const Duration(seconds: 8));
    expect(g.secondsLeft, 22);
    g.skipCountry();
    expect(g.secondsLeft, 30); // fresh country, fresh clock

    g.dispose();
  });

  testWidgets('timeout on match point ends the match and stops the timer',
      (tester) async {
    final g = GameState()
      ..startGame(names: ['A', 'B'], target: 1, countries: _deck());

    await tester.pump(const Duration(seconds: 30)); // player 0 times out
    expect(g.scores, [0, 1]);
    expect(g.matchWinner, 1);
    expect(g.phase, GamePhase.matchOver);

    // Timer is stopped: further elapsed time changes nothing.
    await tester.pump(const Duration(seconds: 5));
    expect(g.secondsLeft, 0);
    expect(g.phase, GamePhase.matchOver);

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

    // Hit 0: a single heavy impact, and the timeout is applied.
    await tester.pump(const Duration(seconds: 1));
    expect(countOf('heavyImpact'), 1);
    expect(countOf('lightImpact'), 5); // no extra light tick at 0
    expect(g.lastRoundEndReason, RoundEndReason.timeout);

    g.dispose();
  });
}
