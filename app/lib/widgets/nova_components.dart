import 'dart:ui' as ui;

import 'package:flutter/material.dart';

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

  const PillButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 52,
  }) : ghost = false;

  const PillButton.ghost({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 52,
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
      onPointerDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onPointerUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onPointerCancel:
          enabled ? (_) => setState(() => _pressed = false) : null,
      child: AnimatedScale(
        scale: _pressed ? .965 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
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

/// Translucent violet glass panel with a backdrop blur and a faint top
/// highlight — the NovaPay surface. Thin wrapper over a BackdropFilter so the
/// blur is real (not a fake tint).
class GlassCard extends StatelessWidget {
  final Widget child;
  final double radius;
  final double blur;
  final EdgeInsetsGeometry padding;

  const GlassCard({
    super.key,
    required this.child,
    this.radius = 22,
    this.blur = 20,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: AppColors.glassTint,
            borderRadius: borderRadius,
            border: Border.all(color: AppColors.stroke),
            // Faint top highlight: light catching the upper glass edge.
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: .06),
                Colors.white.withValues(alpha: 0),
              ],
            ),
          ),
          child: child,
        ),
      ),
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

/// The big condensed uppercase-feel headline. Optionally fills the glyphs
/// with a violet gradient (the "ONE GLOBE, ONE FUTURE" look).
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
    final style = AppText.display(
      size: size,
      color: color ?? AppColors.textPrimary,
    );
    final label = Text(text, textAlign: align, style: style);
    if (!gradient) return label;
    return ShaderMask(
      shaderCallback: (r) => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.accentGlow, AppColors.displayViolet],
      ).createShader(r),
      child: Text(
        text,
        textAlign: align,
        style: AppText.display(size: size, color: Colors.white),
      ),
    );
  }
}
