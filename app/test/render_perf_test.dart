import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:el_hakem/screens/home_screen.dart';
import 'package:el_hakem/services/api_service.dart';
import 'package:el_hakem/state/game_state.dart';
import 'package:el_hakem/theme/app_theme.dart';
import 'package:el_hakem/widgets/nova_components.dart';

/// Guards the render-performance contract of the NovaPay glass surfaces:
/// an opaque dark base on frame zero (no white flash), and no per-frame
/// `saveLayer` work on the largest card in the app.
void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, c) =>
            Directionality(textDirection: TextDirection.rtl, child: c!),
        home: child,
      );

  /// The card's own surface: the outermost DecoratedBox it builds.
  BoxDecoration surfaceOf(WidgetTester tester) {
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(GlassCard),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    return box.decoration as BoxDecoration;
  }

  testWidgets('GlassCard paints an opaque dark base — never a white canvas',
      (tester) async {
    await tester.pumpWidget(
      wrap(const Center(child: GlassCard(child: Text('x')))),
    );

    final gradient = surfaceOf(tester).gradient as LinearGradient;
    // A BoxDecoration gradient overrides `color`, so every stop must itself
    // be opaque — otherwise the very first frame shows through to whatever
    // is behind the route.
    for (final c in gradient.colors) {
      expect(c.a, 1.0, reason: 'glass base stop $c is translucent');
      expect(c.computeLuminance(), lessThan(.08),
          reason: 'glass base stop $c is too light to be the dark base');
    }
  });

  testWidgets('GlassCard mounts with no BackdropFilter and settles instantly',
      (tester) async {
    await tester.pumpWidget(
      wrap(const Center(child: GlassCard(child: Text('x')))),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    // No always-on entrance animation: the card is final on its first frame.
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpAndSettle();
  });

  testWidgets('GlassCard clamps a runaway blur sigma', (tester) async {
    await tester.pumpWidget(
      wrap(const Center(child: GlassCard(blur: 40, child: Text('x')))),
    );

    // Opting into blur is allowed, but the sigma is capped and the filter is
    // strictly bounded by a clip so it cannot widen repaint bounds.
    final clip = tester.widget<ClipRRect>(
      find
          .ancestor(
            of: find.byType(BackdropFilter),
            matching: find.byType(ClipRRect),
          )
          .first,
    );
    expect(clip.clipBehavior, Clip.hardEdge);

    final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(filter.filter.toString(), contains('${GlassCard.maxBlurSigma}'));
  });

  testWidgets('HomeScreen mounts with zero backdrop blurs', (tester) async {
    final game = GameState();
    addTearDown(game.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiService>(create: (_) => ApiService()),
          ChangeNotifierProvider<GameState>.value(value: game),
        ],
        child: wrap(const HomeScreen()),
      ),
    );

    // The setup form is the biggest surface in the app and it mounts on the
    // same frame as the NovaPageRoute push. A BackdropFilter here costs a
    // saveLayer every frame of that transition.
    expect(find.byType(BackdropFilter), findsNothing);

    // And the screen is opaque from frame zero.
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppColors.bg);
  });
}
