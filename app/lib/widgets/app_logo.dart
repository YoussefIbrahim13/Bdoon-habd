import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'launcher_icon.dart';

/// The بدون هبد! brand mark — the same **crossed neon flags** as the phone's
/// launcher icon: cyan vs purple flags with glowing poles and waving
/// pennants (the country challenge), and a neon amber "!" at the
/// intersection (the "هبد!" spark).
///
/// The artwork is [NeonFlagsEmblem] — shared with [LauncherIconPainter] — so
/// the in-app logo and the home-screen icon are pixel-identical. Drawn
/// entirely in code: no image assets, scales losslessly to any size.
///
/// Neon intensity is controlled by [glow] (0 → dim, 1 → full) and can be
/// driven two ways:
/// - externally, by animating [glow] from a parent (the splash screen does
///   this); or
/// - internally, with [animate] — the logo idles with a slow breathing pulse
///   (glow + halo + a whisper of scale) so static screens feel alive.
class AppLogo extends StatefulWidget {
  final double size;

  /// Neon intensity 0..1. With [animate] on, this is the pulse's PEAK.
  final double glow;

  /// When false, the rounded gradient-border badge is omitted and only the
  /// crossed-flags emblem is drawn (transparent behind it). Used for
  /// embedding the emblem on an existing gradient capsule (e.g. the home
  /// screen).
  final bool showBadge;

  /// Self-driving idle breathing. Leave false when a parent already animates
  /// [glow] (e.g. the splash), so the two pulses don't fight.
  final bool animate;

  const AppLogo({
    super.key,
    this.size = 120,
    this.glow = .8,
    this.showBadge = true,
    this.animate = false,
  });

  @override
  State<AppLogo> createState() => _AppLogoState();
}

class _AppLogoState extends State<AppLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _breath.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(AppLogo old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_breath.isAnimating) {
      _breath.repeat(reverse: true);
    } else if (!widget.animate && _breath.isAnimating) {
      _breath
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clampedGlow = widget.glow.clamp(0.0, 1.0).toDouble();

    if (!widget.animate) {
      return RepaintBoundary(
        // Isolates glow repaints from the rest of the tree.
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _LogoPainter(glow: clampedGlow, showBadge: widget.showBadge),
        ),
      );
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _breath,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_breath.value);
          // Breathe between 62% and 100% of the requested peak glow.
          final g = clampedGlow * (0.62 + 0.38 * t);
          return Transform.scale(
            scale: 1.0 + 0.015 * t, // barely-there inhale
            child: Container(
              // Soft ambient halo that swells with the breath.
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color:
                        AppColors.neonPurple.withValues(alpha: .10 + .14 * t),
                    blurRadius: 26 + 18 * t,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: CustomPaint(
                size: Size.square(widget.size),
                painter: _LogoPainter(glow: g, showBadge: widget.showBadge),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  final double glow;
  final bool showBadge;

  _LogoPainter({required this.glow, this.showBadge = true});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.shortestSide / 100);
    if (showBadge) {
      _paintBadge(canvas);
    } else {
      // Badge-less: a soft dark vignette behind the emblem so the neon
      // reads crisply even on a bright host surface (the home screen's
      // gradient capsule).
      canvas.drawCircle(
        const Offset(50, 52),
        46,
        Paint()
          ..shader = ui.Gradient.radial(
            const Offset(50, 52),
            46,
            [
              Colors.black.withValues(alpha: .38),
              Colors.black.withValues(alpha: 0),
            ],
          ),
      );
    }
    // Inset the shared emblem so the flag tips clear the badge border (or
    // the host capsule's rounded corners when the badge is off).
    canvas.translate(50, 50);
    canvas.scale(showBadge ? .82 : .96);
    canvas.translate(-50, -50);
    NeonFlagsEmblem.paint(canvas, glow: glow);
  }

  void _paintBadge(Canvas c) {
    final rrect = RRect.fromRectAndRadius(
      const Rect.fromLTRB(6, 6, 94, 94),
      const Radius.circular(26),
    );
    // Soft halo behind the whole badge.
    c.drawRRect(
      rrect,
      Paint()
        ..color = AppColors.neonPurple.withValues(alpha: .30 * glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    // Obsidian fill with a faint diagonal sheen.
    c.drawRRect(
      rrect,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(6, 6),
          const Offset(94, 94),
          [const Color(0xFF1B1E29), const Color(0xFF111319)],
        ),
    );
    // Gradient border (electric blue → neon purple).
    c.drawRRect(
      rrect.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..shader = ui.Gradient.linear(
          const Offset(6, 6),
          const Offset(94, 94),
          [AppColors.electricBlue, AppColors.neonPurple],
        ),
    );
  }

  @override
  bool shouldRepaint(_LogoPainter old) =>
      old.glow != glow || old.showBadge != showBadge;
}
