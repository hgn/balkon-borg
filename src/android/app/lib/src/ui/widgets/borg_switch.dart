import 'package:flutter/material.dart';

import '../../theme/balkon_theme.dart';

/// Generic pill switch (components.md "SENTRY-Karte" switch shape, reused
/// wherever a toggle needs the same treatment as Material's default
/// `Switch`/`SwitchListTile` would otherwise provide — settings rows, mainly).
/// [SentrySwitch] stays the SENTRY-specific instance (fixed danger-color
/// track); this is the general one, defaulting to `primary` when on.
class BorgSwitch extends StatelessWidget {
  const BorgSwitch({super.key, required this.value, required this.onChanged, this.activeColor});

  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extras = Theme.of(context).extension<BalkonExtras>()!;
    final trackColor = activeColor ?? scheme.primary;

    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: balkonSpringDuration,
        curve: balkonSpring,
        width: 56,
        height: 30,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? trackColor : extras.surface,
          borderRadius: BorderRadius.circular(BalkonRadii.pill),
        ),
        child: AnimatedAlign(
          duration: balkonSpringDuration,
          curve: balkonSpring,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              // tokens.json elevation.switchThumbShadow: "0 2px 6px rgba(0,0,0,.25)"
              boxShadow: [
                BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
