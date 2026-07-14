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

  const JudgeControls({
    super.key,
    required this.onRuleFalse,
    required this.onAcceptFact,
    required this.onPass,
    required this.onAskSmartJudge,
  });

  @override
  Widget build(BuildContext context) {
    final canPass = context.select((GameState g) => g.canPass);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: GameButton(
                label: 'غلط!',
                icon: Icons.close_rounded,
                height: 60,
                gradient: AppGradients.falsehood,
                glowColor: AppColors.rubyDeep,
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
                onPressed: onAcceptFact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            // One pass per player per round — disabled (dimmed) once the
            // current speaker has spent theirs; GameButton renders a null
            // onPressed as inert + faded.
            Expanded(
              child: GameButton(
                label: 'تخطي',
                icon: Icons.fast_forward_rounded,
                height: 56,
                onPressed: canPass ? onPass : null,
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
