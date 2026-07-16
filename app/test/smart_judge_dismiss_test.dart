import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:el_hakem/models/country.dart';
import 'package:el_hakem/screens/game_screen.dart';
import 'package:el_hakem/services/api_service.dart';
import 'package:el_hakem/state/game_state.dart';
import 'package:el_hakem/widgets/smart_judge_sheet.dart';

List<Country> _deck() => List.generate(
  4,
  (i) => Country(code: 'C$i', nameEn: 'Country$i', nameAr: 'دولة$i'),
);

void main() {
  // These tests exercise the live game screen — mark the first-time tutorial
  // as already seen so its overlay never intercepts taps.
  setUp(() => SharedPreferences.setMockInitialValues(
      {'seen_gameplay_tutorial': true}));

  testWidgets('tapping outside dismisses the Smart Judge sheet (modal)', (
    tester,
  ) async {
    final country = Country(code: 'EG', nameEn: 'Egypt', nameAr: 'مصر');
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: Scaffold(
          body: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .55),
      builder: (_) => SmartJudgeSheet(country: country),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SmartJudgeSheet), findsOneWidget);

    await tester.tapAt(const Offset(200, 40)); // dimmed area above the card
    await tester.pumpAndSettle();
    expect(find.byType(SmartJudgeSheet), findsNothing);
  });

  testWidgets('outside tap dismisses via the real GameScreen flow', (
    tester,
  ) async {
    final game = GameState()
      ..startGame(names: ['A', 'B'], target: 5, countries: _deck());
    addTearDown(game.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiService>(create: (_) => ApiService()),
          ChangeNotifierProvider<GameState>.value(value: game),
        ],
        child: MaterialApp(
          builder: (context, child) =>
              Directionality(textDirection: TextDirection.rtl, child: child!),
          home: const GameScreen(),
        ),
      ),
    );
    await tester.pump();

    // Bounded pumps (not pumpAndSettle): the active player's spotlight pulse
    // animates continuously, so the tree never "settles".
    await tester.tap(find.text('اسأل الحكم الذكي'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700)); // sheet entrance
    expect(find.byType(SmartJudgeSheet), findsOneWidget);
    expect(game.isPaused, isTrue); // auto-paused while consulting

    // Tap the dimmed area above the glass card. Bounded pumps (not
    // pumpAndSettle): closing resumes the turn timer, whose 1-second ticks
    // never let the tree "settle".
    await tester.tapAt(const Offset(200, 40));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600)); // close animation

    expect(find.byType(SmartJudgeSheet), findsNothing);
    expect(game.isPaused, isFalse); // resumed on close

    game.backToSetup(); // stop the turn timer so no timer outlives the test
  });

  testWidgets('swipe down also dismisses the sheet', (tester) async {
    final game = GameState()
      ..startGame(names: ['A', 'B'], target: 5, countries: _deck());
    addTearDown(game.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiService>(create: (_) => ApiService()),
          ChangeNotifierProvider<GameState>.value(value: game),
        ],
        child: MaterialApp(
          builder: (context, child) =>
              Directionality(textDirection: TextDirection.rtl, child: child!),
          home: const GameScreen(),
        ),
      ),
    );
    await tester.pump();

    // Bounded pumps throughout (not pumpAndSettle): the spotlight pulse and,
    // after closing, the resumed turn timer never let the tree "settle".
    await tester.tap(find.text('اسأل الحكم الذكي'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700)); // sheet entrance
    expect(find.byType(SmartJudgeSheet), findsOneWidget);

    await tester.drag(find.byType(SmartJudgeSheet), const Offset(0, 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600)); // close animation
    expect(find.byType(SmartJudgeSheet), findsNothing);

    game.backToSetup(); // stop the turn timer so no timer outlives the test
    await tester.pump();
  });
}
