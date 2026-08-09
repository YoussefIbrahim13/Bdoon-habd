import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/game_state.dart';
import '../theme/app_theme.dart';
import 'fx.dart';
import 'pulse_on_change.dart';

/// Scoreboard for 2–4 players: a target chip above a two-column [Wrap] of
/// player cards, so 2 players sit in one row, 3 flow as 2 + 1, and 4 form a
/// clean 2×2 grid — no horizontal overflow at any count.
///
/// Premium identity system:
/// - Each seat carries its neon color (cyan/purple/green/pink from
///   [AppColors.playerAccents]) — the ACTIVE player's card breathes with a
///   pulsing border glow in their own color, while idle cards stay dimmed.
/// - Eliminated players get a ruby-tinted frosted-glass "locked out" overlay
///   that fades and blurs in smoothly instead of snapping.
/// - Each card shows a tiny neon pass ticket that dims once spent.
///
/// Performance: subscribes via granular `context.select` on scalar values
/// only, so timer ticks rebuild nothing here, and a score / turn /
/// elimination / pass change rebuilds only the affected card(s).
class Scoreboard extends StatelessWidget {
  const Scoreboard({super.key});

  static const double _spacing = 10;

  @override
  Widget build(BuildContext context) {
    final totalPlayers = context.select((GameState g) => g.totalPlayers);
    final targetScore = context.select((GameState g) => g.targetScore);
    // Denser cards when a second row exists, to keep the flag area roomy.
    final compact = totalPlayers > 2;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.glassTint,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.stroke),
          ),
          child: Text(
            'آخر صامد ياخد النقطة — الأول لـ $targetScore يفوز',
            style: AppText.ui(size: 11, color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = (constraints.maxWidth - _spacing) / 2;
            return Wrap(
              spacing: _spacing,
              runSpacing: _spacing,
              alignment: WrapAlignment.center,
              children: [
                for (var i = 0; i < totalPlayers; i++)
                  SizedBox(
                    width: cardWidth,
                    child: _PlayerScoreCard(playerIndex: i, compact: compact),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Subscribes to one player's scalars and renders their card via the
/// animated [_CardShell].
class _PlayerScoreCard extends StatelessWidget {
  final int playerIndex;
  final bool compact;

  const _PlayerScoreCard({required this.playerIndex, required this.compact});

  @override
  Widget build(BuildContext context) {
    // GameState mutates its lists in place (scores[i]++, eliminated[i] =
    // true), so select the scalar elements (value equality) — selecting a
    // list itself would compare by identity and never fire.
    final name = context.select((GameState g) => g.playerNames[playerIndex]);
    final score = context.select((GameState g) => g.scores[playerIndex]);
    final active =
        context.select((GameState g) => g.currentPlayer == playerIndex);
    final knockedOut =
        context.select((GameState g) => g.eliminated[playerIndex]);
    final passSpent =
        context.select((GameState g) => g.hasPassed[playerIndex]);

    final accent = AppColors.playerAccents[playerIndex];
    final onCard = active ? Colors.white : AppColors.textSecondary;

    final nameLine = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.ui(
              size: compact ? 13 : 14,
              weight: FontWeight.w700,
              color: onCard,
            ).copyWith(
              decoration: knockedOut ? TextDecoration.lineThrough : null,
              decorationColor: AppColors.ruby,
              decorationThickness: 2,
            ),
          ),
        ),
        const SizedBox(width: 6),
        _PassTicket(spent: passSpent, accent: accent),
      ],
    );
    // Pulse on change + roll the digits instead of jumping.
    final scoreText = PulseOnChange(
      value: score,
      child: AnimatedCount(
        value: score,
        style: AppText.number(
          size: compact ? 26 : 46,
          weight: FontWeight.w800,
          color: active ? Colors.white : AppColors.textPrimary,
        ),
      ),
    );

    return _CardShell(
      accent: accent,
      active: active,
      knockedOut: knockedOut,
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: compact ? 8 : 14,
          horizontal: 12,
        ),
        child: compact
            // Compact (3–4 players): name and score share one line so two
            // rows of cards stay shorter than the old single row.
            ? Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: nameLine,
                    ),
                  ),
                  const SizedBox(width: 8),
                  scoreText,
                ],
              )
            : Column(
                children: [
                  nameLine,
                  const SizedBox(height: 6),
                  scoreText,
                ],
              ),
      ),
    );
  }
}

