import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// NovaPay design-language building blocks: pill buttons, glass cards, stat
/// chips, and the big display headline. All read their colors/type from the
/// centralized [AppColors] / [AppText] tokens — nothing hardcoded here.

/// Fully-rounded button in two variants:
/// - [PillButton] (filled): violet gradient fill with a soft glow.
/// - [PillButton.ghost]: transparent with a thin hairline border.
/// Includes the app's signature 96.5% tactile press-scale.
class PillButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool ghost;
  final double height;

  /// Medium haptic weight for primary/consequential actions.
  final bool mediumHaptic;

  const PillButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 52,
    this.mediumHaptic = false,
  }) : ghost = false;

  const PillButton.ghost({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 52,
    this.mediumHaptic = false,
  }) : ghost = true;

  @override
  State<PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<PillButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final radius = BorderRadius.circular(widget.height / 2);
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: 18,
              color: widget.ghost ? AppColors.textPrimary : Colors.white),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            widget.label,
            overflow: TextOverflow.ellipsis,
            style: AppText.ui(size: 14.5, weight: FontWeight.w800),
          ),
        ),
      ],
    );

    final decoration = widget.ghost
        ? BoxDecoration(
            color: AppColors.glassFill,
            borderRadius: radius,
            border: Border.all(color: AppColors.stroke),
          )
        : BoxDecoration(
            gradient: AppGradients.turn,
            borderRadius: radius,
            boxShadow: enabled
                ? AppShadows.glow(AppColors.primaryViolet, alpha: .4, blur: 20)
                : null,
          );

    return Listener(
      onPointerDown: enabled
          ? (_) {
              setState(() => _pressed = true);
              widget.mediumHaptic
                  ? HapticFeedback.mediumImpact()
                  : HapticFeedback.lightImpact();
            }
          : null,
      onPointerUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onPointerCancel:
          enabled ? (_) => setState(() => _pressed = false) : null,
      child: AnimatedScale(
        scale: _pressed ? .955 : 1.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack, // springy pop on release
        child: AnimatedOpacity(
          opacity: enabled ? 1 : .45,
          duration: const Duration(milliseconds: 200),
          child: Container(
            height: widget.height,
            decoration: decoration,
            clipBehavior: Clip.antiAlias,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onPressed,
                borderRadius: radius,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Center(child: content),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Translucent violet glass panel — the NovaPay surface.
///
/// PERFORMANCE CONTRACT (perf beats aesthetics, always):
///
/// - **Opaque dark base, painted first.** The card is dark violet from its
///   very first frame — never white, never an uninitialized canvas, not
///   while a shader is still compiling and not mid page-transition.
/// - **No `BackdropFilter` by default** (`blur: 0`). A real backdrop blur
///   costs a `saveLayer` over its bounds on *every* frame it is on screen,
///   which is what stalled entry into the setup screen. Over this app's
///   near-uniform dark background a blur is visually a no-op, so the default
///   is a static translucent gradient: identical look, zero GPU cost. Pass
///   `blur > 0` only for a small card floating over genuinely busy content.
/// - **The entrance sheen is opt-in** (`sheen: true`). It needs a
///   `ShaderMask`, i.e. a second `saveLayer` nested inside the first — the
///   classic first-frame jank on a large card.
/// - **The whole card is a `RepaintBoundary`**, so it rasterizes once and is
///   only re-composited while a route transition animates it.
class GlassCard extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  /// Backdrop-blur sigma. `0` (default) skips [BackdropFilter] entirely.
  /// Clamped to [maxBlurSigma] — blur cost grows with sigma, and past ~12
  /// the result is indistinguishable on a dark, low-contrast backdrop.
  final double blur;

  /// One-shot diagonal light sweep on mount. Off by default: it costs a
  /// nested `saveLayer` for 1.1s starting on the busiest frame of the
  /// screen's life. Only enable it on small, cheap cards.
  final bool sheen;

  /// Opaque tone the glass is composited over.
  final Color base;

  static const maxBlurSigma = 12.0;

  const GlassCard({
    super.key,
    required this.child,
    this.radius = 22,
    this.blur = 0,
    this.padding = const EdgeInsets.all(20),
    this.sheen = false,
    this.base = AppColors.surface,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final blurred = blur > 0;

    // On the fast path the base is fully opaque. On the blur path it stays
    // translucent so the backdrop reads through — but it is still
    // dark-violet dominant, so a half-composited frame can never flash light.
    final baseTone = blurred ? base.withValues(alpha: .72) : base;
    final tinted = Color.alphaBlend(AppColors.glassTint, baseTone);

    // ONE gradient does all three jobs (base tone, violet glass tint, faint
    // top highlight) in a single draw with no layer. `color:` is deliberately
    // absent: a BoxDecoration gradient installs a shader that silently
    // overrides `color`, so setting both paints only the gradient — which is
    // exactly how this card used to render a white highlight over nothing.
    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(color: AppColors.stroke),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(Colors.white.withValues(alpha: .05), tinted),
            tinted,
          ],
        ),
      ),
      child: Padding(padding: padding, child: child),
    );

    if (sheen) surface = _EntranceSheen(child: surface);

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: borderRadius,
        // hardEdge on the blur path: an anti-aliased clip around a
        // BackdropFilter widens its repaint bounds. Without the filter the
        // clip is cheap either way, so keep the corners crisp.
        clipBehavior: blurred ? Clip.hardEdge : Clip.antiAlias,
        child: blurred
            ? BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: blur.clamp(0.0, maxBlurSigma),
                  sigmaY: blur.clamp(0.0, maxBlurSigma),
                ),
                child: surface,
              )
            : surface,
      ),
    );
  }
}

