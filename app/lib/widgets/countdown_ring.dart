import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/game_state.dart';
import '../theme/app_theme.dart';
import 'glass_container.dart';

/// Turn countdown bar: a depleting neon ring + seconds, the current speaker,
/// and a pause/resume toggle. Turns neon-red and pulses in the final seconds.
///
/// Each section subscribes to [GameState] separately via `context.select`, so
/// the 1-second tick rebuilds only the ring — the speaker label and pause
/// button rebuild only when their own values change.
class TurnTimerBar extends StatelessWidget {
  const TurnTimerBar({super.key});

  @override
  Widget build(BuildContext context) {
    // Red urgency chrome from the 10s warning mark onward.
    final warn = context.select((GameState g) => g.isWarn && !g.isPaused);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(
          color: warn
              ? AppColors.ruby.withValues(alpha: .7)
              : Colors.transparent,
          width: 1.4,
        ),
        boxShadow: warn
            ? AppShadows.glow(AppColors.rubyDeep, alpha: .28, blur: 22)
            : null,
      ),
      child: GlassContainer(
        radius: AppRadii.card,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: const Row(
          children: [
            _RingSection(),
            SizedBox(width: 14),
            Expanded(child: _SpeakerInfo()),
            _PauseSection(),
          ],
        ),
      ),
    );
  }
}

/// The only part that rebuilds on every timer tick.
class _RingSection extends StatelessWidget {
  const _RingSection();

  @override
  Widget build(BuildContext context) {
    final secondsLeft = context.select((GameState g) => g.secondsLeft);
    final warn = context.select((GameState g) => g.isWarn);
    final danger = context.select((GameState g) => g.isDanger);
    final paused = context.select((GameState g) => g.isPaused);
    return CountdownRing(
      secondsLeft: secondsLeft,
      warn: warn,
      danger: danger,
      paused: paused,
    );
  }
}

class _SpeakerInfo extends StatelessWidget {
  const _SpeakerInfo();

  @override
  Widget build(BuildContext context) {
    final speaker = context.select((GameState g) => g.currentPlayerName);
    final paused = context.select((GameState g) => g.isPaused);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'الدور على',
          style: AppText.ui(size: 11, color: AppColors.textSecondary),
        ),
        Text(
          speaker,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.ui(size: 17, weight: FontWeight.w800),
        ),
        if (paused)
          Text(
            '⏸ متوقّف مؤقتاً',
            style: AppText.ui(size: 11, color: AppColors.amber),
          ),
      ],
    );
  }
}

class _PauseSection extends StatelessWidget {
  const _PauseSection();

  @override
  Widget build(BuildContext context) {
    final paused = context.select((GameState g) => g.isPaused);
    return _PauseButton(
      paused: paused,
      onTap: context.read<GameState>().togglePause,
    );
  }
}

/// Pure presentational countdown ring: depleting arc + seconds number.
/// Neon-blue while calm; at [GameState.warnThreshold] it shifts to urgent
/// red and starts pulsing, and at [GameState.dangerThreshold] the pulse
/// ACCELERATES. State-agnostic (takes plain values), so it is reusable and
/// widget-testable without a provider.
class CountdownRing extends StatefulWidget {
  final int secondsLeft;
  final bool warn;
  final bool danger;
  final bool paused;

  const CountdownRing({
    super.key,
    required this.secondsLeft,
    required this.warn,
    required this.danger,
    required this.paused,
  });

  @override
  State<CountdownRing> createState() => _CountdownRingState();
}

class _CountdownRingState extends State<CountdownRing>
    with SingleTickerProviderStateMixin {
  static const _warnBeat = Duration(milliseconds: 640);
  static const _dangerBeat = Duration(milliseconds: 360);

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: _warnBeat,
  );

  bool get _shouldPulse => widget.warn && !widget.paused;

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(CountdownRing old) {
    super.didUpdateWidget(old);
    _syncPulse();
  }

  void _syncPulse() {
    final beat = widget.danger ? _dangerBeat : _warnBeat;
    if (_shouldPulse) {
      // (Re)start when newly pulsing or when the tempo steps up at the
      // danger mark — repeat() picks up the new duration.
      if (!_pulse.isAnimating || _pulse.duration != beat) {
        _pulse
          ..duration = beat
          ..repeat(reverse: true);
      }
    } else if (_pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = (widget.secondsLeft / GameState.turnDuration).clamp(
      0.0,
      1.0,
    );

    return SizedBox(
      width: 58,
      height: 58,
      // Outer tween glides the arc smoothly between the 1-second ticks.
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 1, end: progress),
        duration: const Duration(milliseconds: 950),
        curve: Curves.linear,
        builder: (context, animatedProgress, _) => AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final t = Curves.easeInOut.transform(_pulse.value);
            final glow = widget.paused
                ? 0.0
                : (_shouldPulse ? 0.5 + 0.5 * t : 0.55);
            final scale = _shouldPulse ? 1.0 + 0.10 * t : 1.0;
            // Nervous jitter in the critical final seconds: a fast sine
            // riding the pulse controller, ±1.6px.
            final jitter = widget.danger && !widget.paused
                ? math.sin(_pulse.value * math.pi * 8) * 1.6
                : 0.0;
            return Transform.translate(
              offset: Offset(jitter, 0),
              child: _buildRing(animatedProgress, t, glow, scale),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRing(
      double animatedProgress, double t, double glow, double scale) {
    final Color accent = widget.paused
        ? AppColors.textSecondary
        : (widget.warn ? AppColors.ruby : AppColors.electricBlue);
    final Color numberColor = widget.paused
        ? AppColors.textSecondary
        : (widget.warn ? AppColors.ruby : Colors.white);
    return CustomPaint(
              painter: _RingPainter(
                progress: animatedProgress,
                color: accent,
                glow: glow,
              ),
              child: Center(
                child: Transform.scale(
                  scale: scale,
                  child: Text(
                    '${widget.secondsLeft}',
                    style: AppText.number(
                      size: 22,
                      weight: FontWeight.w800,
                      color: numberColor,
                    ),
                  ),
                ),
              ),
            );
  }
}

class _RingPainter extends CustomPainter {
  final double progress; // 1.0 (full) → 0.0 (empty)
  final Color color;
  final double glow; // 0..1

  const _RingPainter({
    required this.progress,
    required this.color,
    required this.glow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const stroke = 5.0;
    final radius = (size.shortestSide - stroke) / 2 - 1;

    // Faint full track.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = AppColors.stroke,
    );

    if (progress <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const start = -math.pi / 2; // 12 o'clock
    final sweep = progress * 2 * math.pi;

    // Blurred neon underglow.
    if (glow > 0) {
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: 0.6 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
    // Crisp core arc.
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color || old.glow != glow;
}

class _PauseButton extends StatelessWidget {
  final bool paused;
  final VoidCallback onTap;

  const _PauseButton({required this.paused, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = paused ? AppColors.amber : AppColors.textSecondary;
    return Tooltip(
      message: paused ? 'استئناف الوقت' : 'إيقاف الوقت مؤقتاً',
      child: Material(
        color: paused
            ? AppColors.amber.withValues(alpha: .14)
            : AppColors.glassTint,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: paused
                    ? AppColors.amber.withValues(alpha: .55)
                    : AppColors.stroke,
              ),
            ),
            child: Icon(
              paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              size: 26,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
