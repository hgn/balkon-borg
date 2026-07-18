import 'package:flutter/material.dart';

/// Fixed visual heights for the 5 equalizer bars (components.md "Radio
/// Jetzt aktiv-Karte": "unterschiedliche Höhen 14-22px").
const _barHeights = [14.0, 20.0, 22.0, 16.0, 18.0];

/// Radio "Jetzt aktiv" 5-bar equalizer (components.md, motion.md `eqBar`).
/// Bars pulse (`scaleY` .25<->1, 1000ms ease-in-out, staggered 150ms) while
/// [active]; static at full height when not. The controller pauses when
/// inactive so the ambient loop doesn't burn frames while idle.
class EqBars extends StatefulWidget {
  const EqBars({super.key, required this.active});

  final bool active;

  @override
  State<EqBars> createState() => _EqBarsState();
}

class _EqBarsState extends State<EqBars> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  // Built once, not per tick: one staggered CurvedAnimation per bar
  // (Interval start clamped to 1.0 so the stagger never pushes a bar's
  // window past the controller's own range).
  late final List<Animation<double>> _staggered = [
    for (var i = 0; i < _barHeights.length; i++)
      CurvedAnimation(
        parent: _controller,
        curve: Interval((i * 0.15).clamp(0.0, 1.0), 1.0, curve: Curves.easeInOut),
      ),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant EqBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && oldWidget.active) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < _barHeights.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              _bar(scheme.primary, _barHeights[i], _scaleFor(i)),
            ],
          ],
        );
      },
    );
  }

  double _scaleFor(int i) {
    if (!widget.active) return 1.0;
    return 0.25 + 0.75 * _staggered[i].value;
  }

  Widget _bar(Color color, double height, double scaleY) {
    return SizedBox(
      width: 4,
      height: 22, // tallest bar's height, so all bars share a bottom baseline.
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Transform.scale(
          alignment: Alignment.bottomCenter,
          scaleY: scaleY,
          child: Container(
            width: 4,
            height: height,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
        ),
      ),
    );
  }
}
