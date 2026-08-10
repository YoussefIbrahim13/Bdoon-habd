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
// Fireworks (match over)
// ---------------------------------------------------------------------------

/// Celebratory volley of fireworks for the winner's podium: shells rise from
/// off-screen, flash, and scatter into gravity-pulled sparks.
///
/// One-shot like everything else here — a [trigger] bump plays [volleys]
/// rounds and then settles to an empty box, so `pumpAndSettle` still
/// terminates and an idle podium costs nothing.
class FireworksLayer extends StatefulWidget {
  final int trigger;

  /// Rounds of ~4 shells. Four volleys is roughly 6.5s of celebration.
  final int volleys;

  const FireworksLayer({super.key, required this.trigger, this.volleys = 4});

  @override
  State<FireworksLayer> createState() => _FireworksLayerState();
}

class _FireworksLayerState extends State<FireworksLayer>
    with SingleTickerProviderStateMixin {
  static const _shellsPerVolley = 4;
  static const _volleyMs = 1600;

  /// A shell's whole life (rise + burst) as a fraction of the full show.
  late final double _life;

  late final AnimationController _show = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _volleyMs * widget.volleys),
  );
  List<_Shell> _shells = const [];

  @override
  void initState() {
    super.initState();
    _life = 1700 / (_volleyMs * widget.volleys);
    if (widget.trigger > 0) _play();
  }

  @override
  void didUpdateWidget(FireworksLayer old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger && widget.trigger > 0) _play();
  }

  void _play() {
    final rng = math.Random(widget.trigger);
    const palette = [
      AppColors.amber,
      AppColors.electricBlue,
      AppColors.emerald,
      AppColors.accentGlow,
      AppColors.ruby,
      AppColors.primaryViolet,
    ];
    final count = _shellsPerVolley * widget.volleys;
    _shells = List.generate(count, (i) {
      // Spread launches evenly across the show, then jitter so volleys don't
      // read as a metronome.
      final slot = i / count;
      final start = (slot + (rng.nextDouble() - .5) * .05).clamp(0.0, 1 - _life);
      final burstX = .16 + rng.nextDouble() * .68;
      return _Shell(
        startT: start,
        life: _life,
        riseFrac: .34 + rng.nextDouble() * .1,
        launchX: (burstX + (rng.nextDouble() - .5) * .22).clamp(.05, .95),
        burstX: burstX,
        burstY: .18 + rng.nextDouble() * .34,
        color: palette[(i + rng.nextInt(palette.length)) % palette.length],
        sparks: List.generate(26, (k) {
          // Even angular spread + jitter keeps the burst round, not clumpy.
          final angle =
              k / 26 * 2 * math.pi + (rng.nextDouble() - .5) * .22;
          return _Spark(
            angle: angle,
            speed: .55 + rng.nextDouble() * .55,
            size: 1.5 + rng.nextDouble() * 1.9,
            phase: rng.nextDouble() * 2,
          );
        }),
      );
    });
    _show.forward(from: 0);
  }

  @override
  void dispose() {
    _show.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _show,
          builder: (context, _) {
            if (!_show.isAnimating) return const SizedBox.shrink();
            return CustomPaint(
              size: Size.infinite,
              painter: _FireworksPainter(shells: _shells, t: _show.value),
            );
          },
        ),
      ),
    );
  }
}

class _Spark {
  final double angle, speed, size, phase;
  const _Spark({
    required this.angle,
    required this.speed,
    required this.size,
    required this.phase,
  });
}

class _Shell {
  final double startT, life, riseFrac, launchX, burstX, burstY;
  final Color color;
  final List<_Spark> sparks;
  const _Shell({
    required this.startT,
    required this.life,
    required this.riseFrac,
    required this.launchX,
    required this.burstX,
    required this.burstY,
    required this.color,
    required this.sparks,
  });
}

class _FireworksPainter extends CustomPainter {
  final List<_Shell> shells;
  final double t; // 0..1 across the whole show

