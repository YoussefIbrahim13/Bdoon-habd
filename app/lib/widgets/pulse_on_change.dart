import 'package:flutter/material.dart';

/// Wraps a widget and briefly scales it up whenever [value] changes.
/// Used to make a score "pop" the instant a point is awarded.
class PulseOnChange extends StatefulWidget {
  final Object value;
  final Widget child;
  final double peakScale;

  const PulseOnChange({
    super.key,
    required this.value,
    required this.child,
    this.peakScale = 1.35,
  });

  @override
  State<PulseOnChange> createState() => _PulseOnChangeState();
}

class _PulseOnChangeState extends State<PulseOnChange>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: widget.peakScale)
          .chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween(begin: widget.peakScale, end: 1.0)
          .chain(CurveTween(curve: Curves.easeInOut)),
      weight: 60,
    ),
  ]).animate(_controller);

  @override
  void didUpdateWidget(PulseOnChange old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _scale, child: widget.child);
}
