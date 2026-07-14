import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The بدون هبد! brand mark — a neon wireframe globe (geography) being struck
/// by a judge's gavel (the ruling), inside a gradient-bordered badge.
///
/// Drawn entirely with [CustomPainter]: no image assets, scales losslessly to
/// any size, and the neon intensity is externally animatable via [glow]
/// (0 → dim, 1 → full pulse) so splash/idle screens can "breathe" it.
class AppLogo extends StatelessWidget {
  final double size;

  /// Neon intensity 0..1 — drive this from an animation for a pulse effect.
  final double glow;

  const AppLogo({super.key, this.size = 120, this.glow = .8});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      // Isolates frequent glow repaints from the rest of the tree.
      child: CustomPaint(
        size: Size.square(size),
        painter: _LogoPainter(glow: glow.clamp(0.0, 1.0).toDouble()),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  final double glow;

  _LogoPainter({required this.glow});

  // All geometry lives in a 100×100 design space, scaled to the actual size.
  static const _globeCenter = Offset(41, 57);
  static const _globeRadius = 23.0;

  // Unit vector from the globe center toward the gavel (up-right).
  static const _strikeDir = Offset(0.753, -0.658);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.shortestSide / 100);
    _paintBadge(canvas);
    _paintGlobe(canvas);
    _paintGavel(canvas);
  }

  /// Neon technique: a wide blurred pass in the accent color underneath a
  /// crisp, slightly whitened core stroke on top.
  void _neonPath(Canvas c, Path path, Color color, double width) {
    c.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 2.4
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: .45 * glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
    );
    c.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(color, Colors.white, .30)!,
    );
  }

  void _paintBadge(Canvas c) {
    final rrect = RRect.fromRectAndRadius(
      const Rect.fromLTRB(6, 6, 94, 94),
      const Radius.circular(26),
    );
    // Soft halo behind the whole badge.
    c.drawRRect(
      rrect,
      Paint()
        ..color = AppColors.neonPurple.withValues(alpha: .30 * glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    // Obsidian fill with a faint diagonal sheen.
    c.drawRRect(
      rrect,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(6, 6),
          const Offset(94, 94),
          [const Color(0xFF1B1E29), const Color(0xFF111319)],
        ),
    );
    // Gradient border (electric blue → neon purple).
    c.drawRRect(
      rrect.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..shader = ui.Gradient.linear(
          const Offset(6, 6),
          const Offset(94, 94),
          [AppColors.electricBlue, AppColors.neonPurple],
        ),
    );
  }

  void _paintGlobe(Canvas c) {
    final sphere = Path()
      ..addOval(Rect.fromCircle(center: _globeCenter, radius: _globeRadius));
    _neonPath(c, sphere, AppColors.electricBlue, 2.2);

    // Meridians: two vertical ellipses.
    for (final f in const [0.36, 0.72]) {
      _neonPath(
        c,
        Path()
          ..addOval(Rect.fromCenter(
            center: _globeCenter,
            width: _globeRadius * 2 * f,
            height: _globeRadius * 2,
          )),
        AppColors.electricBlue,
        1.1,
      );
    }

    // Parallels: bowed chords, clipped to the sphere.
    c.save();
    c.clipPath(sphere);
    for (final dy in [-_globeRadius * .48, 0.0, _globeRadius * .48]) {
      final p = Path()
        ..moveTo(_globeCenter.dx - _globeRadius, _globeCenter.dy + dy)
        ..quadraticBezierTo(
          _globeCenter.dx,
          _globeCenter.dy + dy * 1.75,
          _globeCenter.dx + _globeRadius,
          _globeCenter.dy + dy,
        );
      _neonPath(c, p, AppColors.electricBlue, 1.1);
    }
    c.restore();

    // Emerald location ping — the "country of the round".
    final ping = _globeCenter + const Offset(-7, -5);
    c.drawCircle(
      ping,
      4.5,
      Paint()
        ..color = AppColors.emerald.withValues(alpha: .35 * glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    c.drawCircle(
      ping,
      2.2,
      Paint()..color = Color.lerp(AppColors.emerald, Colors.white, .3)!,
    );
  }

  void _paintGavel(Canvas c) {
    final contact = _globeCenter + _strikeDir * _globeRadius;
    final headCenter = _globeCenter + _strikeDir * (_globeRadius + 7);
    final angle = math.atan2(_strikeDir.dy, _strikeDir.dx);

    c.save();
    c.translate(headCenter.dx, headCenter.dy);
    c.rotate(angle);

    // Local space: +x runs along the handle, away from the globe.
    final handle = RRect.fromRectAndRadius(
      const Rect.fromLTRB(7, -3, 32, 3),
      const Radius.circular(3),
    );
    final head = RRect.fromRectAndRadius(
      const Rect.fromLTRB(-5, -12, 5, 12),
      const Radius.circular(4),
    );

    // Purple neon underglow for both parts.
    final glowPaint = Paint()
      ..color = AppColors.neonPurple.withValues(alpha: .50 * glow)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    c.drawRRect(head.inflate(1), glowPaint);
    c.drawRRect(handle.inflate(1), glowPaint);

    c.drawRRect(
      handle,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(7, 0),
          const Offset(32, 0),
          [AppColors.neonPurple, AppColors.electricBlue],
        ),
    );
    c.drawRRect(
      head,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, -12),
          const Offset(0, 12),
          [Color.lerp(AppColors.neonPurple, Colors.white, .25)!, AppColors.neonPurple],
        ),
    );
    // Crisp edge highlight on the mallet head.
    c.drawRRect(
      head,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: .35),
    );
    c.restore();

    // Amber impact sparks fanning out from the strike point.
    final perp = Offset(-_strikeDir.dy, _strikeDir.dx);
    for (final side in const [1.0, -1.0]) {
      for (final tilt in const [0.0, 0.45]) {
        final raw = perp * side + _strikeDir * tilt;
        final dir = raw / raw.distance;
        final from = contact + dir * 5;
        final to = contact + dir * (10 - tilt * 3);
        c.drawLine(
          from,
          to,
          Paint()
            ..strokeWidth = 3.4
            ..strokeCap = StrokeCap.round
            ..color = AppColors.amber.withValues(alpha: .40 * glow)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
        );
        c.drawLine(
          from,
          to,
          Paint()
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round
            ..color = Color.lerp(AppColors.amber, Colors.white, .35)!
                .withValues(alpha: (.55 + .45 * glow).clamp(0.0, 1.0).toDouble()),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.glow != glow;
}
