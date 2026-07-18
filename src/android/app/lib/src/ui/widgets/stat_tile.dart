import 'package:flutter/material.dart';

import '../../theme/balkon_theme.dart';

/// Home's environment-stat tile (components.md "Umgebungs-Stats"). Press
/// scales down to 0.94 (`statTapScale`, tokens.json) on tap-down, springs
/// back; tap opens the chart sheet (handled by the caller via [onTap]).
class StatTile extends StatefulWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    required this.onTap,
  });

  final String value;
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
      onTap: widget.onTap,
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
              Text(
                widget.value,
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
