import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/game_state.dart';
import '../theme/app_theme.dart';
import 'game_button.dart';

/// The Judge's action cluster: "غلط!" (rule false — speaker is eliminated
/// from the round), "صح — التالي" (accept — same country, next active
/// player), "تخطي" (the speaker spends their one pass for this round), and
/// "اسأل الحكم الذكي" (open the Smart Judge sheet).
///
/// Presentation-first: the screen owns the side effects (confirm dialog,
/// modal sheet) and passes them in as callbacks. The only state this widget
/// subscribes to is [GameState.canPass] — a single boolean select, so it
/// rebuilds only when the current speaker's pass availability flips, never
/// on timer ticks.
class JudgeControls extends StatelessWidget {
  final VoidCallback onRuleFalse;
  final VoidCallback onAcceptFact;
  final VoidCallback onPass;
  final VoidCallback onAskSmartJudge;

  /// Optional anchors for the first-time coach-marks tour: the verdict row
  /// (صح/غلط) and the pass button, so the tutorial can spotlight them.
  final Key? verdictRowKey;
  final Key? passKey;

  const JudgeControls({
    super.key,
    required this.onRuleFalse,
    required this.onAcceptFact,
    required this.onPass,
    required this.onAskSmartJudge,
    this.verdictRowKey,
    this.passKey,
  });

  Widget _keyed(Key? k, Widget child) =>
      k == null ? child : KeyedSubtree(key: k, child: child);

  @override
  Widget build(BuildContext context) {
    final canPass = context.select((GameState g) => g.canPass);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _keyed(
          verdictRowKey,
          Row(
            children: [
              Expanded(
                child: GameButton(
                  label: 'غلط!',
                  icon: Icons.close_rounded,
                  height: 60,
                  gradient: AppGradients.falsehood,
                  glowColor: AppColors.rubyDeep,
                  mediumHaptic: true, // a verdict deserves weight
                  onPressed: onRuleFalse,
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
                  mediumHaptic: true,
                  onPressed: onAcceptFact,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            // One pass per player per round. AnimatedSwitcher cross-fades
            // between the live tactile button and the sleek obsidian
            // "locked" plate once the pass is spent.
            Expanded(
              child: _keyed(
                passKey,
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  child: canPass
                      ? GameButton(
                          key: const ValueKey('pass-live'),
                          label: 'تخطي',
                          icon: Icons.fast_forward_rounded,
                          height: 56,
                          borderGradient: AppGradients.uncertain,
                          onPressed: onPass,
                        )
                      : const _LockedPassPlate(key: ValueKey('pass-locked')),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: GameButton(
                label: 'اسأل الحكم الذكي',
                icon: Icons.auto_awesome,
                height: 56,
                borderGradient: AppGradients.turn,
                onPressed: onAskSmartJudge,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The spent-pass state: not a greyed-out button but a quiet obsidian plate
/// with a lock — clearly inert, still premium.
class _LockedPassPlate extends StatelessWidget {
  const _LockedPassPlate({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(AppRadii.button),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lock_rounded,
            size: 15,
            color: AppColors.textSecondary.withValues(alpha: .7),
          ),
          const SizedBox(width: 8),
          Text(
            'تخطي',
            style: AppText.ui(
              size: 15,
              weight: FontWeight.w700,
              color: AppColors.textSecondary.withValues(alpha: .55),
            ).copyWith(decoration: TextDecoration.lineThrough),
          ),
        ],
      ),
    );
  }
}
