import 'package:flutter/material.dart';

import '../../theme/balkon_theme.dart';

/// Push-to-talk button (components.md "Push-to-Talk Button", motion.md
/// `recPulse`, docs/use-cases.md §U21.2). Purely presentational + gesture:
/// idle 92×92 `primary` circle labelled "HALTEN"; while [held], grows to
/// 110×110 (spring), switches to `extras.accent`, labels "AUFNAHME" and
/// shows an expanding/fading ring pulse (1100ms, loops only while held). The
/// caller owns the actual recording start/stop (via the tap callbacks).
class PttButton extends StatefulWidget {
  const PttButton({
    super.key,
    required this.held,
    required this.onTapDown,
    required this.onTapUp,
    required this.onTapCancel,
  });

  final bool held;
  final GestureTapDownCallback onTapDown;
  final GestureTapUpCallback onTapUp;
  final GestureTapCancelCallback onTapCancel;

  @override
  State<PttButton> createState() => _PttButtonState();
}

class _PttButtonState extends State<PttButton> with SingleTickerProviderStateMixin {
  // Built eagerly in initState (not as a lazy `late final` initializer):
  // the ring is only ever read from build() while `widget.held` is true, so
  // a button that's never pressed would otherwise defer construction to
  // dispose() — too late to grab a `vsync` from an already-deactivating
  // element.
  late final AnimationController _ringController;
  late final Animation<double> _ring;

  static const _idleSize = 92.0;
  static const _heldSize = 110.0;
  static const _ringGrowth = 18.0; // motion.md recPulse: "ring 0 -> 18px"

  @override
  void initState() {
    super.initState();
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _ring = CurvedAnimation(parent: _ringController, curve: Curves.easeOut);
    if (widget.held) _ringController.repeat();
  }

  @override
  void didUpdateWidget(covariant PttButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.held && !oldWidget.held) {
      _ringController.repeat();
    } else if (!widget.held && oldWidget.held) {
      _ringController.stop();
      _ringController.value = 0;
    }
  }

  @override
  void dispose() {
    _ringController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extras = Theme.of(context).extension<BalkonExtras>()!;
    final size = widget.held ? _heldSize : _idleSize;

    return GestureDetector(
      onTapDown: widget.onTapDown,
      onTapUp: widget.onTapUp,
      onTapCancel: widget.onTapCancel,
      child: SizedBox(
        width: _heldSize + _ringGrowth * 2,
        height: _heldSize + _ringGrowth * 2,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (widget.held)
              AnimatedBuilder(
                animation: _ring,
                builder: (context, _) {
                  final t = _ring.value;
                  return Container(
                    width: size + t * _ringGrowth * 2,
                    height: size + t * _ringGrowth * 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: extras.accent.withValues(alpha: (1 - t) * 0.6),
                        width: 2,
                      ),
                    ),
                  );
                },
              ),
            AnimatedContainer(
              duration: balkonSpringDuration,
              curve: balkonSpring,
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: widget.held ? extras.accent : scheme.primary,
                shape: BoxShape.circle,
              ),
              child: Text(
                widget.held ? 'AUFNAHME' : 'HALTEN',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 12 * 0.08,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
