import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../contract/submodes.dart';
import '../../contract/topics.dart';
import '../../models/mode_state.dart';
import '../../services/haptics.dart';
import '../../services/ui_sounds.dart';
import '../../theme/balkon_theme.dart';

/// Single-glyph badge per main mode (tokens.json `iconography.modeGlyphs`).
const _glyphs = {
  MainMode.lumen: 'L',
  MainMode.comms: 'C',
  MainMode.sigint: 'Σ',
  MainMode.sentry: '◈',
};

/// Accent color per main mode (tokens.json `color.semantic`).
Color modeAccent(BuildContext context, MainMode m) {
  final scheme = Theme.of(context).colorScheme;
  final extras = Theme.of(context).extension<BalkonExtras>()!;
  return switch (m) {
    MainMode.lumen => extras.accent,
    MainMode.comms => extras.cyan,
    MainMode.sigint => scheme.primary,
    MainMode.sentry => extras.danger,
  };
}

/// Home's 2×2 mode card (components.md "Mode-Card"). Stateful only for the
/// tap-down press-scale; the submode value/typography swap is driven by
/// `state.isOff` from the parent, animated via [AnimatedDefaultTextStyle].
class ModeCard extends StatefulWidget {
  const ModeCard({
    super.key,
    required this.mode,
    required this.state,
    required this.onTap,
  });

  final MainMode mode;
  final ModeState state;
  final VoidCallback onTap;

  @override
  State<ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<ModeCard> {
  bool _pressed = false;

  void _setPressed(bool v) => setState(() => _pressed = v);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extras = Theme.of(context).extension<BalkonExtras>()!;
    final textTheme = Theme.of(context).textTheme;
    final accent = modeAccent(context, widget.mode);
    final active = !widget.state.isOff;
    final armed = widget.mode == MainMode.sentry &&
        Submodes.sentryArmedSubmodes.contains(widget.state.submode);
    final label = Submodes.labelFor(widget.mode, widget.state.submode);

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: () {
        context.read<Haptics>().lightImpact();
        context.read<UiSounds>().blip();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: balkonSpringDuration,
        curve: balkonSpring,
        child: Container(
          constraints: const BoxConstraints(minHeight: 132),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: extras.surface2,
            borderRadius: BorderRadius.circular(BalkonRadii.card),
            border: Border.all(
              color: armed ? extras.danger.withValues(alpha: 0.45) : scheme.outline,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(BalkonRadii.badge),
                ),
                child: Text(
                  _glyphs[widget.mode]!,
                  style: balkonMonoStyle(context, 17, FontWeight.w700).copyWith(color: accent),
                ),
              ),
              const SizedBox(height: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.mode.name.toUpperCase(),
                    style: textTheme.labelLarge?.copyWith(color: extras.textDim),
                  ),
                  const SizedBox(height: 2),
                  AnimatedDefaultTextStyle(
                    duration: balkonSpringDuration,
                    curve: balkonSpring,
                    style: active
                        ? textTheme.titleLarge!
                        : textTheme.titleSmall!.copyWith(color: extras.textDim),
                    child: Text(label),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
