import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/haptics.dart';
import '../../services/ui_sounds.dart';
import '../../theme/balkon_theme.dart';
import 'animated_value.dart';

/// Home's environment-stat tile (components.md "Umgebungs-Stats"). Press
/// scales down to 0.94 (`statTapScale`, tokens.json) on tap-down, springs
/// back; tap opens the chart sheet (handled by the caller via [onTap]).
///
/// [value]/[format] drive an [AnimatedValue] (E8): the reading tweens between
/// samples instead of jumping. `value == null` (no history yet) shows a
/// static "—" instead — there's nothing to animate from.
class StatTile extends StatefulWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.format,
    required this.label,
    required this.onTap,
  });

  final double? value;
  final String Function(double value) format;
  final String label;
  final VoidCallback onTap;

  @override
  State<StatTile> createState() => _StatTileState();
}

class _StatTileState extends State<StatTile> {
  bool _pressed = false;

  void _setPressed(bool v) => setState(() => _pressed = v);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extras = Theme.of(context).extension<BalkonExtras>()!;

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
        scale: _pressed ? 0.94 : 1.0,
        duration: balkonSpringDuration,
        curve: balkonSpring,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: extras.surface,
            border: Border.all(color: scheme.outline),
            borderRadius: BorderRadius.circular(BalkonRadii.statTile),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              widget.value == null
                  ? Text(
                      '—',
                      style: balkonMonoStyle(context, 19, FontWeight.w700),
                      textAlign: TextAlign.center,
                    )
                  : AnimatedValue(
                      value: widget.value!,
                      format: widget.format,
                      style: balkonMonoStyle(context, 19, FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
              const SizedBox(height: 4),
              Text(
                widget.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: extras.textDim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
