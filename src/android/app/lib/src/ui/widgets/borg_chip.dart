import 'package:flutter/material.dart';

import '../../theme/balkon_theme.dart';

/// Selectable chip (components.md "Chips" — COMMS band / SIGINT function).
/// Prop-driven, no Provider coupling: caller decides selection state and the
/// selected colors (COMMS uses `cyan`, SIGINT uses `primary`), matching the
/// per-context color rule in the spec.
class BorgChip extends StatelessWidget {
  const BorgChip({
    super.key,
    required this.label,
    required this.selected,
    required this.selectedBackground,
    required this.selectedForeground,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color selectedBackground;
  final Color selectedForeground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extras = Theme.of(context).extension<BalkonExtras>()!;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: balkonSpringDuration,
        curve: balkonSpring,
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? selectedBackground : extras.surface2,
          borderRadius: BorderRadius.circular(BalkonRadii.chip),
          border: selected ? null : Border.all(color: scheme.outline),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? selectedForeground : extras.textDim,
          ),
        ),
      ),
    );
  }
}
