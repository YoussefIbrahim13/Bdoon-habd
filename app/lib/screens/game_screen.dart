import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_screen.dart';
import '../state/game_state.dart';
import '../theme/app_theme.dart';
import '../widgets/countdown_ring.dart';
import '../widgets/country_card.dart';
import '../widgets/fx.dart';
import '../widgets/game_button.dart';
import '../widgets/glass_container.dart';
import '../widgets/judge_controls.dart';
import '../widgets/nova_components.dart';
import '../widgets/scoreboard.dart';
import '../widgets/smart_judge_sheet.dart';
import '../widgets/tutorial_overlay.dart';

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
  static const _tutorialSeenPref = 'seen_gameplay_tutorial';

  late final GameState _game;
  int _seenEliminations = 0;
  int _seenRounds = 0;
  GamePhase? _lastPhase;

  // One-shot FX triggers: confetti on a round win, shake+flash on a knockout.
  int _confettiTrigger = 0;
  int _shakeTrigger = 0;
  int _flashTrigger = 0;

  // --- First-time coach-marks tour ---
  bool _tutorialActive = false;
  bool _tutorialPausedGame = false;
  final _scoreboardKey = GlobalKey();
  final _heroKey = GlobalKey();
  final _timerKey = GlobalKey();
  final _passKey = GlobalKey();
  final _verdictKey = GlobalKey();
  final _shuffleKey = GlobalKey();
  final _endGameKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _game = context.read<GameState>();
    _seenEliminations = _game.eliminationsCompleted;
    _seenRounds = _game.roundsCompleted;
    // Fire one-shot feedback for every knockout — manual (غلط!) and timeout
    // alike — and for round wins, via GameState's monotonic counters.
    _game.addListener(_onGameChanged);
    // Kick off the first-time tour once the first frame has rendered (the
    // spotlight needs laid-out targets to measure).
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStartTutorial());
  }

  Future<void> _maybeStartTutorial() async {
    bool seen;
    try {
      final prefs = await SharedPreferences.getInstance();
      seen = prefs.getBool(_tutorialSeenPref) ?? false;
    } catch (_) {
      return; // prefs unavailable — never block the game on the tour
    }
    if (seen || !mounted || _game.phase != GamePhase.playing) return;
    // Freeze the speaker's clock for the whole tour.
    _tutorialPausedGame = !_game.isPaused;
    if (_tutorialPausedGame) _game.pause();
    setState(() => _tutorialActive = true);
  }

  void _finishTutorial() {
    setState(() => _tutorialActive = false);
    if (_tutorialPausedGame) _game.resume();
    _persistTutorialSeen();
  }

  Future<void> _persistTutorialSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_tutorialSeenPref, true);
    } catch (_) {
      // Non-fatal: worst case the tour shows again next launch.
    }
  }

  List<TutorialStep> _tutorialSteps() => [
        TutorialStep(
          targets: [_scoreboardKey],
          text:
              'هنا هتشوف أسامي اللعيبة، سكور كل لاعب، ومين اللي عليه الدور — اللي كارت بتاعه بينبض!',
        ),
        TutorialStep(
          targets: [_heroKey, _timerKey],
          text:
              'هنا بتظهر دولة الجولة والعلم بتاعها، والتايمر بيلف.. خلي بالك أول ما يقل عن ١٠ ثواني هينبض بالأحمر!',
        ),
        TutorialStep(
          targets: [_passKey],
          text:
              'كل لاعب عنده تذكرة تخطي واحدة بس في الجولة، تقدر تستخدمها كطوق نجاة تعدّي بيها دورك من غير ما تتستبعد.',
        ),
        TutorialStep(
          targets: [_verdictKey],
          text:
              'بصفتك الحكم: لو اللاعب جاوب صح اضغط "صح" عشان يعدي الدور، ولو هبد أو معرفش اضغط "غلط" عشان يتستبعد برة الجولة بروقان!',
        ),
        TutorialStep(
          targets: [_shuffleKey],
          text:
              'لو الدولة اللي ظهرت صعبة على الكل أو حابب تغيرها، اضغط هنا لتغيير الأعلام فوراً.',
        ),
        TutorialStep(
          targets: [_endGameKey],
          text:
              'لو حابب تقفل الجيم الحالي في أي وقت وترجع للرئيسية عشان تبدأ مباراة جديدة، اضغط هنا.',
        ),
      ];

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
    // Final score reveal: one heavy thump + celebration burst.
    if (_game.phase != _lastPhase) {
      if (_game.phase == GamePhase.matchOver) {
        HapticFeedback.heavyImpact();
      }
      _lastPhase = _game.phase;
    }
  }

  void _announceElimination() {
    if (!mounted || _game.phase != GamePhase.playing) return;
    final out = _game.lastEliminated;
    if (out == null) return;
    // هبدة! — jolt the board.
    setState(() {
      _shakeTrigger++;
      _flashTrigger++;
    });
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
    // صح! — emerald celebration.
    setState(() => _confettiTrigger++);
    HapticFeedback.mediumImpact();
    _showSnack(
      '🏆 ${_game.playerNames[winner]} آخر الصامدين — نقطة! جولة جديدة',
    );
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

  Future<void> _confirmEndGame() async {
    final resumeAfter = !_game.isPaused && _game.phase == GamePhase.playing;
    if (resumeAfter) _game.pause();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .74),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 26),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.amber.withValues(alpha: .55),
                  AppColors.stroke,
                  AppColors.amberDeep.withValues(alpha: .45),
                ],
              ),
              boxShadow: [
                ...AppShadows.soft,
                ...AppShadows.glow(AppColors.amber, alpha: .14, blur: 26),
              ],
            ),
            padding: const EdgeInsets.all(1.2),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
              decoration: BoxDecoration(
                color: const Color(0xEE11131B),
                borderRadius: BorderRadius.circular(27),
                border: Border.all(color: AppColors.stroke),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'إنهاء المباراة؟',
                    textAlign: TextAlign.center,
                    style: AppText.number(size: 24, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'هل أنت متأكد من رغبتك في الخروج برة الجيم الحالي والعودة للشاشة الرئيسية؟',
                    textAlign: TextAlign.center,
                    style: AppText.ui(
                      size: 14.2,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: AppColors.glassFill,
                              side: const BorderSide(color: AppColors.stroke),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              'إلغاء',
                              style: AppText.ui(
                                size: 14.5,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: AppGradients.falsehood,
                              boxShadow: AppShadows.glow(
                                AppColors.rubyDeep,
                                alpha: .28,
                                blur: 18,
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => Navigator.pop(ctx, true),
                                child: Center(
                                  child: Text(
                                    'تأكيد وإنهاء',
                                    style: AppText.ui(
                                      size: 14.5,
                                      weight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (confirmed == true) {
      _game.resetGame();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        NovaPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    } else if (resumeAfter) {
      _game.resume();
    }
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
            // Shake the whole board on a knockout.
            child: ShakeWrapper(
              trigger: _shakeTrigger,
              child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
              child: Column(
                children: [
                  _TopBar(
                    round: round,
                    onSkip: _game.skipCountry,
                    onEndGame: _confirmEndGame,
                    shuffleKey: _shuffleKey,
                    endGameKey: _endGameKey,
                  ),
                  const SizedBox(height: 14),
                  KeyedSubtree(
                    key: _scoreboardKey,
                    child: const Scoreboard(),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        // New round / skip: the incoming country scales+fades
                        // in (easeOutCubic) instead of snapping into place.
                        child: KeyedSubtree(
                          key: _heroKey,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 420),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, anim) => FadeTransition(
                              opacity: anim,
                              child: ScaleTransition(
                                scale:
                                    Tween(begin: .92, end: 1.0).animate(anim),
                                child: child,
                              ),
                            ),
                            child: CountryCard(
                              key: ValueKey(country.code),
                              country: country,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  KeyedSubtree(
                    key: _timerKey,
                    child: const TurnTimerBar(),
                  ),
                  const SizedBox(height: 16),
                  JudgeControls(
                    onRuleFalse: _confirmRuleFalse,
                    onAcceptFact: _game.acceptFact,
                    onPass: _game.passTurn,
                    onAskSmartJudge: _openSmartJudge,
                    verdictRowKey: _verdictKey,
                    passKey: _passKey,
                  ),
                ],
              ),
              ),
            ),
          ),
          // One-shot FX layers: idle they render nothing at all.
          Positioned.fill(child: FlashOverlay(trigger: _flashTrigger)),
          Positioned.fill(child: ConfettiLayer(trigger: _confettiTrigger)),
          // First-time guided tour, floating over the frozen board.
          if (_tutorialActive)
            Positioned.fill(
              child: TutorialOverlay(
                steps: _tutorialSteps(),
                onDone: _finishTutorial,
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
  final VoidCallback onEndGame;

  /// Coach-marks anchors for the shuffle and end-game chips.
  final Key? shuffleKey;
  final Key? endGameKey;

  const _TopBar({
    required this.round,
    required this.onSkip,
    required this.onEndGame,
    this.shuffleKey,
    this.endGameKey,
  });

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
          key: shuffleKey,
          message: 'تغيير الأعلام',
          child: Material(
            color: AppColors.glassTint,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: onSkip,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                constraints: const BoxConstraints(minHeight: 42, minWidth: 42),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.stroke),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.shuffle_rounded,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'تغيير الأعلام',
                      style: AppText.ui(
                        size: 12.8,
                        weight: FontWeight.w700,
                        color: AppColors.textSecondary.withValues(alpha: .9),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Tooltip(
          key: endGameKey,
          message: 'إنهاء المباراة',
          child: Material(
            color: AppColors.glassTint,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: onEndGame,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.amber.withValues(alpha: .24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.rubyDeep.withValues(alpha: .15),
                      blurRadius: 14,
                    ),
                    BoxShadow(
                      color: AppColors.amber.withValues(alpha: .08),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.power_settings_new_rounded,
                  size: 20,
                  color: AppColors.ruby.withValues(alpha: .82),
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
                    GradientText(
                      game.playerNames[winner],
                      gradient: AppGradients.wordmark,
                      textAlign: TextAlign.center,
                      style: AppText.ui(size: 32, weight: FontWeight.w800),
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
