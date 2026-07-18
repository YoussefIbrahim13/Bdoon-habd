import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/game_events.dart';
import '../services/auth_service.dart';
import '../state/game_room_state.dart';
import '../theme/app_theme.dart';
import '../widgets/country_card.dart';
import '../widgets/game_button.dart';
import '../widgets/glass_container.dart';

/// Live multiplayer room. Owns a [GameRoomState] scoped to this screen —
/// the provider disposes it on exit, which closes the socket and cancels
/// the event subscription (no leaked channels, ever).
///
/// The body is one AnimatedSwitcher over the server-driven phase:
/// lobby → awaiting_fact → evaluating → awaiting_votes → … → game_over,
/// plus local connecting/disconnected states.
class GameRoomScreen extends StatelessWidget {
  final String roomCode;

  const GameRoomScreen({super.key, required this.roomCode});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    return ChangeNotifierProvider<GameRoomState>(
      create: (_) => GameRoomState(
        myId: auth.user?.id ?? '',
        token: auth.token ?? '',
      )..join(roomCode),
      child: const _GameRoomView(),
    );
  }
}

class _GameRoomView extends StatefulWidget {
  const _GameRoomView();

  @override
  State<_GameRoomView> createState() => _GameRoomViewState();
}

class _GameRoomViewState extends State<_GameRoomView> {
  late final GameRoomState _room;
  int _seenRounds = 0;
  int _seenErrors = 0;

  @override
  void initState() {
    super.initState();
    _room = context.read<GameRoomState>();
    _seenRounds = _room.roundsCompleted;
    _seenErrors = _room.errorsSeen;
    _room.addListener(_onRoomChanged);
  }

  @override
  void dispose() {
    _room.removeListener(_onRoomChanged);
    super.dispose();
  }

  /// One-shot feedback (round results, server rule errors) via snackbars,
  /// keyed off the state's monotonic counters.
  void _onRoomChanged() {
    if (_room.errorsSeen != _seenErrors) {
      _seenErrors = _room.errorsSeen;
      _snack(_room.lastError, AppColors.amber);
    }
    if (_room.roundsCompleted != _seenRounds) {
      _seenRounds = _room.roundsCompleted;
      final r = _room.lastRoundResult;
      if (r != null) {
        final name = _room.playerById(r.playerId)?.name ?? '';
        _snack(
          r.awarded
              ? '🏆 نقطة لـ $name! (صح ${r.trueVotes} × هبد ${r.falseVotes})'
              : '❌ هبدة من $name — من غير نقطة (صح ${r.trueVotes} × هبد ${r.falseVotes})',
          r.awarded ? AppColors.emerald : AppColors.ruby,
        );
      }
    }
  }

