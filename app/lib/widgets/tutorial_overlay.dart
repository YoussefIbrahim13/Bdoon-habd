import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'game_button.dart';

/// One stop on the guided tour: which widget(s) to spotlight and what to say.
/// Multiple [targets] are merged into one spotlight rect (e.g. the country
/// card + the timer bar as a single "hero zone").
class TutorialStep {
  final List<GlobalKey> targets;
  final String text;

  const TutorialStep({required this.targets, required this.text});
}

/// Premium glassmorphic coach-marks overlay.
///
/// Renders a frosted, dimmed veil over the whole screen with a clear rounded
/// "spotlight" hole cut out over the current step's target (the veil is a
/// [BackdropFilter] clipped by an even-odd path, so the hole stays sharp
/// while everything else blurs). A neon-tinted obsidian tooltip card floats
/// beside the hole with an arrow pointing at it, a step counter in Outfit,
/// "التالي" to advance, and "تخطي الدليل" pinned at the top.
///
/// The spotlight GLIDES between steps (RectTween, easeOutCubic) instead of
/// jumping. Tapping anywhere on the veil also advances — fewer dead taps.
///
/// Purely presentational: the host owns the trigger, the game-timer pause,
/// and persistence, and receives [onDone] for both "finish" and "skip".
class TutorialOverlay extends StatefulWidget {
  final List<TutorialStep> steps;
  final VoidCallback onDone;

