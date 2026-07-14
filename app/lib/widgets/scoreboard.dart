import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/game_state.dart';
import '../theme/app_theme.dart';
import 'pulse_on_change.dart';

/// Scoreboard for 2–4 players: a target chip above a two-column [Wrap] of
/// player cards, so 2 players sit in one row, 3 flow as 2 + 1, and 4 form a
/// clean 2×2 grid — no horizontal overflow at any count.
///
/// Elimination rounds: players knocked out of the current round render
/// dimmed with a struck-through name and an ❌ badge, and snap back when the
/// next round resets everyone to active.
///
/// Subscribes to [GameState] with granular `context.select` calls, so it
/// rebuilds only when a score, the active player, an elimination flag, a
/// name, the target, or the player count changes — never on the 1-second
/// timer ticks. Each card subscribes to its own player's scalars, so one
/// player's change rebuilds only that card.
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

/// Tiny pass-ticket indicator: a lit emerald dot while the player's one
/// "تخطي" for this round is unspent, dimming to a hollow grey dot once used.
class _PassDot extends StatelessWidget {
  final bool spent;

  const _PassDot({required this.spent});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: spent ? Colors.transparent : AppColors.emerald,
        border: spent
            ? Border.all(color: AppColors.textSecondary.withValues(alpha: .6))
            : null,
        boxShadow: spent
            ? null
            : [
                BoxShadow(
                  color: AppColors.emerald.withValues(alpha: .55),
                  blurRadius: 6,
                ),
              ],
      ),
    );
  }
}

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

    final nameStyle = AppText.ui(
      size: compact ? 13 : 14,
      weight: FontWeight.w700,
      color: active ? Colors.white : AppColors.textSecondary,
    ).copyWith(
      decoration: knockedOut ? TextDecoration.lineThrough : null,
      decorationColor: AppColors.ruby,
      decorationThickness: 2,
    );
    final scoreText = PulseOnChange(
      value: score,
      child: Text(
        '$score',
        style: AppText.number(
          size: compact ? 26 : 46,
          weight: FontWeight.w800,
          color: active ? Colors.white : AppColors.textPrimary,
        ),
      ),
    );
    final nameLine = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (knockedOut) ...[
          const Text('❌', style: TextStyle(fontSize: 10)),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: nameStyle,
          ),
        ),
        const SizedBox(width: 5),
        _PassDot(spent: passSpent),
      ],
    );

    // Dim the whole card while eliminated; AnimatedOpacity snaps it back
    // when the next round resets everyone to active.
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 320),
      opacity: knockedOut ? 0.38 : 1.0,
      // AnimatedContainer smoothly lerps the fill/border/glow on turn switch.
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          vertical: compact ? 8 : 14,
          horizontal: 12,
        ),
        decoration: BoxDecoration(
          gradient: active ? AppGradients.turn : null,
          color: active ? null : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(
            color: knockedOut
                ? AppColors.ruby.withValues(alpha: .45)
                : active
                    ? Colors.transparent
                    : AppColors.stroke,
          ),
          boxShadow: active
              ? AppShadows.glow(AppColors.neonPurple, alpha: .35)
              : null,
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
