import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:el_hakem/screens/home_screen.dart';
import 'package:el_hakem/services/api_service.dart';
import 'package:el_hakem/state/game_state.dart';

void main() {
  testWidgets('setup card fits a narrow phone with 5 target options',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final game = GameState();
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
          home: const HomeScreen(),
        ),
      ),
    );
    // Let the (failing, offline) countries fetch settle without pumpAndSettle.
    await tester.pump(const Duration(seconds: 25));
    await tester.pump();

    // All five target pills are present, including the new "1".
    for (final opt in ['1', '3', '5', '7', '10']) {
      expect(find.text(opt), findsOneWidget);
    }
    // No RenderFlex overflow was thrown at 320dp.
    expect(tester.takeException(), isNull);
  });
}
