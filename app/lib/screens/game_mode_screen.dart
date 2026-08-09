import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/fx.dart';
import '../widgets/nova_components.dart';
import '../widgets/rotating_globe.dart';
import 'home_screen.dart';
import 'online_hub_screen.dart';
import 'sign_in_screen.dart';

/// Entry gateway: pick the game mode before the lobby.
///
/// - "لعب أوفلاين" (neon-cyan) → the existing local pass-and-play lobby
///   ([HomeScreen]).
/// - "لعب أونلاين" (neon-magenta) → Google Sign-In gateway when signed out;
///   the online experience (in active development) when signed in.
///
/// The obsidian background carries two slow-drifting radial glows (cyan +
/// purple) on a single long-running controller, isolated behind a
/// [RepaintBoundary] so the drift never repaints the foreground.
class GameModeScreen extends StatefulWidget {
  const GameModeScreen({super.key});

  @override
  State<GameModeScreen> createState() => _GameModeScreenState();
}

class _GameModeScreenState extends State<GameModeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  )..repeat();

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  void _openOffline() {
    Navigator.of(context).push(
      NovaPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  void _onOnlineTap() {
    if (context.read<AuthService>().isSignedIn) {
      Navigator.of(context).push(
        NovaPageRoute(builder: (_) => const OnlineHubScreen()),
      );
    } else {
      Navigator.of(context).push(
        NovaPageRoute(builder: (_) => const SignInScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Slow-drifting ambient glows behind everything.
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _drift,
                builder: (context, _) =>
                    _DriftingGlows(t: _drift.value),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 620;
                      final signedIn = context
                          .select((AuthService a) => a.isSignedIn);
                      final playerName = context
                          .select((AuthService a) => a.user?.name);
                      final cards = [
                        _ModeCard(
                          accent: const Color(0xFF22D3EE),
                          icon: Icons.groups_rounded,
                          title: 'لعب أوفلاين',
                          subtitle:
                              'باس-آند-بلاي محلي: لاعيبة في نفس الأوضة وحكم واحد ماسك الموبايل.',
                          onTap: _openOffline,
                        ),
                        // Signed out → tap opens the Google Sign-In gateway;
                        // signed in → straight into the online experience.
                        _ModeCard(
                          accent: const Color(0xFFE45CFF),
                          icon: Icons.public_rounded,
                          title: 'لعب أونلاين',
                          subtitle: signedIn
                              ? 'متصل كـ ${playerName ?? ''} ✔ — جاهز لتحدي أصحابك عبر الشبكة.'
                              : 'سجّل دخولك بجوجل وادخل تحديات الأونلاين.',
                          onTap: _onOnlineTap,
                        ),
                      ];
                      return Column(
                        children: [
                          // Hero: the rotating Earth sits behind the wordmark.
                          SizedBox(
                            height: 260,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                const RotatingGlobe(size: 240),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const DisplayHeadline(
                                      'بدون\nهبد!',
                                      size: 60,
                                      gradient: true,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'كوكب واحد · تحدٍّ واحد',
                                      textAlign: TextAlign.center,
                                      style: AppText.ui(
                                        size: 13,
                                        weight: FontWeight.w600,
                                        color: AppColors.textSecondary,
                                        spacing: 2,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'اختار طريقة اللعب',
                            style: AppText.ui(
                              size: 14.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 24),
                          // Side-by-side on wide screens, stacked on phones.
                          // IntrinsicHeight equalizes the two card heights —
                          // plain stretch would demand infinite height inside
                          // the unbounded scroll column.
                          if (wide)
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(child: cards[0]),
                                  const SizedBox(width: 18),
                                  Expanded(child: cards[1]),
                                ],
                              ),
                            )
                          else
                            Column(
                              children: [
                                cards[0],
                                const SizedBox(height: 16),
                                cards[1],
                              ],
                            ),
                          if (signedIn) ...[
                            const SizedBox(height: 14),
                            TextButton(
                              onPressed: () =>
                                  context.read<AuthService>().signOut(),
                              child: Text(
                                'تسجيل الخروج',
                                style: AppText.ui(
                                  size: 12.5,
                                  weight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
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

/// The two drifting radial blobs. Pure paint — rebuilt only inside its own
/// RepaintBoundary as [t] (0..1) loops.
class _DriftingGlows extends StatelessWidget {
  final double t;

  const _DriftingGlows({required this.t});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final a = t * 2 * math.pi;
    return Stack(
      children: [
        Positioned(
          top: -140 + 40 * math.sin(a),
          right: -90 + 30 * math.cos(a),
          child: const _GlowBlob(Color(0xFF22D3EE), 360),
        ),
        Positioned(
          bottom: -160 + 44 * math.cos(a + 1.3),
          left: -110 + 34 * math.sin(a + 1.3),
          child: const _GlowBlob(AppColors.neonPurple, 420),
        ),
        // Faint center wash so the cards float on depth, not on black.
        Positioned(
          top: size.height * .3,
          left: size.width * .2,
          child: const _GlowBlob(AppColors.electricBlue, 300, alpha: .06),
        ),
      ],
    );
  }
}

class _GlowBlob extends StatelessWidget {
  final Color color;
  final double size;
  final double alpha;

  const _GlowBlob(this.color, this.size, {this.alpha = .13});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: alpha), Colors.transparent],
          ),
        ),
      ),
    );
  }
}

/// One massive mode card: accent-ringed glass, glowing icon capsule, title,
/// and subtitle.
class _ModeCard extends StatefulWidget {
  final Color accent;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ModeCard({
    required this.accent,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  State<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<_ModeCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return AnimatedScale(
      scale: _pressed ? .965 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.card + 1.4),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: .65),
                AppColors.stroke,
                accent.withValues(alpha: .35),
              ],
            ),
            boxShadow: [
              ...AppShadows.soft,
              BoxShadow(
                color: accent.withValues(alpha: .16),
                blurRadius: 34,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          padding: const EdgeInsets.all(1.4),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.card),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(const Color(0xFF151824), accent, .07)!,
                  const Color(0xFF10121A),
                ],
              ),
            ),
            child: Column(
              children: [
                // Glowing icon capsule.
                Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: accent.withValues(alpha: .12),
                    border: Border.all(
                      color: accent.withValues(alpha: .55),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: .30),
                        blurRadius: 22,
                      ),
                    ],
                  ),
                  child: Icon(
                    widget.icon,
                    size: 32,
                    color: Color.lerp(accent, Colors.white, .35),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: AppText.ui(size: 19, weight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.subtitle,
                  textAlign: TextAlign.center,
                  style: AppText.ui(
                    size: 12.8,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

