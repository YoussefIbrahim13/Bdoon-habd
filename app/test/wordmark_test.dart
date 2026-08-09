import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:el_hakem/theme/app_theme.dart';
import 'package:el_hakem/widgets/nova_components.dart';

/// The "بدون هبد!" wordmark must be pure violet — no white, no grey, no
/// washed-out lavender fringe along the glyph edges.
void main() {
  /// Every opaque pixel the widget rasterizes.
  Future<List<List<int>>> pixelsOf(WidgetTester tester, Widget w) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ColoredBox(
            color: AppColors.bg,
            child: Center(child: RepaintBoundary(child: w)),
          ),
        ),
      ),
    );
    await tester.pump();

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).last,
    );
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final d = bytes!.buffer.asUint8List();

    final out = <List<int>>[];
    for (var i = 0; i < d.length; i += 4) {
      if (d[i + 3] >= 200) out.add([d[i], d[i + 1], d[i + 2]]);
    }
    return out;
  }

  double lum(List<int> p) =>
      (0.2126 * p[0] + 0.7152 * p[1] + 0.0722 * p[2]) / 255;

  testWidgets('the wordmark rasterizes no white or washed-out pixel',
      (tester) async {
    final pixels = await pixelsOf(
      tester,
      const DisplayHeadline('بدون هبد!', size: 44, gradient: true),
    );
    expect(pixels, isNotEmpty);

    for (final p in pixels) {
      final mx = p.reduce((a, b) => a > b ? a : b);
      final mn = p.reduce((a, b) => a < b ? a : b);
      // Nothing bright may also be desaturated — that combination is what
      // reads as a white highlight on a thin antialiased Arabic stroke.
      expect(lum(p) > .5 && (mx - mn) < 60, isFalse,
          reason: 'washed-out pixel rgb$p in the wordmark');
      // Blue must lead: every pixel is violet, never grey or warm.
      expect(p[2], mx, reason: 'non-violet pixel rgb$p in the wordmark');
    }
  });

  testWidgets('gradient-filled text discards the child colour (srcIn)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GradientText(
          'بدون هبد!',
          gradient: AppGradients.wordmark,
          style: AppText.display(size: 44),
        ),
      ),
    );

    final mask = tester.widget<ShaderMask>(find.byType(ShaderMask));
    // `modulate` (the ShaderMask default) multiplies the child's own colour
    // into the result, so a white child bleeds through partial coverage.
    expect(mask.blendMode, BlendMode.srcIn);

    // And the child is not white to begin with.
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.style!.color, isNot(Colors.white));
  });

  test('the wordmark gradient has only saturated violet stops', () {
    for (final c in AppGradients.wordmark.colors) {
      expect(c.a, 1.0);
      expect(c.computeLuminance(), lessThan(.25),
          reason: '$c is too light for text fill');
      // Blue-dominant, and clearly so.
      final r = (c.r * 255).round();
      final g = (c.g * 255).round();
      final b = (c.b * 255).round();
      expect(b, greaterThan(r));
      expect(b - [r, g].reduce((x, y) => x > y ? x : y), greaterThan(60),
          reason: '$c is not saturated enough to read as violet');
    }
  });
}
