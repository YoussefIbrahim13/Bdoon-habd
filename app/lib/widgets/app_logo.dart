import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The بدون هبد! brand mark — a claim being judged:
/// a neon speech bubble (the spoken "fact") holding a bold emerald verdict
/// check, with a ruby ✗ badge bursting off its corner (the "هبد!" getting
/// caught) and amber impact sparks for party-game energy.
///
/// Drawn entirely with [CustomPainter]: no image assets, scales losslessly to
/// any size, and the neon intensity is externally animatable via [glow]
/// (0 → dim, 1 → full pulse) so splash/idle screens can "breathe" it.
class AppLogo extends StatelessWidget {
  final double size;

  /// Neon intensity 0..1 — drive this from an animation for a pulse effect.
  final double glow;

  /// When false, the rounded gradient-border badge is omitted and only the
  /// bubble/verdict emblem is drawn (transparent behind it). Used for the
  /// Android adaptive-icon foreground and for embedding the emblem on an
  /// existing gradient capsule (e.g. the home screen).
  final bool showBadge;

  const AppLogo({
    super.key,
    this.size = 120,
    this.glow = .8,
    this.showBadge = true,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      // Isolates frequent glow repaints from the rest of the tree.
      child: CustomPaint(
        size: Size.square(size),
        painter: _LogoPainter(
          glow: glow.clamp(0.0, 1.0).toDouble(),
          showBadge: showBadge,
        ),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  final double glow;
  final bool showBadge;

  _LogoPainter({required this.glow, this.showBadge = true});

  // All geometry lives in a 100×100 design space, scaled to the actual size.

  // Speech bubble body (the spoken claim).
  static const _bubble = Rect.fromLTRB(18, 26, 82, 70);
  static const _bubbleRadius = 14.0;

  // Ruby ✗ badge riding the bubble's top-right corner.
  static const _crossCenter = Offset(79, 24);
  static const _crossArm = 6.5;
  static const _crossDisc = 11.5;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.shortestSide / 100);
    if (showBadge) _paintBadge(canvas);
    _paintBubble(canvas);
    _paintCheck(canvas);
    _paintCrossBadge(canvas);
    _paintSparks(canvas);
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
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: .45 * glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
    );
    c.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
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

  /// One continuous outline: rounded rect + a tail flicking down-left
  /// (RTL-friendly — the speaker "sits" on the right-to-left reading side).
  Path _bubblePath() {
    const b = _bubble;
    const r = _bubbleRadius;
    const radius = Radius.circular(r);
    return Path()
      ..moveTo(b.left + r, b.top)
      ..lineTo(b.right - r, b.top)
      ..arcToPoint(Offset(b.right, b.top + r), radius: radius)
      ..lineTo(b.right, b.bottom - r)
      ..arcToPoint(Offset(b.right - r, b.bottom), radius: radius)
      // Bottom edge runs right→left, detours through the tail, and returns.
      ..lineTo(46, b.bottom)
      ..lineTo(30, 84) // tail tip
      ..lineTo(34, b.bottom)
      ..lineTo(b.left + r, b.bottom)
      ..arcToPoint(Offset(b.left, b.bottom - r), radius: radius)
      ..lineTo(b.left, b.top + r)
      ..arcToPoint(Offset(b.left + r, b.top), radius: radius)
      ..close();
  }

  void _paintBubble(Canvas c) {
    // Whisper of a fill so the bubble reads as a surface, not just wire.
    c.drawPath(
      _bubblePath(),
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(18, 26),
          const Offset(82, 70),
          [
            AppColors.electricBlue.withValues(alpha: .10 * glow),
            AppColors.neonPurple.withValues(alpha: .06 * glow),
          ],
        ),
    );
    _neonPath(c, _bubblePath(), AppColors.electricBlue, 2.4);
  }

  /// The verdict: a bold emerald check filling the bubble.
  void _paintCheck(Canvas c) {
    final check = Path()
      ..moveTo(34, 48)
      ..lineTo(45, 59)
      ..lineTo(66, 37);
    _neonPath(c, check, AppColors.emerald, 5);
  }

  /// The busted claim: a ruby ✗ pinned to the bubble's corner like a
  /// notification badge.
  void _paintCrossBadge(Canvas c) {
    // Dark disc lifts the ✗ off the bubble outline behind it.
    c.drawCircle(
      _crossCenter,
      _crossDisc,
      Paint()..color = const Color(0xFF15171F),
    );
    c.drawCircle(
      _crossCenter,
      _crossDisc,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = AppColors.ruby.withValues(alpha: .55),
    );
    final cross = Path()
      ..moveTo(_crossCenter.dx - _crossArm, _crossCenter.dy - _crossArm)
      ..lineTo(_crossCenter.dx + _crossArm, _crossCenter.dy + _crossArm)
      ..moveTo(_crossCenter.dx + _crossArm, _crossCenter.dy - _crossArm)
      ..lineTo(_crossCenter.dx - _crossArm, _crossCenter.dy + _crossArm);
    _neonPath(c, cross, AppColors.ruby, 3.4);
  }

  /// Amber impact sparks fanning off the ✗ — the "هبد!" exclamation energy.
  void _paintSparks(Canvas c) {
    for (final angleDeg in const [-55.0, -10.0, 35.0]) {
      final a = angleDeg * math.pi / 180;
      final dir = Offset(math.cos(a), math.sin(a));
      final from = _crossCenter + dir * (_crossDisc + 2.5);
      final to = _crossCenter + dir * (_crossDisc + 8.5);
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

  @override
  bool shouldRepaint(_LogoPainter old) =>
      old.glow != glow || old.showBadge != showBadge;
}
