import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared brand emblem — **"الأعلام وتحدي البلاد"** (flags & country
/// challenge): two crossed neon flags (cyan vs purple — a country battle)
/// with glowing poles and waving pennants, and a neon amber exclamation mark
/// at the intersection tying it to the "بدون هبد!" identity.
///
/// Draws in a 100×100 design space. Used by BOTH [LauncherIconPainter]
/// (phone home screen) and the in-app `AppLogo`, so the identity is
/// pixel-identical everywhere. [glow] (0..1) modulates the neon halos so the
/// in-app logo can breathe; the launcher icon renders it at full intensity.
abstract final class NeonFlagsEmblem {
  // Crossed poles: A rises left→right, B mirrors it. They cross at ~(50, 53).
  static const _poleBottom = Offset(34, 88);
  static const _poleTop = Offset(62, 26);

  static void paint(Canvas c, {double glow = 1}) {
    _paintFlag(c, glow, mirrored: false, color: const Color(0xFF22D3EE));
    _paintFlag(c, glow, mirrored: true, color: AppColors.neonPurple);
    _paintCenterMark(c, glow);
  }

  /// Neon technique: a wide blurred pass under a crisp whitened core.
  static void _neonPath(Canvas c, Path path, Color color, double width,
      double glow) {
    c.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: .48 * glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
    );
    c.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Color.lerp(color, Colors.white, .32)!,
    );
  }

  /// One neon flag: a glowing pole with a waving pennant near the top.
  /// [mirrored] flips the whole flag across the vertical axis for the
  /// opposing country.
  static void _paintFlag(Canvas c, double glow,
      {required bool mirrored, required Color color}) {
    c.save();
    if (mirrored) {
      c.translate(100, 0);
      c.scale(-1, 1);
    }

    // Pole with a finial dot at the top.
    final pole = Path()
      ..moveTo(_poleBottom.dx, _poleBottom.dy)
      ..lineTo(_poleTop.dx, _poleTop.dy);
    _neonPath(c, pole, color, 2.4, glow);
    c.drawCircle(
      _poleTop,
      2.3,
      Paint()..color = Color.lerp(color, Colors.white, .5)!,
    );

    // Waving pennant flying outward from the pole top.
    final banner = Path()
      ..moveTo(62, 26)
      ..quadraticBezierTo(71, 18.5, 81, 21) // upper edge billows up
      ..quadraticBezierTo(78.5, 26.5, 80.5, 32) // swallow-tail flick
      ..quadraticBezierTo(69, 29, 58.5, 35.5) // lower edge sags home
      ..close();
    // Translucent neon cloth.
    c.drawPath(
      banner,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(60, 26),
          const Offset(81, 30),
          [
            color.withValues(alpha: .34 * (.55 + .45 * glow)),
            color.withValues(alpha: .10 * (.55 + .45 * glow)),
          ],
        ),
    );
    _neonPath(c, banner, color, 1.8, glow);

    c.restore();
  }

  /// Neon amber "!" on a dark disc at the poles' intersection — the
  /// "بدون هبد!" spark.
  static void _paintCenterMark(Canvas c, double glow) {
    const mark = Offset(50, 56);
    c.drawCircle(mark, 13.5, Paint()..color = const Color(0xFF14161F));
    c.drawCircle(
      mark,
      13.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = AppColors.amber.withValues(alpha: .55),
    );
    final bang = Path()
      ..moveTo(mark.dx, mark.dy - 8)
      ..lineTo(mark.dx, mark.dy + 2.5);
    _neonPath(c, bang, AppColors.amber, 3.4, glow);
    c.drawCircle(
      Offset(mark.dx, mark.dy + 7.5),
      2.1,
      Paint()..color = Color.lerp(AppColors.amber, Colors.white, .35)!,
    );
    // Halo so the mark reads as the icon's energy source.
    c.drawCircle(
      mark,
      12,
      Paint()
        ..color = AppColors.amber.withValues(alpha: .16 * glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }
}

/// Launcher icon artwork: the [NeonFlagsEmblem] on an obsidian background
/// with a circular cyan→purple gradient frame.
///
/// [frame] = true renders the full square icon (background + ring + emblem),
/// used for iOS and legacy Android. [frame] = false renders ONLY the emblem
/// on transparency, scaled into the Android adaptive-icon safe zone.
///
/// All geometry lives in a 100×100 design space and scales losslessly to any
/// output size (the rasterizer renders it at 1024×1024).
class LauncherIconPainter extends CustomPainter {
  final bool frame;

  const LauncherIconPainter({this.frame = true});

  static const _center = Offset(50, 50);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.shortestSide / 100);
    if (frame) {
      _paintBackground(canvas);
    } else {
      // Adaptive foreground: shrink the emblem into the ~66% safe zone so
      // launcher masks (circle/squircle) never clip the flag tips.
      canvas.translate(50, 50);
      canvas.scale(.68);
      canvas.translate(-50, -50);
    }
    NeonFlagsEmblem.paint(canvas);
  }

  void _paintBackground(Canvas c) {
    // Obsidian base with a soft vertical falloff.
    c.drawRect(
      const Rect.fromLTRB(0, 0, 100, 100),
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(50, 0),
          const Offset(50, 100),
          [const Color(0xFF181B26), const Color(0xFF0D0E13)],
        ),
    );
    // Faint radial glow rising from behind the emblem.
    c.drawCircle(
      _center,
      52,
      Paint()
        ..shader = ui.Gradient.radial(
          _center,
          52,
          [
            AppColors.neonPurple.withValues(alpha: .16),
            Colors.transparent,
          ],
        ),
    );
    // Circular gradient frame: blurred halo ring under a crisp sweep ring.
    final ring = Path()
      ..addOval(Rect.fromCircle(center: _center, radius: 45));
    c.drawPath(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = AppColors.electricBlue.withValues(alpha: .30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    c.drawPath(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..shader = ui.Gradient.sweep(
          _center,
          [
            const Color(0xFF22D3EE),
            AppColors.neonPurple,
            const Color(0xFF22D3EE),
          ],
          [0, .5, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(LauncherIconPainter old) => old.frame != frame;
}
