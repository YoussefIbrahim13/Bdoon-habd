import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/game_events.dart';
import '../services/auth_service.dart';
import '../services/friendship_service.dart';
import '../state/friendship_state.dart';
import '../state/game_room_state.dart';
import '../theme/app_theme.dart';
import '../widgets/country_card.dart';
import '../widgets/friend_widgets.dart';
import '../widgets/game_button.dart';
import '../widgets/glass_container.dart';
import '../widgets/nova_components.dart';

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
  int _seenTimeouts = 0;
  int _seenFriendReqs = 0;
  int _seenInvites = 0;
  RoomInvitePushed? _pendingInvite;

  @override
  void initState() {
    super.initState();
    _room = context.read<GameRoomState>();
    _seenRounds = _room.roundsCompleted;
    _seenErrors = _room.errorsSeen;
    _seenTimeouts = _room.timeoutsSeen;
    _seenFriendReqs = _room.friendRequestsSeen;
    _seenInvites = _room.roomInvitesSeen;
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
    if (_room.timeoutsSeen != _seenTimeouts) {
      _seenTimeouts = _room.timeoutsSeen;
      final name = _room.playerById(_room.lastTimedOutPlayerId)?.name ?? '';
      _snack('⏰ خلص وقت $name — الجولة راحت عليه!', AppColors.ruby);
    }
    // A friend request rode the game socket — hand it to the friends state so
    // the bell badge (and requests center) update live, and nudge the player.
    if (_room.friendRequestsSeen != _seenFriendReqs) {
      _seenFriendReqs = _room.friendRequestsSeen;
      final req = _room.lastFriendRequest;
      if (req != null) {
        context.read<FriendshipState>().onIncomingRequest(
              PendingRequest(
                requestId: req.requestId,
                sender: Friend(
                  id: req.senderId,
                  name: req.senderName,
                  picture: req.senderPicture,
                ),
              ),
            );
        _snack('👋 ${req.senderName} عايز يضيفك صاحب!', AppColors.primaryViolet);
      }
    }
    // A friend invited me to their room → raise the Join/Decline banner.
    if (_room.roomInvitesSeen != _seenInvites) {
      _seenInvites = _room.roomInvitesSeen;
      if (_room.lastRoomInvite != null) {
        setState(() => _pendingInvite = _room.lastRoomInvite);
      }
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
          // Incoming room-invite banner (Join / Decline), floats at the top.
          if (_pendingInvite != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: _InviteBanner(
                  invite: _pendingInvite!,
                  onJoin: _joinInvitedRoom,
                  onDismiss: () => setState(() => _pendingInvite = null),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _joinInvitedRoom() {
    final code = _pendingInvite!.roomCode;
    setState(() => _pendingInvite = null);
    // Replace this room with the invited one (existing join flow handles a
    // full/started room by landing on the disconnected view with the reason).
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => GameRoomScreen(roomCode: code)),
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
              const SizedBox(height: 16),
              const _LobbySettings(),
              const SizedBox(height: 16),
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
              const SizedBox(height: 16),
              // Anyone in the room (host or guest) can invite online friends.
              PillButton.ghost(
                label: 'ادعُ أصحابك',
                icon: Icons.person_add_alt_1_rounded,
                onPressed: () => showInviteFriends(context),
              ),
              const SizedBox(height: 14),
              if (room.iAmHost)
                // Always tappable: the SERVER owns the minimum-players rule
                // (env-configurable, e.g. solo testing) — if there aren't
                // enough players it answers with an Arabic error event that
                // surfaces as a snackbar. The client never duplicates the
                // threshold.
                GameButton(
                  label: 'ابدأ اللعب',
                  icon: Icons.sports_esports_rounded,
                  height: 58,
                  gradient: AppGradients.turn,
                  glowColor: AppColors.neonPurple,
                  onPressed: room.startGame,
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
// Lobby settings — host edits, guests watch them sync live.
// ---------------------------------------------------------------------------

class _LobbySettings extends StatelessWidget {
  const _LobbySettings();

  static const _roundOptions = [1, 3, 5, 10];
  static const _difficulties = [
    ('easy', 'سهل'),
    ('progressive', 'متدرج'),
    ('hard', 'صعب'),
  ];

  @override
  Widget build(BuildContext context) {
    final room = context.watch<GameRoomState>();
    final editable = room.iAmHost;

    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('إعدادات الماتش',
                  style: AppText.ui(size: 14, weight: FontWeight.w800)),
              const Spacer(),
              if (!editable)
                Text('صاحب الأوضة بيظبطها',
                    style: AppText.ui(
                        size: 11, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 12),
          _SettingRow(
            label: 'عدد الدول',
            children: [
              for (final n in _roundOptions)
                _NeonChip(
                  label: '$n',
                  outfit: true,
                  selected: room.totalRounds == n,
                  accent: AppColors.electricBlue,
                  onTap: editable
                      ? () => context
                          .read<GameRoomState>()
                          .updateSettings(totalRounds: n)
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 10),
          _SettingRow(
            label: 'الصعوبة',
            children: [
              for (final (value, label) in _difficulties)
                _NeonChip(
                  label: label,
                  selected: room.difficulty == value,
                  accent: switch (value) {
                    'easy' => AppColors.emerald,
                    'hard' => AppColors.ruby,
                    _ => AppColors.amber,
                  },
                  onTap: editable
                      ? () => context
                          .read<GameRoomState>()
                          .updateSettings(difficulty: value)
                      : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String label;
  final List<Widget> children;

  const _SettingRow({required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 74,
          child: Text(label,
              style: AppText.ui(size: 12.5, color: AppColors.textSecondary)),
        ),
        Expanded(
          child: Wrap(spacing: 8, runSpacing: 8, children: children),
        ),
      ],
    );
  }
}

/// Neon selectable pill: filled + glowing when selected, hairline glass
/// otherwise. Null [onTap] = read-only (guest view) but still shows the
/// host's live selection.
class _NeonChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final bool outfit;
  final VoidCallback? onTap;

  const _NeonChip({
    required this.label,
    required this.selected,
    required this.accent,
    this.outfit = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final style = outfit
        ? AppText.number(
            size: 15,
            weight: FontWeight.w800,
            color: selected ? Colors.white : AppColors.textSecondary)
        : AppText.ui(
            size: 12.5,
            weight: FontWeight.w800,
            color: selected ? Colors.white : AppColors.textSecondary);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: .18) : AppColors.glassFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accent.withValues(alpha: .85) : AppColors.stroke,
            width: selected ? 1.4 : 1,
          ),
          boxShadow: selected
              ? [BoxShadow(color: accent.withValues(alpha: .35), blurRadius: 12)]
              : null,
        ),
        child: Text(label, style: style),
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
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (room.turnDeadline != null)
                  _TurnCountdown(
                    key: ValueKey(room.roundNumber),
                    deadline: room.turnDeadline!,
                    totalSeconds: room.turnTotalSeconds,
                    emphasize: room.isMyTurn,
                  ),
                const SizedBox(width: 12),
                Text(
                  'جولة ${room.roundNumber} / ${room.totalRounds}',
                  style: AppText.number(
                      size: 13,
                      weight: FontWeight.w700,
                      color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 10),
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
// Turn countdown — a neon ring animating toward the SERVER's deadline.
// The server is authoritative; this is pure presentation, so drift of a few
// hundred ms is invisible and harmless.
// ---------------------------------------------------------------------------

class _TurnCountdown extends StatefulWidget {
  final DateTime deadline;
  final int totalSeconds;

  /// True for the current speaker: the ring pulses/flashes in the last 5s.
  final bool emphasize;

  const _TurnCountdown({
    super.key,
    required this.deadline,
    required this.totalSeconds,
    required this.emphasize,
  });

  @override
  State<_TurnCountdown> createState() => _TurnCountdownState();
}

class _TurnCountdownState extends State<_TurnCountdown>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(
      vsync: this,
      duration: Duration(seconds: widget.totalSeconds),
    );
    _seek();
  }

  void _seek() {
    // Start mid-way if we joined late (snapshot with time already burned).
    final remainingMs = widget.deadline
        .difference(DateTime.now())
        .inMilliseconds
        .clamp(0, widget.totalSeconds * 1000);
    _clock
      ..value = 1 - remainingMs / (widget.totalSeconds * 1000)
      ..forward();
  }

  @override
  void didUpdateWidget(_TurnCountdown old) {
    super.didUpdateWidget(old);
    if (old.deadline != widget.deadline) _seek();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _clock,
      builder: (context, _) {
        final remaining = (1 - _clock.value) * widget.totalSeconds;
        final secondsLeft = remaining.ceil().clamp(0, widget.totalSeconds);
        final danger = remaining <= 5;
        final accent = danger
            ? AppColors.ruby
            : (remaining <= 10 ? AppColors.amber : AppColors.electricBlue);
        // 2Hz flash for the speaker in the final 5 seconds.
        final flash = danger && widget.emphasize
            ? (math.sin(remaining * math.pi * 4) + 1) / 2
            : 0.0;
        return Transform.scale(
          scale: 1 + .08 * flash,
          child: SizedBox(
            width: 52,
            height: 52,
            child: CustomPaint(
              painter: _CountdownPainter(
                progress: 1 - _clock.value,
                color: accent,
                glow: .45 + .55 * flash,
              ),
              child: Center(
                child: Text(
                  '$secondsLeft',
                  style: AppText.number(
                    size: 19,
                    weight: FontWeight.w800,
                    color: danger ? AppColors.ruby : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CountdownPainter extends CustomPainter {
  final double progress; // 1.0 full → 0.0 empty
  final Color color;
  final double glow;

  const _CountdownPainter({
    required this.progress,
    required this.color,
    required this.glow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const stroke = 4.5;
    final radius = (size.shortestSide - stroke) / 2 - 1;
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
    final sweep = progress * 2 * math.pi;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: .6 * glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(color, Colors.white, .25)!,
    );
  }

  @override
  bool shouldRepaint(_CountdownPainter old) =>
      old.progress != progress || old.color != color || old.glow != glow;
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
            if (room.isMyTurn)
              // No judging your own fact — the server enforces it, the UI
              // never offers it.
              GlassContainer(
                padding: const EdgeInsets.all(16),
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
                        'بانتظار تصويت الخصم والحكم... (${room.votesCast}/${room.votesNeeded})',
                        style:
                            AppText.ui(size: 13.5, weight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              )
            else if (room.myVoteCast)
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
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.ui(
                                      size: 14.5, weight: FontWeight.w700)),
                            ),
                            // Add-friend for everyone but yourself.
                            if (p.id != room.myId) ...[
                              AddFriendButton(playerId: p.id),
                              const SizedBox(width: 10),
                            ],
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

// ---------------------------------------------------------------------------
// Invite friends modal — lists friends, Invite button per ONLINE friend.
// ---------------------------------------------------------------------------

/// Open the invite sheet. Both the friends list ([FriendshipState]) and the
/// room socket ([GameRoomState]) are handed down via .value, since the modal
/// builds under the navigator root (outside the room screen's provider).
Future<void> showInviteFriends(BuildContext context) {
  final friends = context.read<FriendshipState>();
  final room = context.read<GameRoomState>();
  friends.refresh(); // freshen online status
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .55),
    builder: (_) => MultiProvider(
      providers: [
        ChangeNotifierProvider<FriendshipState>.value(value: friends),
        ChangeNotifierProvider<GameRoomState>.value(value: room),
      ],
      child: const _InviteFriendsSheet(),
    ),
  );
}

class _InviteFriendsSheet extends StatelessWidget {
  const _InviteFriendsSheet();

  @override
  Widget build(BuildContext context) {
    final friends = context.watch<FriendshipState>().friends;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GlassCard(
          radius: 26,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const DisplayHeadline('ادعُ أصحابك', size: 22),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (friends.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Text('لسه مفيش أصحاب — ضيف ناس بعد الماتش! 🤝',
                      textAlign: TextAlign.center,
                      style: AppText.ui(
                          size: 14, color: AppColors.textSecondary)),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * .5),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: friends.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) =>
                        _InviteRow(friend: friends[i]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InviteRow extends StatelessWidget {
  final Friend friend;

  const _InviteRow({required this.friend});

  @override
  Widget build(BuildContext context) {
    final sent =
        context.select((GameRoomState r) => r.hasInvited(friend.id));
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.surfaceActive,
                backgroundImage: friend.picture != null
                    ? NetworkImage(friend.picture!)
                    : null,
                child: friend.picture == null
                    ? Text(
                        friend.name.isEmpty ? '؟' : friend.name.characters.first,
                        style: AppText.ui(size: 14, weight: FontWeight.w800))
                    : null,
              ),
              if (friend.online)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: AppColors.emerald,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.surface, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(friend.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.ui(size: 14.5, weight: FontWeight.w700)),
                Text(friend.online ? 'أونلاين' : 'أوفلاين',
                    style: AppText.ui(
                        size: 11,
                        weight: FontWeight.w700,
                        color: friend.online
                            ? AppColors.emerald
                            : AppColors.textSecondary)),
              ],
            ),
          ),
          if (sent)
            const _MutedTag(icon: Icons.check_rounded, label: 'تم الإرسال')
          else if (!friend.online)
            const _MutedTag(icon: Icons.circle_outlined, label: 'مش متاح')
          else
            Material(
              color: AppColors.primaryViolet.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () =>
                    context.read<GameRoomState>().inviteFriend(friend.id),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: AppColors.primaryViolet.withValues(alpha: .6)),
                  ),
                  child: Text('دعوة',
                      style: AppText.ui(
                          size: 12.5,
                          weight: FontWeight.w800,
                          color: AppColors.primaryViolet)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MutedTag extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MutedTag({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 5),
          Text(label,
              style: AppText.ui(
                  size: 11.5,
                  weight: FontWeight.w700,
                  color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

/// The floating incoming-invite banner with Join (emerald) / Decline (ruby).
class _InviteBanner extends StatelessWidget {
  final RoomInvitePushed invite;
  final VoidCallback onJoin;
  final VoidCallback onDismiss;

  const _InviteBanner({
    required this.invite,
    required this.onJoin,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: GlassCard(
        radius: 20,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '👋 ${invite.senderName} عازمك تدخل أوضته',
              textAlign: TextAlign.center,
              style: AppText.ui(size: 14.5, weight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text('كود الأوضة ${invite.roomCode}',
                style: AppText.number(
                    size: 12.5,
                    weight: FontWeight.w700,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GameButton(
                    label: 'تجاهل',
                    height: 46,
                    gradient: AppGradients.falsehood,
                    glowColor: AppColors.rubyDeep,
                    onPressed: onDismiss,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GameButton(
                    label: 'دخول',
                    icon: Icons.login_rounded,
                    height: 46,
                    gradient: AppGradients.truth,
                    glowColor: AppColors.emeraldDeep,
                    onPressed: onJoin,
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
