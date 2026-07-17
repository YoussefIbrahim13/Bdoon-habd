import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/glass_container.dart';

/// Google Sign-In gateway for the online mode.
///
/// Breathing crossed-flags logo, a glowing title, and one ultra-premium
/// glassmorphic Google button (code-drawn brand "G", neon white/blue rim,
/// tactile 96.5% press-scale). Outcome feedback rides our neon snackbars:
/// amber for a cancelled popup, ruby for failures, emerald welcome on
/// success (then pops back to the gateway, which now shows online unlocked).
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  Future<void> _signIn() async {
    final auth = context.read<AuthService>();
    final result = await auth.signInWithGoogle();
    if (!mounted) return;
    switch (result) {
      case SignInResult.success:
        _snack(
          'أهلاً ${auth.user?.name ?? ''}! تم تسجيل الدخول ✔',
          AppColors.emerald,
        );
        Navigator.of(context).pop();
      case SignInResult.cancelled:
        _snack('اتلغى تسجيل الدخول — ولا يهمك، جرّب في أي وقت.', AppColors.amber);
      case SignInResult.failed:
        _snack(auth.lastError, AppColors.ruby);
    }
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
          content: Text(
            msg,
            style: AppText.ui(size: 14, weight: FontWeight.w700),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.select((AuthService a) => a.isBusy);

    return Scaffold(
      body: Stack(
        children: [
          const AmbientBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    children: [
                      const AppLogo(size: 120, animate: true),
                      const SizedBox(height: 24),
                      ShaderMask(
                        shaderCallback: (r) => AppGradients.turn.createShader(r),
                        child: Text(
                          'سجل دخولك لتحدي الأونلاين ⚡',
                          textAlign: TextAlign.center,
                          style: AppText.ui(
                            size: 24,
                            weight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'حساب واحد يحفظ سكورك وانتصاراتك،\nويجهّزك لتحدي أصحابك عبر الشبكة.',
                        textAlign: TextAlign.center,
                        style: AppText.ui(
                          size: 13.5,
                          height: 1.6,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 40),
                      _GoogleButton(busy: busy, onTap: busy ? null : _signIn),
                      const SizedBox(height: 18),
                      TextButton(
                        onPressed:
                            busy ? null : () => Navigator.of(context).pop(),
                        child: Text(
                          'الرجوع',
                          style: AppText.ui(
                            size: 13,
                            weight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
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

/// The premium Google button: frosted glass, neon white→blue rim, code-drawn
/// brand "G", spinner while the flow is in flight, tactile press-scale.
class _GoogleButton extends StatefulWidget {
  final bool busy;
  final VoidCallback? onTap;

  const _GoogleButton({required this.busy, required this.onTap});

  @override
  State<_GoogleButton> createState() => _GoogleButtonState();
}

class _GoogleButtonState extends State<_GoogleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return AnimatedScale(
      scale: _pressed ? .965 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel:
            enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onTap,
        child: Container(
          // Neon white→blue rim.
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.button + 1.5),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: .75),
                AppColors.electricBlue.withValues(alpha: .65),
              ],
            ),
            boxShadow: [
              ...AppShadows.soft,
              BoxShadow(
                color: AppColors.electricBlue.withValues(alpha: .22),
                blurRadius: 26,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.all(1.5),
          child: GlassContainer(
            radius: AppRadii.button,
            blur: 22,
            tint: const Color(0x1AFFFFFF),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.busy)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                else
                  const CustomPaint(
                    size: Size(22, 22),
                    painter: _GoogleGPainter(),
                  ),
                const SizedBox(width: 14),
                Flexible(
                  child: Text(
                    widget.busy
                        ? 'جارٍ تسجيل الدخول...'
                        : 'تسجيل الدخول باستخدام جوجل',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.ui(size: 15.5, weight: FontWeight.w800),
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

/// The Google brand "G" drawn in code (no image assets): four colored arc
/// segments + the red-to-bar crossstroke, on Google's official palette.
class _GoogleGPainter extends CustomPainter {
  const _GoogleGPainter();

  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final stroke = size.width * .21;
    final radius = (size.shortestSide - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    Paint arc(Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = c;

    // Angles in radians; 0 = 3 o'clock, positive = clockwise.
    // Red: top arc; yellow: left-bottom; green: bottom; blue: right + bar.
    canvas.drawArc(rect, -math.pi * .80, math.pi * .55, false, arc(_red));
    canvas.drawArc(rect, math.pi * .75, math.pi * .45, false, arc(_yellow));
    canvas.drawArc(rect, math.pi * .25, math.pi * .50, false, arc(_green));
    canvas.drawArc(rect, -math.pi * .06, math.pi * .31, false, arc(_blue));

    // Blue horizontal bar into the G's mouth.
    canvas.drawRect(
      Rect.fromLTWH(
        center.dx,
        center.dy - stroke / 2,
        radius + stroke / 2,
        stroke,
      ),
      Paint()..color = _blue,
    );
  }

  @override
  bool shouldRepaint(_GoogleGPainter old) => false;
}