/// The card chrome: identity-colored pulsing spotlight while active, calm
/// dim glass while idle, and a frosted ruby "locked out" overlay that blurs
/// in when the player is eliminated.
class _CardShell extends StatefulWidget {
  final Color accent;
  final bool active;
  final bool knockedOut;
  final Widget child;

  const _CardShell({
    required this.accent,
    required this.active,
    required this.knockedOut,
    required this.child,
  });

  @override
  State<_CardShell> createState() => _CardShellState();
}

class _CardShellState extends State<_CardShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  bool get _shouldPulse => widget.active && !widget.knockedOut;

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(_CardShell old) {
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
    final accent = widget.accent;
    final radius = BorderRadius.circular(AppRadii.card);

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_pulse.value);
        final decoration = widget.active
            ? BoxDecoration(
                // Identity-tinted glass, not a flat gradient fill, so the
                // accent reads as light INSIDE the card.
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(AppColors.surfaceActive, accent, .16)!,
                    AppColors.surface,
                  ],
                ),
                borderRadius: radius,
                border: Border.all(
                  color: accent.withValues(alpha: .45 + .45 * t),
                  width: 1.6,
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: .18 + .17 * t),
                    blurRadius: 16 + 10 * t,
                    spreadRadius: 1,
                  ),
                ],
              )
            : BoxDecoration(
                color: AppColors.surface,
                borderRadius: radius,
                border: Border.all(
                  color: widget.knockedOut
                      ? AppColors.ruby.withValues(alpha: .40)
                      : AppColors.stroke,
                ),
              );
        return Container(decoration: decoration, child: child);
      },
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            // Idle cards sit slightly dimmed so the spotlight owns the eye.
            AnimatedOpacity(
              duration: const Duration(milliseconds: 320),
              opacity: widget.active ? 1 : .82,
              child: widget.child,
            ),
            // Elimination lock-out: frosted ruby glass blurring in smoothly.
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: widget.knockedOut ? 1 : 0),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                builder: (context, t, _) {
                  if (t == 0) return const SizedBox.shrink();
                  return IgnorePointer(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(
                        sigmaX: 3.5 * t,
                        sigmaY: 3.5 * t,
                      ),
                      child: Container(
                        alignment: Alignment.center,
                        color: AppColors.rubyDeep.withValues(alpha: .12 * t),
                        child: Opacity(
                          opacity: t,
                          child: Icon(
                            Icons.lock_outline_rounded,
                            size: 16,
                            color: AppColors.ruby.withValues(alpha: .85),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Futuristic pass ticket: a tiny neon stub glowing in the player's accent
/// while their round pass is available, powering down to a hollow outline
/// once spent.
class _PassTicket extends StatelessWidget {
  final bool spent;
  final Color accent;

  const _PassTicket({required this.spent, required this.accent});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 1.5),
      decoration: BoxDecoration(
        color: spent ? Colors.transparent : accent.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: spent
              ? AppColors.textSecondary.withValues(alpha: .45)
              : accent.withValues(alpha: .8),
          width: 1,
        ),
        boxShadow: spent
            ? null
            : [
                BoxShadow(
                  color: accent.withValues(alpha: .45),
                  blurRadius: 7,
                ),
              ],
      ),
      child: Icon(
        Icons.confirmation_number_outlined,
        size: 9,
        color: spent
            ? AppColors.textSecondary.withValues(alpha: .55)
            : Color.lerp(accent, Colors.white, .35),
      ),
    );
  }
}
