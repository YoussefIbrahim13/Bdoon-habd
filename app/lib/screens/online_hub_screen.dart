import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/game_socket_service.dart';
import '../state/friendship_state.dart';
import '../theme/app_theme.dart';
import '../widgets/friend_widgets.dart';
import '../widgets/fx.dart';
import '../widgets/game_button.dart';
import '../widgets/glass_container.dart';
import '../widgets/nova_components.dart';
import 'game_room_screen.dart';

/// Online mode hub: create a room (REST → then socket) or join a friend's
/// room by its 6-digit code.
class OnlineHubScreen extends StatefulWidget {
  const OnlineHubScreen({super.key});

  @override
  State<OnlineHubScreen> createState() => _OnlineHubScreenState();
}

class _OnlineHubScreenState extends State<OnlineHubScreen> {
  final _codeController = TextEditingController();
  final _service = GameWebSocketService();
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    // Pull friends + pending so the bell badge and podium buttons are fresh.
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<FriendshipState>().refresh());
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _createRoom() async {
    final auth = context.read<AuthService>();
    final token = auth.token;
    if (token == null) return;
    setState(() => _creating = true);
    try {
      final code = await _service.createRoom(token: token);
      if (!mounted) return;
      _openRoom(code);
    } catch (e) {
      if (!mounted) return;
      _snack('فشل إنشاء الأوضة — السيرفر ممكن يكون بيصحى، جرّب تاني.',
          AppColors.ruby);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _joinRoom() {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      _snack('اكتب كود الأوضة المكوّن من ٦ أرقام.', AppColors.amber);
      return;
    }
    _openRoom(code);
  }

  void _openRoom(String code) {
    Navigator.of(context).push(
      NovaPageRoute(builder: (_) => GameRoomScreen(roomCode: code)),
    );
  }

  void _snack(String msg, Color accent) {
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
          content:
              Text(msg, style: AppText.ui(size: 14, weight: FontWeight.w700)),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final playerName =
        context.select((AuthService a) => a.user?.name ?? 'يا بطل');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
        leadingWidth: 64,
        leading: const Padding(
          padding: EdgeInsetsDirectional.only(start: 12),
          child: Center(child: GlassBackButton()),
        ),
        title: Text('لعب أونلاين',
            style: AppText.ui(size: 18, weight: FontWeight.w800)),
        actions: const [FriendRequestsBell(), SizedBox(width: 4)],
      ),
      body: Stack(
        children: [
          const AmbientBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'أهلاً $playerName 👋',
                        textAlign: TextAlign.center,
                        style: AppText.ui(size: 22, weight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'اعمل أوضة وابعت الكود لأصحابك، أو ادخل بكود موجود.',
                        textAlign: TextAlign.center,
                        style: AppText.ui(
                            size: 13.5, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 28),
                      // --- Create room -------------------------------------
                      GlassCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Icon(Icons.add_home_rounded,
                                size: 34,
                                color: AppColors.electricBlue
                                    .withValues(alpha: .9)),
                            const SizedBox(height: 10),
                            Text('أوضة جديدة',
                                style: AppText.ui(
                                    size: 16, weight: FontWeight.w800)),
                            const SizedBox(height: 14),
                            GameButton(
                              label: _creating
                                  ? 'جارٍ إنشاء الأوضة...'
                                  : 'اعمل أوضة',
                              icon: _creating ? null : Icons.rocket_launch_rounded,
                              leading: _creating
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2.2),
                                    )
                                  : null,
                              gradient: AppGradients.turn,
                              glowColor: AppColors.neonPurple,
                              mediumHaptic: true,
                              onPressed: _creating ? null : _createRoom,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      // --- Join room ---------------------------------------
                      GlassCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Icon(Icons.meeting_room_rounded,
                                size: 34,
                                color:
                                    const Color(0xFFE45CFF).withValues(alpha: .9)),
                            const SizedBox(height: 10),
                            Text('عندك كود؟',
                                style: AppText.ui(
                                    size: 16, weight: FontWeight.w800)),
                            const SizedBox(height: 14),
                            _CodeField(
                              controller: _codeController,
                              onSubmitted: _joinRoom,
                            ),
                            const SizedBox(height: 14),
                            GameButton(
                              label: 'ادخل الأوضة',
                              icon: Icons.login_rounded,
                              borderGradient: AppGradients.turn,
                              mediumHaptic: true,
                              onPressed: _joinRoom,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Oversized 6-digit room-code input with a violet glow that blooms while
/// focused — the numeric display treatment for codes.
class _CodeField extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSubmitted;

  const _CodeField({required this.controller, required this.onSubmitted});

  @override
  State<_CodeField> createState() => _CodeFieldState();
}

class _CodeFieldState extends State<_CodeField> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.field),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: AppColors.primaryViolet.withValues(alpha: .32),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ]
            : const [],
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 6,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: AppText.number(size: 26, weight: FontWeight.w800, spacing: 8),
        decoration: InputDecoration(
          counterText: '',
          hintText: '000000',
          hintStyle: AppText.number(
            size: 26,
            weight: FontWeight.w800,
            color: AppColors.textSecondary.withValues(alpha: .35),
            spacing: 8,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.field),
            borderSide: BorderSide(
                color: AppColors.primaryViolet.withValues(alpha: .28)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.field),
            borderSide:
                const BorderSide(color: AppColors.primaryViolet, width: 1.6),
          ),
        ),
        onSubmitted: (_) => widget.onSubmitted(),
      ),
    );
  }
}
