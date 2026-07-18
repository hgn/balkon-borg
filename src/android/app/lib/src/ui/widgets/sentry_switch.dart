import 'package:flutter/material.dart';

import '../../theme/balkon_theme.dart';

/// SENTRY-card arm/disarm switch (components.md "SENTRY-Karte"): 56×30 pill
/// track, 24×24 white thumb with shadow. Off = `surface` track, armed =
/// `#ff5470` (`extras.danger`) track; thumb slides 300ms spring.
class SentrySwitch extends StatelessWidget {
  const SentrySwitch({super.key, required this.armed, required this.onChanged});

  final bool armed;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final extras = Theme.of(context).extension<BalkonExtras>()!;

    return GestureDetector(
      onTap: () => onChanged(!armed),
      child: AnimatedContainer(
        duration: balkonSpringDuration,
        curve: balkonSpring,
        width: 56,
        height: 30,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: armed ? extras.danger : extras.surface,
          borderRadius: BorderRadius.circular(BalkonRadii.pill),
        ),
        child: AnimatedAlign(
          duration: balkonSpringDuration,
          curve: balkonSpring,
          alignment: armed ? Alignment.centerRight : Alignment.centerLeft,
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
