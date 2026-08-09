import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Frosted-glass panel: blurred backdrop, translucent fill, hairline border.
///
/// The tint is composited over a dark violet base before painting, so the
/// surface reads as dark from its first frame even while the blur's shader is
/// still warming up — an 8%-alpha tint alone would let a bare canvas through.
/// The [BackdropFilter] is wrapped in a hard-edge [ClipRRect] to keep its
/// repaint bounds off the rest of the screen, and lives inside a
/// [RepaintBoundary] so ambient animation behind it never re-rasterizes it.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double radius;
  final double blur;
  final Color? tint;
  final EdgeInsetsGeometry? padding;

  /// Blur cost grows with sigma, and past ~12 the difference is invisible on
  /// a dark, low-contrast backdrop. Callers asking for more get this.
  static const maxBlurSigma = 12.0;

  const GlassContainer({
    super.key,
    required this.child,
    this.radius = AppRadii.card,
    this.blur = 12,
    this.tint,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final sigma = blur.clamp(0.0, maxBlurSigma);
    final fill = Color.alphaBlend(
      tint ?? AppColors.glassTint,
      AppColors.bg.withValues(alpha: .55),
    );
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: borderRadius,
        clipBehavior: Clip.hardEdge,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: borderRadius,
              border: Border.all(color: AppColors.stroke),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Card wrapped in a gradient border with an optional colored glow.
/// Used for the hero flag card and Smart Judge verdict cards.
class GradientBorderCard extends StatelessWidget {
  final Widget child;
  final Gradient gradient;
  final double radius;
  final double borderWidth;
  final Color innerColor;
  final List<BoxShadow>? shadows;
  final EdgeInsetsGeometry? padding;

  const GradientBorderCard({
    super.key,
    required this.child,
    required this.gradient,
    this.radius = AppRadii.card,
    this.borderWidth = 1.8,
    this.innerColor = AppColors.surface,
    this.shadows,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadows,
      ),
      padding: EdgeInsets.all(borderWidth),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: innerColor,
          borderRadius: BorderRadius.circular(radius - borderWidth),
        ),
        child: child,
      ),
    );
  }
}

/// Soft radial color blobs + slow-drifting neon embers behind every screen —
/// gives the obsidian background living depth without competing with content.
///
/// Layered for a zero-cost first frame: an **opaque [AppColors.bg] fill comes
/// first**, so a screen is dark violet the instant it mounts rather than
/// inheriting whatever is behind the route mid-transition. The static blobs
/// and the animated ember field each sit in their own [RepaintBoundary], so
/// the ember tick never re-rasterizes the blobs or the foreground.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(child: RepaintBoundary(child: _StaticBackdrop())),
          Positioned.fill(child: RepaintBoundary(child: _EmberField())),
        ],
      ),
    );
  }
}

/// Opaque base + the two static glow blobs: rasterized once, then reused.
class _StaticBackdrop extends StatelessWidget {
  const _StaticBackdrop();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.bg,
      child: Stack(
        children: [
          Positioned(
              top: -140, right: -90, child: _Blob(AppColors.electricBlue, 340)),
          Positioned(
              bottom: -160, left: -110, child: _Blob(AppColors.neonPurple, 400)),
        ],
      ),
    );
  }
}

/// ~16 ultra-faint embers rising on individual phase offsets. One looping
/// controller; per-frame cost is 16 tiny blurred dots.
class _EmberField extends StatefulWidget {
  const _EmberField();

  @override
  State<_EmberField> createState() => _EmberFieldState();
}

class _EmberFieldState extends State<_EmberField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 30),
  )..repeat();

  static final List<_Ember> _embers = _spawnEmbers();

  static List<_Ember> _spawnEmbers() {
    final rng = math.Random(7);
    return List.generate(16, (i) {
      return _Ember(
        x: rng.nextDouble(),
        phase: rng.nextDouble(),
        size: .8 + rng.nextDouble() * 1.9,
        sway: .01 + rng.nextDouble() * .03,
        cyan: rng.nextDouble() < .35,
      );
    });
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _drift,
      builder: (context, _) => CustomPaint(
        size: Size.infinite,
        painter: _EmberPainter(embers: _embers, t: _drift.value),
      ),
    );
  }
}

class _Ember {
  final double x, phase, size, sway;
  final bool cyan;
  const _Ember({
    required this.x,
    required this.phase,
    required this.size,
    required this.sway,
    required this.cyan,
  });
}

class _EmberPainter extends CustomPainter {
  final List<_Ember> embers;
  final double t;

  const _EmberPainter({required this.embers, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    // One reused Paint, and NO MaskFilter: a mask blur is an uncached
    // per-draw blur pass, and this ran 16 times a frame, forever, on every
    // screen. At a 1–3px radius plain anti-aliasing is indistinguishable.
    final paint = Paint()..isAntiAlias = true;
    for (final e in embers) {
      // Each ember loops bottom→top on its own phase; alpha fades at both
      // ends of the journey so spawns/despawns are invisible.
      final progress = (t + e.phase) % 1.0;
      final y = size.height * (1.05 - progress * 1.1);
      final x = size.width *
          (e.x + math.sin((progress * 4 + e.phase) * math.pi) * e.sway);
      final edgeFade = math.sin(progress * math.pi).clamp(0.0, 1.0);
      paint.color = (e.cyan ? AppColors.electricBlue : AppColors.accentGlow)
          .withValues(alpha: .16 * edgeFade);
      canvas.drawCircle(Offset(x, y), e.size, paint);
    }
  }

  @override
  bool shouldRepaint(_EmberPainter old) => old.t != t;
}

class _Blob extends StatelessWidget {
  final Color color;
  final double size;

  const _Blob(this.color, this.size);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Fade to the SAME hue at zero alpha, not to `Colors.transparent`
        // (transparent black), which premultiplies into a grey halo.
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: .14),
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}
