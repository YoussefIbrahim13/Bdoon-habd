import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Zero-asset "juice" toolkit: confetti bursts, screen shake, color flashes,
/// animated counters, and the app's signature page transition. Everything is
/// CustomPaint / plain animation controllers — no images, no packages.
///
/// All effect widgets are ONE-SHOT (they play and settle), driven by a
/// monotonic `trigger` counter: bump the int, the effect replays. This keeps
/// them test-friendly (pumpAndSettle-safe once finished) and dead cheap when
/// idle (they build a SizedBox.shrink).

// ---------------------------------------------------------------------------
// Page transition
// ---------------------------------------------------------------------------

/// Silky fade + slide-up push, replacing rigid MaterialPageRoute jumps.
/// Short enough (360ms) that existing bounded test pumps still land on the
/// destination.
class NovaPageRoute<T> extends PageRouteBuilder<T> {
  NovaPageRoute({required Widget Function(BuildContext) builder})
      : super(
          transitionDuration: const Duration(milliseconds: 360),
          reverseTransitionDuration: const Duration(milliseconds: 280),
          pageBuilder: (context, _, _) => builder(context),
          transitionsBuilder: (context, animation, _, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeIn,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, .06),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        );
}

// ---------------------------------------------------------------------------
// Confetti burst (صح!)
// ---------------------------------------------------------------------------

/// Full-area neon particle burst. Idle = zero cost; each [trigger] bump
/// replays one ~900ms burst from the widget's center.
class ConfettiLayer extends StatefulWidget {
  final int trigger;
  final Color color;

  const ConfettiLayer({
    super.key,
    required this.trigger,
    this.color = AppColors.emerald,
  });

  @override
  State<ConfettiLayer> createState() => _ConfettiLayerState();
}

class _ConfettiLayerState extends State<ConfettiLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  List<_Particle> _particles = const [];

  @override
  void didUpdateWidget(ConfettiLayer old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger && widget.trigger > 0) _play();
  }

  void _play() {
    final rng = math.Random(widget.trigger); // varied but deterministic
    _particles = List.generate(42, (i) {
      final angle = rng.nextDouble() * 2 * math.pi;
      final speed = .35 + rng.nextDouble() * .95;
      return _Particle(
        vx: math.cos(angle) * speed,
        vy: math.sin(angle) * speed - .55, // launch upward-biased
        size: 2.2 + rng.nextDouble() * 3.4,
        spin: (rng.nextDouble() - .5) * 10,
        whiten: rng.nextDouble() * .55,
      );
    });
    _burst.forward(from: 0);
  }

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _burst,
        builder: (context, _) {
          if (!_burst.isAnimating) return const SizedBox.shrink();
          return CustomPaint(
            size: Size.infinite,
            painter: _ConfettiPainter(
              particles: _particles,
              t: _burst.value,
              color: widget.color,
            ),
          );
        },
      ),
    );
  }
}

class _Particle {
  final double vx, vy, size, spin, whiten;
  const _Particle({
    required this.vx,
    required this.vy,
    required this.size,
    required this.spin,
    required this.whiten,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles;
  final double t; // 0..1
  final Color color;

  const _ConfettiPainter({
    required this.particles,
    required this.t,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final reach = size.shortestSide * .55;
    final fade = (1 - t).clamp(0.0, 1.0);
    final eased = Curves.easeOutCubic.transform(t);
    for (final p in particles) {
      final gravity = .8 * t * t; // particles arc downward
      final pos = center +
          Offset(p.vx * eased * reach, (p.vy * eased + gravity) * reach);
      final paint = Paint()
        ..color = Color.lerp(color, Colors.white, p.whiten)!
            .withValues(alpha: fade);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(p.spin * t);
      // Tiny neon shards: rounded bars read better than dots when spinning.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset.zero, width: p.size * 2.4, height: p.size),
          Radius.circular(p.size / 2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

// ---------------------------------------------------------------------------
// Screen shake + color flash (هبد!)
// ---------------------------------------------------------------------------

/// Wrap content in a decaying horizontal shake. Bump [trigger] to shake.
class ShakeWrapper extends StatefulWidget {
  final int trigger;
  final Widget child;

  const ShakeWrapper({super.key, required this.trigger, required this.child});

  @override
  State<ShakeWrapper> createState() => _ShakeWrapperState();
}

class _ShakeWrapperState extends State<ShakeWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void didUpdateWidget(ShakeWrapper old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger && widget.trigger > 0) {
      _shake.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shake,
      child: widget.child,
      builder: (context, child) {
        final t = _shake.value;
        // 5 oscillations decaying to zero.
        final dx =
            _shake.isAnimating ? math.sin(t * math.pi * 10) * 7 * (1 - t) : 0.0;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
    );
  }
}

/// Brief full-surface color flash (defaults to ruby). Bump [trigger].
class FlashOverlay extends StatefulWidget {
  final int trigger;
  final Color color;

  const FlashOverlay({
    super.key,
    required this.trigger,
    this.color = AppColors.rubyDeep,
  });

  @override
  State<FlashOverlay> createState() => _FlashOverlayState();
}

class _FlashOverlayState extends State<FlashOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  @override
  void didUpdateWidget(FlashOverlay old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger && widget.trigger > 0) {
      _flash.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _flash,
        builder: (context, _) {
          if (!_flash.isAnimating) return const SizedBox.shrink();
          // Sharp attack, soft decay.
          final a = (1 - _flash.value) * .22;
          return ColoredBox(
            color: widget.color.withValues(alpha: a),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Animated numbers
// ---------------------------------------------------------------------------

/// Integer that rolls smoothly to new values instead of jumping.
class AnimatedCount extends StatelessWidget {
  final int value;
  final TextStyle style;
  final Duration duration;

  const AnimatedCount({
    super.key,
    required this.value,
    required this.style,
    this.duration = const Duration(milliseconds: 550),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text('${v.round()}', style: style),
    );
  }
}
