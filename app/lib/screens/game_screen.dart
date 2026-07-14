import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/game_state.dart';
import '../theme/app_theme.dart';
import '../widgets/countdown_ring.dart';
import '../widgets/country_card.dart';
import '../widgets/game_button.dart';
import '../widgets/glass_container.dart';
import '../widgets/judge_controls.dart';
import '../widgets/scoreboard.dart';
import '../widgets/smart_judge_sheet.dart';

/// Layout controller for a running match.
///
/// Owns no game UI of its own: it arranges [Scoreboard], [CountryCard],
/// [TurnTimerBar], and [JudgeControls], and coordinates everything that
/// leaves the layer — the round-end snackbar, the rule-false confirm dialog,
/// the Smart Judge modal sheet, and the match-over takeover view.
///
/// Rebuild scope is deliberately narrow: the build subscribes only to
/// `phase`, `currentCountry`, and `roundNumber` via `context.select`; the
/// per-second timer ticks rebuild the extracted widgets, not this screen.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final GameState _game;
  int _seenEliminations = 0;
  int _seenRounds = 0;

  @override
  void initState() {
    super.initState();
    _game = context.read<GameState>();
    _seenEliminations = _game.eliminationsCompleted;
    _seenRounds = _game.roundsCompleted;
    // Fire one-shot feedback for every knockout — manual (غلط!) and timeout
    // alike — and for round wins, via GameState's monotonic counters.
    _game.addListener(_onGameChanged);
  }

  @override
  void dispose() {
    _game.removeListener(_onGameChanged);
    super.dispose();
  }

  void _onGameChanged() {
    final roundEnded = _game.roundsCompleted != _seenRounds;
    final someoneOut = _game.eliminationsCompleted != _seenEliminations;
    _seenRounds = _game.roundsCompleted;
    _seenEliminations = _game.eliminationsCompleted;
    // A round-ending knockout fires both counters at once — the round-win
    // message wins (it implies the elimination).
    if (roundEnded) {
      _announceRoundWon();
    } else if (someoneOut) {
      _announceElimination();
    }
  }

  void _announceElimination() {
    if (!mounted || _game.phase != GamePhase.playing) return;
    final out = _game.lastEliminated;
    if (out == null) return;
    final timedOut = _game.lastRoundEndReason == RoundEndReason.timeout;
    final msg = timedOut
        ? '⏰ انتهى وقت ${_game.playerNames[out]} — خرج من الجولة!'
        : '❌ هبدة! ${_game.playerNames[out]} خرج من الجولة';
    _showSnack(msg);
  }

  void _announceRoundWon() {
    // Match-over shows its own screen; only snackbar for continuing play.
    if (!mounted || _game.phase != GamePhase.playing) return;
    final winner = _game.lastRoundWinner;
    if (winner == null) return;
    _showSnack('🏆 ${_game.playerNames[winner]} آخر الصامدين — نقطة! جولة جديدة');
  }

  void _showSnack(String msg) {
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

  Future<void> _confirmRuleFalse() async {
    final speaker = _game.currentPlayerName;
    // Freeze the clock while the judge deliberates in the dialog.
    final resumeAfter = !_game.isPaused;
    if (resumeAfter) _game.pause();

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
                'معلومة "$speaker" غلط ويخرج من الجولة؟',
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
      _game.ruleFalse();
    } else if (resumeAfter) {
      // Cancelled — restore the clock we paused.
      _game.resume();
    }
  }

  void _openSmartJudge() {
    final country = _game.currentCountry;
    if (country == null) return;
    // Consulting the AI shouldn't burn the speaker's clock — auto-pause while
    // the sheet is open, and resume on close only if we were the one to pause.
    final resumeAfter = !_game.isPaused;
    if (resumeAfter) _game.pause();

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
      if (resumeAfter) _game.resume();
    });
  }

  @override
  Widget build(BuildContext context) {
    final phase = context.select((GameState g) => g.phase);
    if (phase == GamePhase.matchOver) {
      return const _MatchOverView();
    }

    final country = context.select((GameState g) => g.currentCountry);
    if (country == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final round = context.select((GameState g) => g.roundNumber);

    return Scaffold(
      body: Stack(
        children: [
          const AmbientBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
              child: Column(
                children: [
                  _TopBar(round: round, onSkip: _game.skipCountry),
                  const SizedBox(height: 14),
                  const Scoreboard(),
                  const SizedBox(height: 18),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        child: CountryCard(country: country),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const TurnTimerBar(),
                  const SizedBox(height: 16),
                  JudgeControls(
                    onRuleFalse: _confirmRuleFalse,
                    onAcceptFact: _game.acceptFact,
                    onPass: _game.passTurn,
                    onAskSmartJudge: _openSmartJudge,
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
        Tooltip(
          message: 'تغيير الدولة',
          child: Material(
            color: AppColors.glassTint,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: onSkip,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.stroke),
                ),
                child: const Icon(
                  Icons.shuffle_rounded,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Full-screen takeover shown when the match is decided. Reads GameState
// directly (values are frozen once the phase is matchOver).

class _MatchOverView extends StatelessWidget {
  const _MatchOverView();

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameState>();
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
                        game.scores.join('  -  '),
                        style: AppText.number(
                          size: game.totalPlayers > 2 ? 30 : 40,
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
