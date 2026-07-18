import 'package:flutter/material.dart';

/// Soft ambient background glow reflecting WLED's current light color (E9 —
/// implementation-plan.md). Sits behind all Scaffold content
/// (`shell.dart`'s body `Stack`, under `SafeArea`); a very faint radial
/// gradient anchored center-top, fully transparent when [color] is `null`
/// (LUMEN off/unknown). Color and visibility changes morph smoothly via
/// [TweenAnimationBuilder]: [color] `null` maps to fully-transparent black
/// rather than a `null` tween end (`TweenAnimationBuilder` requires a
/// non-null `Tween.end`), so both "the color changed" and "the light turned
/// on/off" are the same alpha-including `Color` lerp, no separate opacity
/// animation needed.
///
/// Never intercepts touches ([IgnorePointer]) and stays faint enough
/// (opacity 0.10 dark / 0.06 light, applied here before the tween so the
/// morph animates the final on-screen alpha) to never impair readability of
/// the content painted on top of it.
class WledGlow extends StatelessWidget {
  const WledGlow({super.key, required this.color});

  final Color? color;

  static const _duration = Duration(milliseconds: 800);
  static const _transparent = Color(0x00000000);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final opacity = isDark ? 0.10 : 0.06;
    final target = color == null ? _transparent : color!.withValues(alpha: opacity);

    return IgnorePointer(
      child: TweenAnimationBuilder<Color>(
        tween: _GlowColorTween(end: target),
        duration: _duration,
        curve: Curves.ease,
        builder: (context, animatedColor, _) {
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.6),
                radius: 1.3,
                colors: [animatedColor, _transparent],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// [ColorTween] is a `Tween<Color?>` (its `lerp` needs to handle a `null`
/// begin/end for the general case); `TweenAnimationBuilder<Color>` needs a
/// non-nullable `Tween<Color>` instead, since [WledGlow] always resolves
/// "no color" to transparent black up front rather than passing `null`
/// through. Thin wrapper reusing `Color.lerp`'s same null-tolerant math.
class _GlowColorTween extends Tween<Color> {
  _GlowColorTween({required Color end}) : super(end: end);

  @override
  Color lerp(double t) => Color.lerp(begin, end, t)!;
}