  void _snack(String msg, Color accent) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xF5141722),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: accent.withValues(alpha: .55)),
            ),
            content: Text(msg,
                style: AppText.ui(size: 13.5, weight: FontWeight.w700)),
          ),
        );
    });
  }

  @override
  Widget build(BuildContext context) {
    final phase = context.select((GameRoomState r) => r.phase);
    final code = context.select((GameRoomState r) => r.roomCode);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('أوضة $code',
            style: AppText.number(size: 17, weight: FontWeight.w700)),
      ),
      body: Stack(
        children: [
          const AmbientBackground(),
          SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutCubic,
              child: switch (phase) {
                OnlinePhase.connecting =>
                  const _CenteredNote(key: ValueKey('connecting'),
                      icon: Icons.wifi_tethering_rounded,
                      text: 'جارٍ الاتصال بالأوضة...'),
                OnlinePhase.lobby => const _LobbyView(key: ValueKey('lobby')),
                OnlinePhase.awaitingFact =>
                  const _TurnView(key: ValueKey('turn')),
                OnlinePhase.evaluating =>
                  const _EvaluatingView(key: ValueKey('evaluating')),
                OnlinePhase.awaitingVotes =>
                  const _VotingView(key: ValueKey('voting')),
                OnlinePhase.gameOver =>
                  const _GameOverView(key: ValueKey('over')),
                OnlinePhase.disconnected =>
                  const _DisconnectedView(key: ValueKey('gone')),
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

class _CenteredNote extends StatelessWidget {
  final IconData icon;
  final String text;

  const _CenteredNote({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: AppColors.electricBlue),
          const SizedBox(height: 14),
          const CircularProgressIndicator(strokeWidth: 2.4),
          const SizedBox(height: 14),
          Text(text, style: AppText.ui(size: 14.5, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Horizontal strip of player chips with scores; the current speaker glows.
class _PlayersStrip extends StatelessWidget {
  const _PlayersStrip();

  @override
  Widget build(BuildContext context) {
    final players = context.select((GameRoomState r) => r.players);
    final currentId = context.select((GameRoomState r) => r.currentPlayerId);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final p in players)
            Container(
              margin: const EdgeInsetsDirectional.only(end: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: p.id == currentId
                    ? AppColors.electricBlue.withValues(alpha: .16)
                    : AppColors.glassFill,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: p.id == currentId
                      ? AppColors.electricBlue.withValues(alpha: .7)
                      : AppColors.stroke,
                ),
              ),
              child: Row(
                children: [
                  _Avatar(player: p, size: 22),
                  const SizedBox(width: 7),
                  Text(
                    p.name,
                    style: AppText.ui(
                      size: 12.5,
                      weight: FontWeight.w700,
                      color: p.connected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary.withValues(alpha: .5),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text('${p.score}',
                      style: AppText.number(
                          size: 15,
                          weight: FontWeight.w800,
                          color: AppColors.electricBlue)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final OnlinePlayer player;
  final double size;

  const _Avatar({required this.player, required this.size});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: AppColors.surfaceActive,
      backgroundImage:
          player.picture != null ? NetworkImage(player.picture!) : null,
      child: player.picture == null
          ? Text(
              player.name.isEmpty ? '؟' : player.name.characters.first,
              style: AppText.ui(size: size * .45, weight: FontWeight.w800),
            )
          : null,
    );
  }
}

// ---------------------------------------------------------------------------
// LOBBY
// ---------------------------------------------------------------------------

class _LobbyView extends StatelessWidget {
  const _LobbyView({super.key});

  @override
  Widget build(BuildContext context) {
    final room = context.watch<GameRoomState>();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The shareable room code, hero-sized.
              GradientBorderCard(
                gradient: AppGradients.turn,
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Column(
                  children: [
                    Text('كود الأوضة',
                        style: AppText.ui(
                            size: 12.5, color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    Text(room.roomCode,
                        style: AppText.number(
                            size: 44, weight: FontWeight.w800, spacing: 10)),
                    const SizedBox(height: 4),
                    Text('ابعته لأصحابك وخليهم يدخلوا',
                        style: AppText.ui(
                            size: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              GlassContainer(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('اللاعيبة (${room.players.length})',
                        style:
                            AppText.ui(size: 14, weight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    for (final p in room.players)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            _Avatar(player: p, size: 34),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(p.name,
                                  style: AppText.ui(
                                      size: 14.5, weight: FontWeight.w700)),
                            ),
                            if (p.id == room.hostId)
                              Text('👑',
                                  style: const TextStyle(fontSize: 16)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              if (room.iAmHost)
                GameButton(
                  label: room.players.length < 2
                      ? 'مستنيين لاعب كمان...'
                      : 'ابدأ اللعب',
                  icon: Icons.sports_esports_rounded,
                  height: 58,
                  gradient: AppGradients.turn,
                  glowColor: AppColors.neonPurple,
                  onPressed:
                      room.players.length < 2 ? null : room.startGame,
                )
              else
                Text(
                  'مستنيين صاحب الأوضة يبدأ اللعب...',
                  textAlign: TextAlign.center,
                  style:
                      AppText.ui(size: 13.5, color: AppColors.textSecondary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AWAITING_FACT
// ---------------------------------------------------------------------------

class _TurnView extends StatefulWidget {
  const _TurnView({super.key});

  @override
  State<_TurnView> createState() => _TurnViewState();
}

class _TurnViewState extends State<_TurnView> {
  final _factController = TextEditingController();

  @override
  void dispose() {
    _factController.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _factController.text.trim();
    if (text.isEmpty) return;
    context.read<GameRoomState>().submitFact(text);
    _factController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final room = context.watch<GameRoomState>();
    final country = room.country;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _PlayersStrip(),
            const SizedBox(height: 16),
            if (country != null)
              Center(child: CountryCard(country: country)),
            const SizedBox(height: 18),
            if (room.isMyTurn) ...[
              Text('دورك يا نجم — قول معلومة عن الدولة دي:',
                  style: AppText.ui(size: 14.5, weight: FontWeight.w800)),
              const SizedBox(height: 10),
              TextField(
                controller: _factController,
                maxLength: 300,
                maxLines: 2,
                minLines: 1,
                style: AppText.ui(size: 15, weight: FontWeight.w700),
                decoration: const InputDecoration(
                    hintText: 'اكتب معلومتك هنا... من غير هبد 👀'),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 10),
              GameButton(
                label: 'ابعت المعلومة',
                icon: Icons.send_rounded,
                gradient: AppGradients.truth,
                glowColor: AppColors.emeraldDeep,
                onPressed: _submit,
              ),
            ] else
              GlassContainer(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${room.currentPlayer?.name ?? '...'} بيكتب معلومته... استعد للتصويت!',
                        style:
                            AppText.ui(size: 13.5, weight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// EVALUATING
// ---------------------------------------------------------------------------

class _EvaluatingView extends StatelessWidget {
  const _EvaluatingView({super.key});

  @override
  Widget build(BuildContext context) {
    final fact =
        context.select((GameRoomState r) => r.submittedFact) ?? '';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🤖', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 14),
            const CircularProgressIndicator(strokeWidth: 2.6),
            const SizedBox(height: 18),
            Text('الحكم الذكي بيقرا الهبدة...',
                style: AppText.ui(size: 16, weight: FontWeight.w800)),
            const SizedBox(height: 10),
            GlassContainer(
              padding: const EdgeInsets.all(14),
              child: Text('"$fact"',
                  textAlign: TextAlign.center,
                  style: AppText.ui(
                      size: 14, color: AppColors.textSecondary, height: 1.5)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AWAITING_VOTES
// ---------------------------------------------------------------------------

class _VotingView extends StatelessWidget {
  const _VotingView({super.key});

  @override
  Widget build(BuildContext context) {
    final room = context.watch<GameRoomState>();
    final verdict = room.verdict;
    final (accent, label) = switch (verdict?.verdict) {
      'true' => (AppColors.emerald, 'الحكم الذكي: صح ✔'),
      'false' => (AppColors.ruby, 'الحكم الذكي: هبد ✖'),
      _ => (AppColors.amber, 'الحكم الذكي: مش متأكد 🤔'),
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _PlayersStrip(),
            const SizedBox(height: 18),
            GlassContainer(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Text(
                    '${room.currentPlayer?.name ?? ''} قال:',
                    style: AppText.ui(
                        size: 12.5, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Text('"${room.submittedFact ?? ''}"',
                      textAlign: TextAlign.center,
                      style: AppText.ui(
                          size: 17, weight: FontWeight.w800, height: 1.5)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // AI verdict card, color-coded.
            GradientBorderCard(
              gradient: LinearGradient(colors: [
                accent,
                accent.withValues(alpha: .4),
              ]),
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Text(label,
                      style: AppText.ui(
                          size: 15,
                          weight: FontWeight.w800,
                          color: accent)),
                  if ((verdict?.explanation ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(verdict!.explanation,
                        textAlign: TextAlign.center,
                        style: AppText.ui(
                            size: 12.5,
                            color: AppColors.textSecondary,
                            height: 1.5)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (room.myVoteCast)
              Text(
                'صوتك وصل ✔ — مستنيين الباقيين (${room.votesCast}/${room.votesNeeded})',
                textAlign: TextAlign.center,
                style: AppText.ui(size: 13.5, weight: FontWeight.w700),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: GameButton(
                      label: 'هبد! ✖',
                      height: 56,
                      gradient: AppGradients.falsehood,
                      glowColor: AppColors.rubyDeep,
                      onPressed: () =>
                          context.read<GameRoomState>().submitVote(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GameButton(
                      label: 'صح ✔',
                      height: 56,
                      gradient: AppGradients.truth,
                      glowColor: AppColors.emeraldDeep,
                      onPressed: () =>
                          context.read<GameRoomState>().submitVote(true),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// GAME_OVER + DISCONNECTED
// ---------------------------------------------------------------------------

class _GameOverView extends StatelessWidget {
  const _GameOverView({super.key});

  @override
  Widget build(BuildContext context) {
    final room = context.watch<GameRoomState>();
    final winner = room.winner;
    final ranked = [...room.players]
      ..sort((a, b) => b.score.compareTo(a.score));
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            children: [
              const Text('🏆', style: TextStyle(fontSize: 72)),
              const SizedBox(height: 12),
              if (winner != null)
                ShaderMask(
                  shaderCallback: (r) => AppGradients.turn.createShader(r),
                  child: Text(winner.name,
                      style: AppText.ui(
                          size: 30,
                          weight: FontWeight.w800,
                          color: Colors.white)),
                ),
              Text(
                room.gameOverReason == 'not_enough_players'
                    ? 'اللعبة خلصت — مفيش لاعيبة كفاية.'
                    : 'الفائز بالماتش!',
                style: AppText.ui(size: 13.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 22),
              GlassContainer(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    for (final (i, p) in ranked.indexed)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Text(
                              switch (i) {
                                0 => '🥇',
                                1 => '🥈',
                                2 => '🥉',
                                _ => '  ',
                              },
                              style: const TextStyle(fontSize: 18),
                            ),
                            const SizedBox(width: 8),
                            _Avatar(player: p, size: 30),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(p.name,
                                  style: AppText.ui(
                                      size: 14.5, weight: FontWeight.w700)),
                            ),
                            Text('${p.score}',
                                style: AppText.number(
                                    size: 20, weight: FontWeight.w800)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              GameButton(
                label: 'ارجع للرئيسية',
                icon: Icons.home_rounded,
                gradient: AppGradients.turn,
                glowColor: AppColors.neonPurple,
                onPressed: () =>
                    Navigator.of(context).popUntil((r) => r.isFirst),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisconnectedView extends StatelessWidget {
  const _DisconnectedView({super.key});

  @override
  Widget build(BuildContext context) {
    final reason =
        context.select((GameRoomState r) => r.disconnectReason);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded,
                size: 52, color: AppColors.ruby),
            const SizedBox(height: 14),
            Text(reason.isEmpty ? 'الاتصال اتقطع.' : reason,
                textAlign: TextAlign.center,
                style: AppText.ui(size: 15, weight: FontWeight.w700)),
            const SizedBox(height: 22),
            GameButton(
              label: 'ارجع',
              icon: Icons.arrow_back_rounded,
              borderGradient: AppGradients.turn,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
