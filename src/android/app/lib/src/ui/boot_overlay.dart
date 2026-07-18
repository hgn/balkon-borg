import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../services/boot_sound.dart';
import '../theme/balkon_theme.dart';

/// Every boot-animation timing constant, centralized here rather than
/// scattered as magic numbers through the widgets below (E8 —
/// implementation-plan.md). Values are the original E7 "Radar-Welle" timings
/// scaled ~1.5x, taking the whole sequence from ~1.3s to ~2.0s (user-approved
/// polish batch, added 2026-07-17).
class _BootTiming {
  _BootTiming._();

  /// Overall ring/controller duration — drives the wave expansion; the
  /// reveal-band delays below are tuned to land inside it. History: 1300ms
  /// (E7 spec) → 1950ms (E8) → 2950ms → 1950ms (corner-clamp fixed) →
  /// **1450ms** (user, 2026-07-17: effect confirmed good, "500ms schneller").
  /// Everything below scales at ~0.75 of the 1950ms values.
  static const total = Duration(milliseconds: 1450);

  // Reveal bands (header/content/nav uncovering as the wave sweeps past).
  static const headerDelay = Duration(milliseconds: 225);
  static const contentDelay = Duration(milliseconds: 390);
  static const navDelay = Duration(milliseconds: 560);
  static const revealFadeDuration = Duration(milliseconds: 470);

  // Logo fade-in / hold / scale-and-fade-out sequence.
  static const logoFadeIn = Duration(milliseconds: 245);
  static const logoHoldDelay = Duration(milliseconds: 170);
  static const logoScale = Duration(milliseconds: 425);
  static const logoFadeOut = Duration(milliseconds: 425);
}

/// "Radar-Welle" boot animation (E7, implementation-plan.md): on cold start a
/// deep-violet glowing ring expands from a centered logo badge across the
/// whole screen. The shell underneath renders at full opacity from frame
/// one and is revealed in three staggered bands (header, content, nav) as
/// the wave sweeps past, then the whole boot layer unmounts itself — nothing
/// lingers (no controllers, no timers) once it's done.
///
/// Deliberately layered *above* [child] rather than reaching into its
/// internals: the boot effect never depends on the shell's widget structure,
/// so it can't desync from it and touching this file can't regress
/// shell/home widget tests.
class BootOverlay extends StatefulWidget {
  const BootOverlay({super.key, required this.child, this.enabled = true, this.soundPlayer});

  /// Total boot duration, exposed so tests fast-forward past it without
  /// duplicating the number (it has been retuned twice on user feedback).
  static const totalDuration = _BootTiming.total;

  final Widget child;

  /// Widget tests pass `false` to skip the animation deterministically: the
  /// overlay decides in `didChangeDependencies` (before the first frame
  /// paints anything boot-related) and never creates a ticking animation, so
  /// there's nothing left running for `pump()`/`pumpAndSettle()` to race.
  final bool enabled;

  /// Injectable seam for the `start.wav` underscore (E8): widget tests pass a
  /// fake so nothing touches the real `audioplayers` plugin channel. Defaults
  /// to [PackageBootSound] in production; only ever constructed when the
  /// animation actually plays (never on the skip path).
  final BootSound? soundPlayer;

  @override
  State<BootOverlay> createState() => _BootOverlayState();
}

class _BootOverlayState extends State<BootOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _booting = true;
  bool _decided = false;

  /// Only ever set on the "animation actually plays" path — stays `null` on
  /// the skip path (disabled / reduced motion), so no `BootSound`
  /// implementation is even constructed there, let alone played.
  BootSound? _sound;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _BootTiming.total)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _finish();
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    // Reduced-motion (accessibility setting) skips straight to the revealed
    // state, same as tests do via `enabled: false`. No sound on this path.
    if (!widget.enabled || MediaQuery.of(context).disableAnimations) {
      _finish();
    } else {
      _sound = widget.soundPlayer ?? PackageBootSound();
      unawaited(_sound!.play()); // fire-and-forget; play() itself never throws.
      _controller.forward();
    }
  }

  void _finish() {
    if (!mounted || !_booting) return;
    setState(() => _booting = false);
  }

  @override
  void dispose() {
    _controller.dispose();
    unawaited(_sound?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_booting) return widget.child;
    return Stack(
      children: [
        widget.child,
        _RadarWave(controller: _controller),
      ],
    );
  }
}

/// The visual layer: black cover in three reveal bands, the centered logo
/// badge, and the expanding glow ring — all drawn on top of the already-live
/// shell.
class _RadarWave extends StatelessWidget {
  const _RadarWave({required this.controller});

  final AnimationController controller;

  // A radar shockwave travels at constant speed — near-linear expansion
  // (gentle sine easing at the ends only). The earlier strong ease-out
  // (balkonScreenEnterCurve) front-loaded ~80% of the expansion into the
  // first third of the time, which made the 3s wave *feel* sub-second
  // (user feedback 2026-07-17).
  static const _ringCurve = Curves.easeInOutSine;
  static const _ringBaseDiameter = 28.0;
  static const _ringBorderWidth = 3.0;

