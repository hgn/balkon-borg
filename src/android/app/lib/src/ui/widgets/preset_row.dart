import 'package:flutter/material.dart';

import '../../theme/balkon_theme.dart';

/// One row in a COMMS preset list (components.md "Preset-Listen"). Prop-driven,
/// no Provider coupling: caller decides selection state and the selected
/// colors (DAB+ uses cyan/dark text, FM/airband use primary/white, per the
/// per-band rule in the spec).
class PresetRow extends StatelessWidget {
  const PresetRow({
    super.key,
    required this.name,
    required this.freq,
    required this.selected,
    required this.selectedBackground,
    required this.selectedForeground,
    required this.onTap,
  });

  final String name;

  /// Display frequency (e.g. "97.3"); null hides the frequency (DAB+).
  final String? freq;
  final bool selected;
  final Color selectedBackground;
  final Color selectedForeground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extras = Theme.of(context).extension<BalkonExtras>()!;
    final fg = selected ? selectedForeground : scheme.onSurface;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: balkonSpringDuration,
        curve: balkonSpring,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? selectedBackground : extras.surface2,
          borderRadius: BorderRadius.circular(BalkonRadii.chip),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              name,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
            if (freq != null)
              Text(
                freq!,
                style: balkonMonoStyle(context, 13, FontWeight.w600)
                    .copyWith(color: selected ? selectedForeground : extras.textDim),
              ),
          ],
        ),
      ),
    );
  }
}
