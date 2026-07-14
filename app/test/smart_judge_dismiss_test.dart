import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

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
  testWidgets('tapping outside dismisses the Smart Judge sheet (modal)', (
    tester,
  ) async {
    const country = Country(code: 'EG', nameEn: 'Egypt', nameAr: 'مصر');
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
      builder: (_) => const SmartJudgeSheet(country: country),
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

    await tester.tap(find.text('اسأل الحكم الذكي'));
    await tester.pumpAndSettle();
    expect(find.byType(SmartJudgeSheet), findsOneWidget);
    expect(game.isPaused, isTrue); // auto-paused while consulting

    // Tap the dimmed area above the glass card.
    await tester.tapAt(const Offset(200, 40));
    await tester.pumpAndSettle();

    expect(find.byType(SmartJudgeSheet), findsNothing);
    expect(game.isPaused, isFalse); // resumed on close
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

    await tester.tap(find.text('اسأل الحكم الذكي'));
    await tester.pumpAndSettle();
    expect(find.byType(SmartJudgeSheet), findsOneWidget);

    await tester.drag(find.byType(SmartJudgeSheet), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.byType(SmartJudgeSheet), findsNothing);
  });
}