  // Reveal bands roughly matching shell.dart's header/nav padding; approximate
  // is fine, this is a sub-second flourish, not a layout contract. Timings
  // themselves live in [_BootTiming].
  static const _headerHeight = 92.0;
  static const _navHeight = 116.0;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final diagonal = math.sqrt(size.width * size.width + size.height * size.height);
    final maxDiameter = diagonal * 1.15; // clears the corners at full expansion.

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Black cover, revealed in three staggered strips as the wave
          // passes — "as if the scan just discovered them".
          Column(
            children: [
              SizedBox(
                height: _headerHeight,
                child: _RevealBand(
                  delay: _BootTiming.headerDelay,
                  fadeDuration: _BootTiming.revealFadeDuration,
                ),
              ),
              Expanded(
                child: _RevealBand(
                  delay: _BootTiming.contentDelay,
                  fadeDuration: _BootTiming.revealFadeDuration,
                ),
              ),
              SizedBox(
                height: _navHeight,
                child: _RevealBand(
                  delay: _BootTiming.navDelay,
                  fadeDuration: _BootTiming.revealFadeDuration,
                ),
              ),
            ],
          ),
          const Center(child: _BootLogo()),
          // OverflowBox lifts the parent's BoxConstraints: without it the
          // circle silently clamped at the screen width the moment it hit
          // the side edges and never actually traveled past the corners
          // (user: "der Kreis darf nicht enden, wenn es an die Kanten
          // stößt"). The Stack clips whatever overflows — exactly right.
          Center(
            child: OverflowBox(
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                final t = _ringCurve.transform(controller.value);
                final diameter = _ringBaseDiameter + (maxDiameter - _ringBaseDiameter) * t;
                // Exit choreography (user-tuned 2026-07-18): the ring is at
                // full strength only for the first quarter, then sags
                // noticeably ("ab 1/4 deutlich absacken") — fade exponent 1.5
                // drops it fast early and lets it bleed out toward zero. A
                // narrow gaussian flare at t≈0.85 briefly re-brightens it to
                // full, tinting toward white ("der Aufleuchteffekt ist gut"):
                // an energy discharge right before it dies.
                final p = ((t - 0.25) / 0.75).clamp(0.0, 1.0);
                final baseFade = math.pow(1 - p, 1.5).toDouble();
                final flare = math.exp(-math.pow((t - 0.85) / 0.023, 2)).toDouble();
                final glowAlpha = (baseFade + flare * 0.9).clamp(0.0, 1.0);
                // Blur still ramps over the last quarter only (sigma 0 → 5):
                // the edge hazes out at the end, the flare shines through the
                // haze rather than sharpening it again.
                final blurSigma = ((t - 0.75) / 0.25).clamp(0.0, 1.0) * 5.0;
                final flashColor = Color.lerp(
                  BalkonColors.darkPrimaryStrong,
                  Colors.white,
                  flare * 0.65,
                )!;
                final ring = Container(
                  width: diameter,
                  height: diameter,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: flashColor.withValues(alpha: glowAlpha),
                      width: _ringBorderWidth,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: flashColor.withValues(alpha: glowAlpha * 0.55),
                        blurRadius: 40,
                        spreadRadius: 6,
                      ),
                      BoxShadow(
                        color: BalkonColors.darkPrimary.withValues(alpha: glowAlpha * 0.35),
                        blurRadius: 90,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                );
                if (blurSigma == 0) return ring;
                return ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                  child: ring,
                );
              },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One black strip of the reveal cover: opaque until [delay] elapses, then
/// fades to transparent over [fadeDuration], uncovering the shell below.
class _RevealBand extends StatelessWidget {
  const _RevealBand({required this.delay, required this.fadeDuration});

  final Duration delay;
  final Duration fadeDuration;

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: Colors.black)
        .animate(delay: delay)
        .fadeOut(duration: fadeDuration, curve: Curves.easeOut);
  }
}

/// Stylized stand-in for the app icon (eyebrow "BALKON" + wordmark "Borg",
/// design/tokens.json `brandEyebrow`/`headlineLarge`-ish sizing): fades in on
/// black, then scales up slightly and fades out as the ring sweeps past it.
/// Colors are the fixed dark-theme brand colors, independent of the active
/// theme mode — the boot surface is always black, per spec.
class _BootLogo extends StatelessWidget {
  const _BootLogo();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Text(
          'BALKON',
          style: TextStyle(
            fontFamily: 'SpaceGrotesk',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 12 * 0.22,
            color: BalkonColors.darkPrimary,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Borg',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: BalkonColors.darkText,
          ),
        ),
      ],
    )
        .animate()
        .fadeIn(duration: _BootTiming.logoFadeIn, curve: Curves.easeOut)
        .then(delay: _BootTiming.logoHoldDelay)
        .scale(end: const Offset(1.18, 1.18), duration: _BootTiming.logoScale, curve: Curves.easeOut)
        .fadeOut(duration: _BootTiming.logoFadeOut, curve: Curves.easeOut);
  }
}
