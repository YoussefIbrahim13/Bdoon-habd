import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A continuously rotating night-side Earth, drawn entirely in code (no
/// image assets — matching the app's CustomPainter aesthetic). City-light
/// dots are clustered over the real continents and projected onto a sphere,
/// so the Y-axis spin reads as a recognizable globe. A soft violet glow
/// sits behind it; meant to live UNDER a headline in a Stack.
///
/// The dot field is generated once (seeded, stable) and only the rotation
/// phase animates, so the per-frame cost is a cheap projection + point draw
/// inside a RepaintBoundary.
class RotatingGlobe extends StatefulWidget {
  final double size;

  /// Seconds for one full revolution.
  final double periodSeconds;

  const RotatingGlobe({super.key, this.size = 260, this.periodSeconds = 24});

  @override
  State<RotatingGlobe> createState() => _RotatingGlobeState();
}

class _RotatingGlobeState extends State<RotatingGlobe>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (widget.periodSeconds * 1000).round()),
  )..repeat();

  late final List<_CityLight> _lights = _generateLights();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _spin,
        builder: (context, _) => CustomPaint(
          size: Size.square(widget.size),
          painter: _GlobePainter(
            lights: _lights,
            phase: _spin.value * 2 * math.pi,
          ),
        ),
      ),
    );
  }
}

/// A dot on the sphere in geographic coordinates (radians) + a stable tint
/// mix (0 = violet, 1 = cyan).
class _CityLight {
  final double lat;
  final double lon;
  final double tint;
  final double baseRadius;

  const _CityLight(this.lat, this.lon, this.tint, this.baseRadius);
}

/// Continent seed centers (lat°, lon°) and how many lights each carries —
/// enough to make the landmasses recognizable as they rotate past.
const List<(double, double, int)> _continents = [
  (48, -100, 26), // North America
  (-12, -58, 20), // South America
  (50, 12, 22), // Europe
  (4, 20, 26), // Africa
  (46, 92, 30), // North + Central Asia
  (22, 78, 16), // India / South Asia
  (12, 105, 14), // Southeast Asia
  (-26, 133, 12), // Oceania
];

List<_CityLight> _generateLights() {
  final rng = math.Random(42); // stable field across rebuilds
  final lights = <_CityLight>[];
  for (final (latDeg, lonDeg, count) in _continents) {
    for (var i = 0; i < count; i++) {
      // Gaussian-ish scatter around the seed so clusters have soft edges.
      final dLat = (rng.nextDouble() - rng.nextDouble()) * 16;
      final dLon = (rng.nextDouble() - rng.nextDouble()) * 22;
      lights.add(_CityLight(
        (latDeg + dLat) * math.pi / 180,
        (lonDeg + dLon) * math.pi / 180,
        rng.nextDouble(),
        1.1 + rng.nextDouble() * 1.4,
      ));
    }
  }
  return lights;
}

class _GlobePainter extends CustomPainter {
  final List<_CityLight> lights;
  final double phase;

  const _GlobePainter({required this.lights, required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2 * 0.78; // leave room for the glow halo

    // Soft violet glow behind the globe.
    canvas.drawCircle(
      center,
      r * 1.35,
      Paint()
        ..shader = ui.Gradient.radial(center, r * 1.35, [
          AppColors.accentGlow.withValues(alpha: .34),
          AppColors.accentGlow.withValues(alpha: 0),
        ]),
    );

    // The dark ocean sphere with a subtle day/terminator shade.
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(center.dx - r * .3, center.dy - r * .3),
          r * 1.5,
          [const Color(0xFF241a44), const Color(0xFF0A0716)],
        ),
    );

    // City lights, back hemisphere culled, brightness scaled by facing.
    final visible = <(Offset, double, _CityLight)>[];
    for (final c in lights) {
      final lon = c.lon + phase;
      final cosLat = math.cos(c.lat);
      final x = cosLat * math.sin(lon);
      final z = cosLat * math.cos(lon); // >0 = front hemisphere
      if (z <= 0.02) continue;
      final y = math.sin(c.lat);
      final px = center.dx + x * r;
      final py = center.dy - y * r;
      visible.add((Offset(px, py), z, c));
    }
    // Draw dimmer/back-most first so brighter front dots sit on top.
    visible.sort((a, b) => a.$2.compareTo(b.$2));
    for (final (pos, z, c) in visible) {
      final color = Color.lerp(
        AppColors.displayViolet,
        AppColors.electricBlue,
        c.tint,
      )!;
      final facing = z.clamp(0.0, 1.0);
      final dotR = c.baseRadius * (0.55 + 0.45 * facing);
      // Blurred halo.
      canvas.drawCircle(
        pos,
        dotR * 2.2,
        Paint()
          ..color = color.withValues(alpha: 0.28 * facing)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      );
      // Crisp core.
      canvas.drawCircle(
        pos,
        dotR,
        Paint()
          ..color = Color.lerp(color, Colors.white, 0.35 * facing)!
              .withValues(alpha: (0.5 + 0.5 * facing)),
      );
    }

    // Atmosphere rim: a bright thin arc on the light-facing edge.
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..shader = ui.Gradient.linear(
          Offset(center.dx - r, center.dy - r),
          Offset(center.dx + r, center.dy + r),
          [
            AppColors.accentGlow.withValues(alpha: .7),
            AppColors.displayViolet.withValues(alpha: .1),
          ],
        ),
    );
  }

  @override
  bool shouldRepaint(_GlobePainter old) => old.phase != phase;
}
