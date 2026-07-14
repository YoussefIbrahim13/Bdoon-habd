import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/country.dart';
import '../state/game_state.dart';
import '../theme/app_theme.dart';
import '../widgets/game_button.dart';
import '../widgets/glass_container.dart';
import '../widgets/pulse_on_change.dart';
import '../widgets/smart_judge_sheet.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final GameState _game;
  int _seenRounds = 0;

  @override
  void initState() {
    super.initState();
    _game = context.read<GameState>();
    _seenRounds = _game.roundsCompleted;
    // Fire one-shot round-end feedback for BOTH manual (غلط!) and automatic
    // (timeout) losses, which both flow through GameState.roundsCompleted.
    _game.addListener(_onGameChanged);
  }

  @override
  void dispose() {
    _game.removeListener(_onGameChanged);
    super.dispose();
  }

  void _onGameChanged() {
    if (_game.roundsCompleted != _seenRounds) {
      _seenRounds = _game.roundsCompleted;
      _announceRoundEnd();
    }
  }

  void _announceRoundEnd() {
    // Match-over shows its own screen; only snackbar for continuing play.
    if (!mounted || _game.phase != GamePhase.playing) return;
    final winner = _game.lastRoundWinner;
    if (winner == null) return;
    final timedOut = _game.lastRoundEndReason == RoundEndReason.timeout;
    final msg = timedOut
        ? '⏰ انتهى الوقت — هبدة! نقطة لـ ${_game.playerNames[winner]}'
        : '🏆 هبدة! نقطة لـ ${_game.playerNames[winner]} — جولة جديدة';
    // Defer to after the current notify/build cycle.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              msg,
              style: AppText.ui(size: 14, weight: FontWeight.w600),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
    });
  }

  Future<void> _confirmRuleFalse(GameState game) async {
    final speaker = game.currentPlayerName;
    // Freeze the clock while the judge deliberates in the dialog.
    final resumeAfter = !game.isPaused;
    if (resumeAfter) game.pause();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .6),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: GlassContainer(
          blur: 24,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'حكم نهائي؟',
                style: AppText.ui(size: 20, weight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Text(
                'معلومة "$speaker" غلط والجولة تنتهي؟',
                textAlign: TextAlign.center,
                style: AppText.ui(size: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: GameButton(
                      label: 'إلغاء',
                      height: 50,
                      onPressed: () => Navigator.pop(ctx, false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GameButton(
                      label: 'نعم، غلط',
                      height: 50,
                      gradient: AppGradients.falsehood,
                      glowColor: AppColors.rubyDeep,
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true) {
      // Round-end feedback is shown by the shared listener.
      game.ruleFalse();
    } else if (resumeAfter) {
      // Cancelled — restore the clock we paused.
      game.resume();
    }
  }

  void _openSmartJudge(GameState game) {
    final country = game.currentCountry;
    if (country == null) return;
    // Consulting the AI shouldn't burn the speaker's clock — auto-pause while
    // the sheet is open, and resume on close only if we were the one to pause.
    final resumeAfter = !game.isPaused;
    if (resumeAfter) game.pause();

    // Do NOT pass a custom transitionAnimationController built from this
    // State's vsync: once the sheet fully covers the game screen, TickerMode
    // mutes this route's tickers, freezing that controller — so the dismiss
    // animation never completes and the sheet can't be closed. Letting the
    // route create its own (overlay-vsync) controller keeps close working.
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true, // tap outside to close
      enableDrag: true, // swipe down to close
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .55),
      builder: (_) => SmartJudgeSheet(country: country),
    ).whenComplete(() {
      if (resumeAfter) game.resume();
    });
  }

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameState>();

    if (game.phase == GamePhase.matchOver) {
      return _MatchOverView(game: game);
    }
    final country = game.currentCountry;
    if (country == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Stack(
        children: [
          const AmbientBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
              child: Column(
                children: [
                  _TopBar(round: game.roundNumber, onSkip: game.skipCountry),
                  const SizedBox(height: 14),
                  _ScorePanel(game: game),
                  const SizedBox(height: 18),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        child: _HeroFlagCard(country: country),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _TurnTimerBar(game: game),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: GameButton(
                          label: 'غلط!',
                          icon: Icons.close_rounded,
                          height: 60,
                          gradient: AppGradients.falsehood,
                          glowColor: AppColors.rubyDeep,
                          onPressed: () => _confirmRuleFalse(game),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GameButton(
                          label: 'صح — التالي',
                          icon: Icons.check_rounded,
                          height: 60,
                          gradient: AppGradients.truth,
                          glowColor: AppColors.emeraldDeep,
                          onPressed: game.nextTurn,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GameButton(
                    label: 'اسأل الحكم الذكي',
                    icon: Icons.auto_awesome,
                    height: 56,
                    borderGradient: AppGradients.turn,
                    onPressed: () => _openSmartJudge(game),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  final int round;
  final VoidCallback onSkip;

  const _TopBar({required this.round, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.glassTint,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.stroke),
          ),
          child: Text(
            'الجولة $round',
            style: AppText.ui(size: 13, weight: FontWeight.w700),
          ),
        ),
        const Spacer(),
        _IconChip(
          icon: Icons.shuffle_rounded,
          tooltip: 'تغيير الدولة',
          onTap: onSkip,
        ),
      ],
    );
  }
}

class _IconChip extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _IconChip({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.glassTint,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.stroke),
            ),
            child: Icon(icon, size: 20, color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ScorePanel extends StatelessWidget {
  final GameState game;
  const _ScorePanel({required this.game});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PlayerScoreCard(
            name: game.playerNames[0],
            score: game.scores[0],
            active: game.currentPlayer == 0,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Column(
            children: [
              Text(
                'VS',
                style: AppText.number(
                  size: 16,
                  weight: FontWeight.w800,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'حتى ${game.targetScore}',
                style: AppText.ui(size: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        Expanded(
          child: _PlayerScoreCard(
            name: game.playerNames[1],
            score: game.scores[1],
            active: game.currentPlayer == 1,
          ),
        ),
      ],
    );
  }
}

class _PlayerScoreCard extends StatelessWidget {
  final String name;
  final int score;
  final bool active;

  const _PlayerScoreCard({
    required this.name,
    required this.score,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    // AnimatedContainer smoothly lerps the fill/border/glow on turn switch.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        gradient: active ? AppGradients.turn : null,
        color: active ? null : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(
          color: active ? Colors.transparent : AppColors.stroke,
        ),
        boxShadow: active
            ? AppShadows.glow(AppColors.neonPurple, alpha: .35)
            : null,
      ),
      child: Column(
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.ui(
              size: 14,
              weight: FontWeight.w700,
              color: active ? Colors.white : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          PulseOnChange(
            value: score,
            child: Text(
              '$score',
              style: AppText.number(
                size: 46,
                weight: FontWeight.w800,
                color: active ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _HeroFlagCard extends StatelessWidget {
  final Country country;
  const _HeroFlagCard({required this.country});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Heroic flag: gradient border + colored outer glow.
        GradientBorderCard(
          gradient: AppGradients.turn,
          radius: AppRadii.card,
          borderWidth: 2,
          padding: const EdgeInsets.all(10),
          shadows: AppShadows.glow(
            AppColors.electricBlue,
            alpha: .28,
            blur: 40,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.card - 12),
            child: AspectRatio(
              aspectRatio: 3 / 2,
              child: country.flagPng != null
                  ? Image.network(
                      country.flagPng!,
                      fit: BoxFit.cover,
                      width: 300,
                      loadingBuilder: (c, child, progress) => progress == null
                          ? child
                          : Container(
                              color: AppColors.surfaceActive,
                              child: const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                      errorBuilder: (_, _, _) => Container(
                        color: AppColors.surfaceActive,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.flag_outlined,
                          size: 48,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  : Container(color: AppColors.surfaceActive),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          country.nameAr,
          textAlign: TextAlign.center,
          style: AppText.ui(size: 34, weight: FontWeight.w800, height: 1.1),
        ),
        const SizedBox(height: 2),
        Text(
          country.nameEn.toUpperCase(),
          textAlign: TextAlign.center,
          style: AppText.number(
            size: 14,
            weight: FontWeight.w600,
            color: AppColors.textSecondary,
            spacing: 3,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Turn countdown: a depleting neon ring + seconds, the current speaker, and a
// pause/resume toggle. Turns neon-red and pulses in the final 5 seconds.

class _TurnTimerBar extends StatelessWidget {
  final GameState game;
  const _TurnTimerBar({required this.game});

  @override
  Widget build(BuildContext context) {
    final danger = game.isDanger && !game.isPaused;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(
          color: danger
              ? AppColors.ruby.withValues(alpha: .7)
              : Colors.transparent,
          width: 1.4,
        ),
        boxShadow: danger
            ? AppShadows.glow(AppColors.rubyDeep, alpha: .28, blur: 22)
            : null,
      ),
      child: GlassContainer(
        radius: AppRadii.card,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            _CountdownRing(
              secondsLeft: game.secondsLeft,
              danger: game.isDanger,
              paused: game.isPaused,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'الدور على',
                    style: AppText.ui(size: 11, color: AppColors.textSecondary),
                  ),
                  Text(
                    game.currentPlayerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.ui(size: 17, weight: FontWeight.w800),
                  ),
                  if (game.isPaused)
                    Text(
                      '⏸ متوقّف مؤقتاً',
                      style: AppText.ui(size: 11, color: AppColors.amber),
                    ),
                ],
              ),
            ),
            _PauseButton(paused: game.isPaused, onTap: game.togglePause),
          ],
        ),
      ),
    );
  }
}

class _CountdownRing extends StatefulWidget {
  final int secondsLeft;
  final bool danger;
  final bool paused;

  const _CountdownRing({
    required this.secondsLeft,
    required this.danger,
    required this.paused,
  });

  @override
  State<_CountdownRing> createState() => _CountdownRingState();
}

class _CountdownRingState extends State<_CountdownRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );

  bool get _shouldPulse => widget.danger && !widget.paused;

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(_CountdownRing old) {
    super.didUpdateWidget(old);
    _syncPulse();
  }

  void _syncPulse() {
    if (_shouldPulse && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!_shouldPulse && _pulse.isAnimating) {
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
    final Color accent = widget.paused
        ? AppColors.textSecondary
        : (widget.danger ? AppColors.ruby : AppColors.electricBlue);
    final Color numberColor = widget.paused
        ? AppColors.textSecondary
        : (widget.danger ? AppColors.ruby : Colors.white);
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
          },
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

// ---------------------------------------------------------------------------

class _MatchOverView extends StatelessWidget {
  final GameState game;
  const _MatchOverView({required this.game});

  @override
  Widget build(BuildContext context) {
    final winner = game.matchWinner!;
    return Scaffold(
      body: Stack(
        children: [
          const AmbientBackground(),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🏆', style: TextStyle(fontSize: 84)),
                    const SizedBox(height: 20),
                    ShaderMask(
                      shaderCallback: (r) => AppGradients.turn.createShader(r),
                      child: Text(
                        game.playerNames[winner],
                        textAlign: TextAlign.center,
                        style: AppText.ui(
                          size: 32,
                          weight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'الفائز باللعبة',
                      style: AppText.ui(
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    GlassContainer(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 16,
                      ),
                      child: Text(
                        '${game.scores[0]}  -  ${game.scores[1]}',
                        style: AppText.number(
                          size: 40,
                          weight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 34),
                    GameButton(
                      label: 'لعبة جديدة',
                      icon: Icons.replay_rounded,
                      gradient: AppGradients.turn,
                      glowColor: AppColors.neonPurple,
                      onPressed: () {
                        game.backToSetup();
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