/// Opt-in one-shot diagonal light sweep (see [GlassCard.sheen]). Plays once
/// and settles to a `SizedBox.shrink`, so it is pumpAndSettle-safe and costs
/// nothing once finished.
class _EntranceSheen extends StatefulWidget {
  final Widget child;

  const _EntranceSheen({required this.child});

  @override
  State<_EntranceSheen> createState() => _EntranceSheenState();
}

class _EntranceSheenState extends State<_EntranceSheen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sheen = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  @override
  void dispose() {
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _sheen,
              builder: (context, _) {
                if (!_sheen.isAnimating) return const SizedBox.shrink();
                final t = Curves.easeInOut.transform(_sheen.value);
                return ShaderMask(
                  blendMode: BlendMode.srcATop,
                  shaderCallback: (rect) => LinearGradient(
                    begin: Alignment(-1.6 + 3.2 * t, -1),
                    end: Alignment(-1.0 + 3.2 * t, 1),
                    colors: [
                      Colors.white.withValues(alpha: 0),
                      Colors.white.withValues(alpha: .10),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ).createShader(rect),
                  child: const ColoredBox(
                    color: Colors.white,
                    child: SizedBox.expand(),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Small muted pill with an icon + value — for countdowns and stats
/// (e.g. "⏱ 12 min", "30 seconds").
class StatChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color? accent;

  const StatChip({super.key, required this.icon, required this.value, this.accent});

  @override
  Widget build(BuildContext context) {
    final tint = accent ?? AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: tint),
          const SizedBox(width: 6),
          Text(
            value,
            style: AppText.number(
              size: 13,
              weight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Circular NovaPay glass back button: light haptic tick + pop. Hides itself
/// when there is nothing to pop (e.g. widget tests pumping a screen as the
/// root). Direction-aware icon mirrors correctly under RTL.
class GlassBackButton extends StatelessWidget {
  const GlassBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Navigator.of(context).canPop()) return const SizedBox.shrink();
    return Material(
      color: AppColors.glassTint,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.of(context).pop();
        },
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.stroke),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryViolet.withValues(alpha: .18),
                blurRadius: 14,
              ),
            ],
          ),
          child: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 17,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// Text whose glyphs are filled with a [Gradient].
///
/// The one correct way to gradient-fill text in this app — every hero title
/// goes through it so the white-fringe bug can only ever be fixed once.
///
/// Two rules, both about never letting white reach the screen:
///
/// 1. `BlendMode.srcIn`, **not** `ShaderMask`'s default `modulate`. Modulate
///    MULTIPLIES the child's own color into the shader, so the glyph color is
///    part of the result and a white child bleeds through wherever coverage
///    is partial — i.e. along every antialiased edge. `srcIn` discards the
///    child's color entirely and keeps only its alpha coverage, so the output
///    can contain nothing but the gradient's own stops.
/// 2. The child is painted in the gradient's darkest stop rather than
///    `Colors.white`, so there is no white pixel anywhere in the subtree even
///    before the mask is applied.
class GradientText extends StatelessWidget {
  final String text;
  final Gradient gradient;
  final TextStyle style;
  final TextAlign? textAlign;

  const GradientText(
    this.text, {
    super.key,
    required this.gradient,
    required this.style,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (r) => gradient.createShader(r),
      child: Text(
        text,
        textAlign: textAlign,
        style: style.copyWith(color: gradient.colors.last),
      ),
    );
  }
}

/// The big condensed uppercase-feel headline. Optionally fills the glyphs
/// with the pure-violet [AppGradients.wordmark].
class DisplayHeadline extends StatelessWidget {
  final String text;
  final double size;
  final TextAlign align;
  final bool gradient;
  final Color? color;

  const DisplayHeadline(
    this.text, {
    super.key,
    this.size = 48,
    this.align = TextAlign.center,
    this.gradient = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (!gradient) {
      return Text(
        text,
        textAlign: align,
        style: AppText.display(size: size, color: color ?? AppColors.textPrimary),
      );
    }
    return GradientText(
      text,
      gradient: AppGradients.wordmark,
      style: AppText.display(size: size),
      textAlign: align,
    );
  }
}
