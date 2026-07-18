import 'package:flutter/material.dart';

/// Small reusable widget that turns a numeric value's on-screen transitions
/// into a tween instead of a jump (E8, implementation-plan.md): the three
/// home-screen stat tiles and the chart sheet's big value both flip through
/// intermediate readings over ~400ms rather than snapping straight to a new
/// number.
///
/// Formatting stays entirely the caller's: [format] receives the *animated*
/// double every frame and decides decimals/unit exactly as before — this
/// widget only interpolates the raw number feeding it. The text style is
/// likewise untouched, passed straight through to the underlying `Text`.
class AnimatedValue extends StatelessWidget {
  const AnimatedValue({
    super.key,
    required this.value,
    required this.format,
    this.style,
    this.textAlign,
    this.duration = const Duration(milliseconds: 400),
  });

  final double value;
  final String Function(double value) format;
  final TextStyle? style;
  final TextAlign? textAlign;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      // `begin` only ever matters for this widget's very first build (no
      // animate-in-from-nothing on initial data load) — `TweenAnimationBuilder`
      // ignores it on every later rebuild and re-anchors to whatever value is
      // currently on screen, so a changing `value` always animates smoothly
      // from the last shown number to the new one, never jumps.
      tween: Tween<double>(begin: value, end: value),
      duration: duration,
      curve: Curves.easeOut,
      builder: (context, animatedValue, _) => Text(
        format(animatedValue),
        style: style,
        textAlign: textAlign,
      ),
    );
  }
}