  const TutorialOverlay({
    super.key,
    required this.steps,
    required this.onDone,
  });

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay> {
  int _step = 0;
  Rect? _rect; // current step's target rect (measured post-frame)
  Rect? _prevRect; // where the spotlight glides FROM

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  /// Union of the current step's target rects, in global coordinates (the
  /// overlay fills the screen, so global == local here).
  Rect? _rectFor(TutorialStep step) {
    Rect? rect;
    for (final key in step.targets) {
      final ctx = key.currentContext;
      final box = ctx?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final r = box.localToGlobal(Offset.zero) & box.size;
      rect = rect == null ? r : rect.expandToInclude(r);
    }
    return rect;
  }

  void _measure() {
    if (!mounted) return;
    final r = _rectFor(widget.steps[_step]);
    if (r != _rect) setState(() => _rect = r);
  }

  void _next() {
    if (_step >= widget.steps.length - 1) {
      widget.onDone();
      return;
    }
    setState(() {
      _prevRect = _rect;
      _step++;
      _rect = _rectFor(widget.steps[_step]) ?? _rect;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final topInset = MediaQuery.paddingOf(context).top;
    final rect = _rect;

    // First frame: targets not measured yet — plain dim while we wait.
    if (rect == null) {
      return Container(color: Colors.black.withValues(alpha: .6));
    }

    final hole = rect.inflate(7);
    final isLast = _step == widget.steps.length - 1;

    return TweenAnimationBuilder<Rect?>(
      key: ValueKey(_step), // restart the glide on every step change
      tween: RectTween(begin: _prevRect?.inflate(7) ?? hole, end: hole),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      builder: (context, animHole, _) {
        final h = animHole!;
        final holeRRect = RRect.fromRectAndRadius(
          h,
          const Radius.circular(20),
        );
        // Tooltip above or below the hole, wherever there's more room.
        final placeBelow = h.center.dy < screen.height * .52;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Frosted dim veil with the spotlight hole punched out.
            ClipPath(
              clipper: _SpotlightClipper(holeRRect),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: Container(color: Colors.black.withValues(alpha: .62)),
              ),
            ),
            // Tap-anywhere-to-advance catcher (covers the hole too, so the
            // spotlighted control can't actually be pressed mid-tour).
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _next,
                child: const SizedBox.expand(),
              ),
            ),
            // Neon rim hugging the spotlight.
            Positioned.fromRect(
              rect: h.inflate(2),
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: AppColors.electricBlue.withValues(alpha: .85),
                      width: 1.8,
                    ),
                    boxShadow: [
                      ...AppShadows.glow(AppColors.electricBlue,
                          alpha: .38, blur: 22),
                      BoxShadow(
                        color: AppColors.neonPurple.withValues(alpha: .22),
                        blurRadius: 30,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Floating tooltip card + arrow.
            Positioned(
              left: 0,
              right: 0,
              top: placeBelow ? h.bottom + 8 : null,
              bottom: placeBelow ? null : screen.height - h.top + 8,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: placeBelow
                    ? [
                        _Arrow(pointUp: true, x: h.center.dx, screen: screen),
                        _TooltipCard(
                          step: _step,
                          total: widget.steps.length,
                          text: widget.steps[_step].text,
                          isLast: isLast,
                          onNext: _next,
                        ),
                      ]
                    : [
                        _TooltipCard(
                          step: _step,
                          total: widget.steps.length,
                          text: widget.steps[_step].text,
                          isLast: isLast,
                          onNext: _next,
                        ),
                        _Arrow(pointUp: false, x: h.center.dx, screen: screen),
                      ],
              ),
            ),
            // Skip, pinned at the top.
            PositionedDirectional(
              top: topInset + 10,
              start: 18,
              child: Material(
                color: AppColors.glassTint,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: widget.onDone,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.stroke),
                    ),
                    child: Text(
                      'تخطي الدليل',
                      style: AppText.ui(
                        size: 12.5,
                        weight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The neon-obsidian tooltip card: Outfit step counter, Cairo body text
/// (Outfit has no Arabic glyphs), progress dots, and the next button.
class _TooltipCard extends StatelessWidget {
  final int step;
  final int total;
  final String text;
  final bool isLast;
  final VoidCallback onNext;

  const _TooltipCard({
    required this.step,
    required this.total,
    required this.text,
    required this.isLast,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.electricBlue.withValues(alpha: .5),
                AppColors.stroke,
                AppColors.neonPurple.withValues(alpha: .5),
              ],
            ),
            boxShadow: AppShadows.soft,
          ),
          padding: const EdgeInsets.all(1.3),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            decoration: BoxDecoration(
              color: const Color(0xF5131622),
              borderRadius: BorderRadius.circular(21),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${step + 1} / $total',
                  style: AppText.number(
                    size: 13,
                    weight: FontWeight.w700,
                    color: AppColors.electricBlue,
                    spacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  text,
                  style: AppText.ui(size: 14.5, height: 1.55),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    for (var i = 0; i < total; i++)
                      Container(
                        width: i == step ? 16 : 6,
                        height: 6,
                        margin: const EdgeInsetsDirectional.only(end: 5),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          color: i == step
                              ? AppColors.electricBlue
                              : AppColors.stroke,
                        ),
                      ),
                    const Spacer(),
                    SizedBox(
                      width: 132,
                      child: GameButton(
                        label: isLast ? 'يلا نلعب!' : 'التالي',
                        height: 42,
                        gradient: AppGradients.turn,
                        glowColor: AppColors.neonPurple,
                        textStyle:
                            AppText.ui(size: 13.5, weight: FontWeight.w800),
                        onPressed: onNext,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small triangle aimed at the spotlight, horizontally aligned to its center.
class _Arrow extends StatelessWidget {
  final bool pointUp;
  final double x;
  final Size screen;

  const _Arrow({required this.pointUp, required this.x, required this.screen});

  @override
  Widget build(BuildContext context) {
    // Alignment expects -1..1 across the width.
    final align = ((x / screen.width) * 2 - 1).clamp(-.85, .85);
    return Align(
      alignment: Alignment(align.toDouble(), 0),
      child: CustomPaint(
        size: const Size(18, 9),
        painter: _ArrowPainter(pointUp: pointUp),
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  final bool pointUp;

  const _ArrowPainter({required this.pointUp});

  @override
  void paint(Canvas canvas, Size size) {
    final path = pointUp
        ? (Path()
          ..moveTo(size.width / 2, 0)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close())
        : (Path()
          ..moveTo(0, 0)
          ..lineTo(size.width, 0)
          ..lineTo(size.width / 2, size.height)
          ..close());
    canvas.drawPath(path, Paint()..color = const Color(0xF5131622));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.electricBlue.withValues(alpha: .35),
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.pointUp != pointUp;
}

/// Full-screen path with the spotlight hole punched out (even-odd fill).
/// Clips both the paint AND the hit-testing of the veil.
class _SpotlightClipper extends CustomClipper<Path> {
  final RRect hole;

  const _SpotlightClipper(this.hole);

  @override
  Path getClip(Size size) => Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(Offset.zero & size)
    ..addRRect(hole);

  @override
  bool shouldReclip(_SpotlightClipper old) => old.hole != hole;
}
