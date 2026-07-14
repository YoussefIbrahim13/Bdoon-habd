import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Frosted-glass panel: blurred backdrop, translucent fill, hairline border.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double radius;
  final double blur;
  final Color? tint;
  final EdgeInsetsGeometry? padding;

  const GlassContainer({
    super.key,
    required this.child,
    this.radius = AppRadii.card,
    this.blur = 18,
    this.tint,
    this.padding,
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
            color: tint ?? AppColors.glassTint,
            borderRadius: borderRadius,
            border: Border.all(color: AppColors.stroke),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Card wrapped in a gradient border with an optional colored glow.
/// Used for the hero flag card and Smart Judge verdict cards.
class GradientBorderCard extends StatelessWidget {
  final Widget child;
  final Gradient gradient;
  final double radius;
  final double borderWidth;
  final Color innerColor;
  final List<BoxShadow>? shadows;
  final EdgeInsetsGeometry? padding;

  const GradientBorderCard({
    super.key,
    required this.child,
    required this.gradient,
    this.radius = AppRadii.card,
    this.borderWidth = 1.8,
    this.innerColor = AppColors.surface,
    this.shadows,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadows,
      ),
      padding: EdgeInsets.all(borderWidth),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: innerColor,
          borderRadius: BorderRadius.circular(radius - borderWidth),
        ),
        child: child,
      ),
    );
  }
}

/// Soft radial color blobs behind every screen — gives the obsidian
/// background depth without competing with content.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: Stack(
        children: [
          Positioned(top: -140, right: -90, child: _Blob(AppColors.electricBlue, 340)),
          Positioned(bottom: -160, left: -110, child: _Blob(AppColors.neonPurple, 400)),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final Color color;
  final double size;

  const _Blob(this.color, this.size);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: .14), Colors.transparent],
        ),
      ),
    );
  }
}