  const _FireworksPainter({required this.shells, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final reach = size.shortestSide * .34;
    for (final s in shells) {
      final local = (t - s.startT) / s.life;
      if (local <= 0 || local >= 1) continue;

      final burst = Offset(s.burstX * size.width, s.burstY * size.height);

      if (local < s.riseFrac) {
        // Rising shell: a bright head with a short tail behind it.
        final p = local / s.riseFrac;
        final eased = Curves.easeOutQuad.transform(p);
        final from = Offset(s.launchX * size.width, size.height * 1.05);
        final head = Offset.lerp(from, burst, eased)!;
        final tail = Offset.lerp(
          from,
          burst,
          Curves.easeOutQuad.transform((p - .09).clamp(0.0, 1.0)),
        )!;
        canvas.drawLine(
          tail,
          head,
          Paint()
            ..color = s.color.withValues(alpha: .5)
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawCircle(
          head,
          2.3,
          Paint()..color = Colors.white.withValues(alpha: .92),
        );
        continue;
      }

      // Burst: sparks fly out, decelerate, then sag under gravity.
      final b = (local - s.riseFrac) / (1 - s.riseFrac);
      final eased = Curves.easeOutCubic.transform(b);
      final fade = math.pow(1 - b, 1.5).toDouble();

      if (b < .18) {
        // Muzzle flash at the detonation point.
        final f = 1 - b / .18;
        canvas.drawCircle(
          burst,
          18 * f,
          Paint()
            ..color = Colors.white.withValues(alpha: .45 * f)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
        );
      }

      for (final sp in s.sparks) {
        final r = eased * reach * sp.speed;
        final gravity = .45 * b * b * reach;
        final pos = burst +
            Offset(math.cos(sp.angle) * r, math.sin(sp.angle) * r + gravity);
        // Sparks start white-hot and cool into the shell's color.
        final color = Color.lerp(Colors.white, s.color, (b * 2.4).clamp(0, 1))!;
        final twinkle = .6 + .4 * math.sin((b * 16 + sp.phase) * math.pi);
        canvas.drawCircle(
          pos,
          sp.size * (1 - b * .4),
          Paint()
            ..color = color.withValues(alpha: (fade * twinkle).clamp(0.0, 1.0)),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_FireworksPainter old) => old.t != t;
}

// ---------------------------------------------------------------------------
// Result face (match over)
// ---------------------------------------------------------------------------

/// The big emoji at the top of the end-of-match screen: pops in with an
/// elastic overshoot, settles through two decaying bobs, and sits over a
/// colored glow. Plays once and settles.
class ResultFace extends StatefulWidget {
  final String emoji;
  final Color glow;
  final double size;

  const ResultFace({
    super.key,
    required this.emoji,
    required this.glow,
    this.size = 84,
  });

  @override
  State<ResultFace> createState() => _ResultFaceState();
}

class _ResultFaceState extends State<ResultFace>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..forward();

  @override
  void didUpdateWidget(ResultFace old) {
    super.didUpdateWidget(old);
    // A changed result (rare, e.g. a late score sync) replays the reveal.
    if (widget.emoji != old.emoji) _in.forward(from: 0);
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _in,
      builder: (context, _) {
        final t = _in.value;
        // Elastic pop over the first 40%, then decaying bobs.
        final pop = t < .4
            ? Curves.elasticOut.transform(t / .4)
            : 1.0;
        final bobT = ((t - .4) / .6).clamp(0.0, 1.0);
        final bob = math.sin(bobT * math.pi * 4) * 6 * (1 - bobT);
        final glowA = (.20 + .16 * (1 - bobT)) * pop.clamp(0.0, 1.0);

        return Transform.translate(
          offset: Offset(0, -bob),
          child: Transform.scale(
            scale: pop,
            child: Container(
              width: widget.size * 1.6,
              height: widget.size * 1.6,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    widget.glow.withValues(alpha: glowA),
                    widget.glow.withValues(alpha: 0),
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
              child: Text(
                widget.emoji,
                style: TextStyle(fontSize: widget.size),
              ),
            ),
          ),
        );
      },
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
