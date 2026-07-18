import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:el_hakem/screens/game_mode_screen.dart';
import 'package:el_hakem/screens/home_screen.dart';
import 'package:el_hakem/screens/online_hub_screen.dart';
import 'package:el_hakem/screens/sign_in_screen.dart';
import 'package:el_hakem/services/api_service.dart';
import 'package:el_hakem/services/auth_service.dart';
import 'package:el_hakem/state/game_state.dart';

Future<(GameState, AuthService)> _pump(WidgetTester tester) async {
  final game = GameState();
  final auth = AuthService(idTokenProvider: () async => null);
  await auth.restoreSession();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<ApiService>(create: (_) => ApiService()),
        ChangeNotifierProvider<GameState>.value(value: game),
        ChangeNotifierProvider<AuthService>.value(value: auth),
      ],
      child: MaterialApp(
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const GameModeScreen(),
      ),
    ),
  );
  await tester.pump();
  return (game, auth);
}

void _seedSignedInPrefs() {
  SharedPreferences.setMockInitialValues({
    'auth_jwt': 'jwt-abc',
    'auth_jwt_expiry':
        DateTime.now().millisecondsSinceEpoch ~/ 1000 + 7 * 24 * 3600,
    'auth_user': jsonEncode({
      'id': 'player-1',
      'email': 'p@example.com',
      'name': 'Karim',
      'picture': null,
      'matches_played': 3,
      'wins': 1,
      'total_points': 7,
    }),
  });
}

void main() {
  // Bounded pumps throughout: the drifting glows, logo breathing, and the
  // "قريباً" tag pulse animate forever, so the tree never settles.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('gateway shows both mode cards, no coming-soon dressing',
      (tester) async {
    final (game, _) = await _pump(tester);
    addTearDown(game.dispose);

    expect(find.text('لعب أوفلاين'), findsOneWidget);
    expect(find.text('لعب أونلاين'), findsOneWidget);
    expect(find.text('اختار طريقة اللعب'), findsOneWidget);
    // The "coming soon" era is over: no tag, no lock, no suffix.
    expect(find.textContaining('قريباً'), findsNothing);
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
    expect(find.text('تسجيل الخروج'), findsNothing);
  });

  testWidgets('signed out: online card opens the Google sign-in gateway',
      (tester) async {
    final (game, _) = await _pump(tester);
    addTearDown(game.dispose);

    await tester.tap(find.text('لعب أونلاين'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600)); // route transition

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.text('تسجيل الدخول باستخدام جوجل'), findsOneWidget);
  });

  testWidgets('signed in: online card opens the online hub', (tester) async {
    _seedSignedInPrefs();
    final (game, auth) = await _pump(tester);
    addTearDown(game.dispose);
    expect(auth.isSignedIn, isTrue);

    expect(find.text('لعب أونلاين'), findsOneWidget);
    expect(find.textContaining('متصل كـ Karim'), findsOneWidget);
    expect(find.text('تسجيل الخروج'), findsOneWidget);

    await tester.tap(find.text('لعب أونلاين'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600)); // route transition
    expect(find.byType(SignInScreen), findsNothing);
    expect(find.byType(OnlineHubScreen), findsOneWidget);
    expect(find.text('اعمل أوضة'), findsOneWidget);
    expect(find.text('ادخل الأوضة'), findsOneWidget);
  });

  testWidgets('offline card navigates to the lobby', (tester) async {
    final (game, _) = await _pump(tester);
    addTearDown(game.dispose);

    await tester.tap(find.text('لعب أوفلاين'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600)); // route transition

    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('cancelled sign-in shows the amber feedback and stays put',
      (tester) async {
    final (game, _) = await _pump(tester);
    addTearDown(game.dispose);

    await tester.tap(find.text('لعب أونلاين'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // idTokenProvider returns null → cancelled.
    await tester.tap(find.text('تسجيل الدخول باستخدام جوجل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('اتلغى تسجيل الدخول'), findsOneWidget);
    expect(find.byType(SignInScreen), findsOneWidget); // still here
  });
}
