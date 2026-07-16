import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:el_hakem/models/country.dart';
import 'package:el_hakem/screens/game_screen.dart';
import 'package:el_hakem/services/api_service.dart';
import 'package:el_hakem/state/game_state.dart';
import 'package:el_hakem/widgets/tutorial_overlay.dart';

List<Country> _deck() => List.generate(
      4,
      (i) => Country(code: 'C$i', nameEn: 'Country$i', nameAr: 'دولة$i'),
    );

Future<GameState> _pumpGame(WidgetTester tester) async {
  final game = GameState()
    ..startGame(names: ['A', 'B'], target: 5, countries: _deck());
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
  // Frame 1 schedules the post-frame trigger; extra pumps let the async
  // prefs lookup resolve and the overlay measure its first spotlight.
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return game;
}

void main() {
  testWidgets('first launch: tutorial appears and pauses the game',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final game = await _pumpGame(tester);
    addTearDown(game.dispose);

    expect(find.byType(TutorialOverlay), findsOneWidget);
    expect(find.text('تخطي الدليل'), findsOneWidget);
    expect(find.text('التالي'), findsOneWidget);
    expect(game.isPaused, isTrue); // clock frozen during the tour

    game.backToSetup(); // stop the timer so none outlives the test
  });

  testWidgets('walking all 6 steps ends the tour, resumes, and persists',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final game = await _pumpGame(tester);
    addTearDown(game.dispose);

    for (var step = 0; step < 5; step++) {
      expect(find.text('${step + 1} / 6'), findsOneWidget);
      await tester.tap(find.text('التالي'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400)); // spotlight glide
    }
    expect(find.text('6 / 6'), findsOneWidget);
    await tester.tap(find.text('يلا نلعب!'));
    await tester.pump();

    expect(find.byType(TutorialOverlay), findsNothing);
    expect(game.isPaused, isFalse); // clock resumed
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('seen_gameplay_tutorial'), isTrue);

    game.backToSetup();
    await tester.pump();
  });

  testWidgets('skip ends the tour immediately and persists', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final game = await _pumpGame(tester);
    addTearDown(game.dispose);

    await tester.tap(find.text('تخطي الدليل'));
    await tester.pump();

    expect(find.byType(TutorialOverlay), findsNothing);
    expect(game.isPaused, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('seen_gameplay_tutorial'), isTrue);

    game.backToSetup();
    await tester.pump();
  });

  testWidgets('returning player: tutorial never appears', (tester) async {
    SharedPreferences.setMockInitialValues({'seen_gameplay_tutorial': true});
    final game = await _pumpGame(tester);
    addTearDown(game.dispose);

    expect(find.byType(TutorialOverlay), findsNothing);
    expect(game.isPaused, isFalse); // game running normally

    game.backToSetup();
  });
}
