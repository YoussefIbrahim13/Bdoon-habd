import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Custom game-control button: gradient or glass fill, colored glow,
/// ink ripple, and a tactile scale-down on press.
///
/// Variants:
///  - `gradient:` filled action (primary game controls)
///  - `borderGradient:` glass fill with a gradient outline (secondary actions)
///  - neither: plain glass button
class GameButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final Widget? leading; // overrides [icon] (e.g. a spinner while loading)
  final VoidCallback? onPressed;
  final Gradient? gradient;
  final Gradient? borderGradient;
  final Color? glowColor;
  final double height;
  final TextStyle? textStyle;

  /// Haptic weight on press: light for navigation/secondary actions (the
  /// default), medium for consequential game actions (verdicts, votes,
  /// submitting a fact).
  final bool mediumHaptic;

  const GameButton({
    super.key,
    required this.label,
    this.icon,
    this.leading,
    this.onPressed,
    this.gradient,
    this.borderGradient,
    this.glowColor,
    this.height = 56,
    this.textStyle,
    this.mediumHaptic = false,
  });

  @override
  State<GameButton> createState() => _GameButtonState();
}

class _GameButtonState extends State<GameButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadii.button);
    final style = widget.textStyle ??
        AppText.ui(size: 16, weight: FontWeight.w700, height: 1.2);

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.leading != null) ...[
          widget.leading!,
          const SizedBox(width: 10),
        ] else if (widget.icon != null) ...[
          Icon(widget.icon, size: 20, color: style.color),
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Text(widget.label, style: style, overflow: TextOverflow.ellipsis),
        ),
      ],
    );

    final fill = widget.gradient != null
        ? BoxDecoration(
            gradient: widget.gradient,
            borderRadius: radius,
            boxShadow: _enabled && widget.glowColor != null
                ? AppShadows.glow(widget.glowColor!)
                : null,
          )
        : BoxDecoration(
            color: AppColors.glassTint,
            borderRadius: radius,
            border:
                widget.borderGradient == null ? Border.all(color: AppColors.stroke) : null,
          );

    Widget button = Container(
      height: widget.height,
      decoration: fill,
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: radius,
          splashColor: Colors.white.withValues(alpha: .12),
          highlightColor: Colors.white.withValues(alpha: .06),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Center(child: content),
          ),
        ),
      ),
    );

    // Gradient outline variant: wrap the glass fill in a 1.5px gradient ring.
    if (widget.gradient == null && widget.borderGradient != null) {
      button = Container(
        decoration: BoxDecoration(
          gradient: widget.borderGradient,
          borderRadius: BorderRadius.circular(AppRadii.button + 1.5),
        ),
        padding: const EdgeInsets.all(1.5),
        child: button,
      );
    }

    return Listener(
      onPointerDown: _enabled
          ? (_) {
              setState(() => _pressed = true);
              // Tactile tick the instant the finger lands (fire-and-forget).
              widget.mediumHaptic
                  ? HapticFeedback.mediumImpact()
                  : HapticFeedback.lightImpact();
            }
          : null,
      onPointerUp: _enabled ? (_) => setState(() => _pressed = false) : null,
      onPointerCancel: _enabled ? (_) => setState(() => _pressed = false) : null,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        // Springy: easeOutBack overshoots slightly on release, so the button
        // "pops" back instead of gliding.
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        child: AnimatedOpacity(
          opacity: _enabled ? 1 : 0.45,
          duration: const Duration(milliseconds: 200),
          child: button,
        ),
      ),
    );
  }
}
