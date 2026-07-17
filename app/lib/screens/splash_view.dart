import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/glass_container.dart';
import 'game_mode_screen.dart';

/// Animated brand splash. Fully self-contained (no assets):
///  - the logo scales + fades in (staggered),
///  - a looping neon pulse drives the logo's glow and a halo,
///  - the Arabic title slides up + fades,
///  - a Latin subtitle reveals with animated letter-spacing,
///  - then it auto-transitions to the [GameModeScreen] gateway via a
///    fade/zoom route.
class SplashView extends StatefulWidget {
  const SplashView({super.key});

  static const _bg = Color(0xFF121214);
  static const _hold = Duration(seconds: 3);

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> with TickerProviderStateMixin {
  // One-shot entrance controller drives the staggered reveal.
  late final AnimationController _entry = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  // Independent looping controller for the neon "breathing" pulse.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  late final Animation<double> _logoScale = CurvedAnimation(
    parent: _entry,
    curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack),
  );
  late final Animation<double> _logoFade = CurvedAnimation(
    parent: _entry,
    curve: const Interval(0.0, 0.40, curve: Curves.easeOut),
  );
  late final Animation<double> _titleReveal = CurvedAnimation(
    parent: _entry,
    curve: const Interval(0.45, 0.85, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _subtitleReveal = CurvedAnimation(
    parent: _entry,
    curve: const Interval(0.65, 1.0, curve: Curves.easeOut),
  );

  Timer? _navTimer;

  @override
  void initState() {
    super.initState();
    _entry.forward();
    _navTimer = Timer(SplashView._hold, _goHome);
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context)
        .pushReplacement(_FadeZoomRoute(const GameModeScreen()));
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _entry.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SplashView._bg,
      body: Stack(
        children: [
          const AmbientBackground(),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // --- Logo: staggered scale + fade, with a pulsing halo. ---
                FadeTransition(
                  opacity: _logoFade,
                  child: ScaleTransition(
                    scale: _logoScale,
                    child: AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, child) {
                        final t = Curves.easeInOut.transform(_pulse.value);
                        final glow = 0.55 + 0.45 * t;
                        return Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.neonPurple
                                    .withValues(alpha: 0.28 * t),
                                blurRadius: 40 + 24 * t,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: AppLogo(size: 132, glow: glow),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 34),

                // --- Arabic title: slide-up + fade reveal. ---
                AnimatedBuilder(
                  animation: _titleReveal,
                  builder: (_, _) => Opacity(
                    opacity: _titleReveal.value,
                    child: Transform.translate(
                      offset: Offset(0, 26 * (1 - _titleReveal.value)),
                      child: ShaderMask(
                        shaderCallback: (r) => AppGradients.turn.createShader(r),
                        child: Text(
                          'بدون هبد!',
                          style: AppText.ui(
                            size: 42,
                            weight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // --- Latin subtitle: animated letter-spacing reveal. ---
                // (Tracking is applied to Latin only — expanding letter-spacing
                //  on the cursive Arabic title would break its joined letters.)
                AnimatedBuilder(
                  animation: _subtitleReveal,
                  builder: (_, _) {
                    final v = _subtitleReveal.value;
                    return Opacity(
                      opacity: v,
                      child: Text(
                        'BEDOON HABD',
                        style: AppText.number(
                          size: 12.5,
                          weight: FontWeight.w600,
                          color: AppColors.textSecondary,
                          spacing: 2 + 8 * v, // 2 → 10 as it reveals
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // --- Tagline pinned near the bottom, last to appear. ---
          Positioned(
            left: 0,
            right: 0,
            bottom: 44,
            child: FadeTransition(
              opacity: _subtitleReveal,
              child: Text(
                'لعبة معلومات البلاد — الحكم النهائي لك',
                textAlign: TextAlign.center,
                style: AppText.ui(size: 12.5, color: AppColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fade + subtle zoom page transition (no abrupt jump into the gateway).
class _FadeZoomRoute extends PageRouteBuilder<void> {
  _FadeZoomRoute(Widget page)
      : super(
          transitionDuration: const Duration(milliseconds: 620),
          reverseTransitionDuration: const Duration(milliseconds: 320),
          pageBuilder: (_, _, _) => page,
          transitionsBuilder: (_, animation, _, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 1.06, end: 1.0).animate(curved),
                child: child,
              ),
            );
          },
        );
}
