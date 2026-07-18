import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../contract/stations.dart';
import '../contract/submodes.dart';
import '../contract/topics.dart';
import '../models/mode_state.dart';
import '../state/app_state.dart';
import '../theme/balkon_theme.dart';
import 'widgets/borg_chip.dart';
import 'widgets/eq_bars.dart';
import 'widgets/preset_row.dart';

/// Dark contrast text on `cyan` backgrounds (DAB+ chip/preset selection,
/// components.md "Preset-Listen": "DAB+ ausgewählt: Background cyan, Text
/// dunkel (#06232a)").
const _cyanContrastText = Color(0xFF06232A);

/// Which segment of the COMMS/SIGINT tab is currently viewed. Purely local
/// screen state — not a mode selection, just which content block shows.
enum _Segment { comms, sigint }

/// Radio tab (components.md "Segmented Tab", "Radio Jetzt aktiv-Karte",
/// "Chips", "Preset-Listen"; docs/use-cases.md §U10). Segmented COMMS/SIGINT
/// view; each segment has its own band/function chips + detail below. Both
/// COMMS and SIGINT share one tuner in the real system (architecture.md
/// §3/§4), so activating one while the other is non-off displaces it — see
/// [_activateWithDisplacement].
class RadioScreen extends StatefulWidget {
  const RadioScreen({super.key});

  @override
  State<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends State<RadioScreen> {
  _Segment _segment = _Segment.comms;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final viewedMode = _segment == _Segment.comms ? MainMode.comms : MainMode.sigint;
    final viewedState = state.modes[viewedMode] ?? const ModeState(submode: 'off');
    final commsState = state.modes[MainMode.comms] ?? const ModeState(submode: 'off');
    final sigintState = state.modes[MainMode.sigint] ?? const ModeState(submode: 'off');

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        _SegmentedTab(segment: _segment, onChanged: (s) => setState(() => _segment = s)),
        const SizedBox(height: 18),
        _ActiveCard(mode: viewedMode, state: viewedState),
        const SizedBox(height: 22),
        if (_segment == _Segment.comms)
          _CommsBlock(commsState: commsState)
        else
          _SigintBlock(sigintState: sigintState),
      ],
    );
  }
}

/// Segmented Tab (components.md): `surface` track, two equal-width segments.
class _SegmentedTab extends StatelessWidget {
  const _SegmentedTab({required this.segment, required this.onChanged});

  final _Segment segment;
  final ValueChanged<_Segment> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extras = Theme.of(context).extension<BalkonExtras>()!;

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: extras.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outline),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegmentItem(
              label: 'COMMS',
              active: segment == _Segment.comms,
              onTap: () => onChanged(_Segment.comms),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _SegmentItem(
              label: 'SIGINT',
              active: segment == _Segment.sigint,
              onTap: () => onChanged(_Segment.sigint),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentItem extends StatelessWidget {
  const _SegmentItem({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extras = Theme.of(context).extension<BalkonExtras>()!;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: balkonSpringDuration,
        curve: balkonSpring,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? extras.surface3 : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 12 * 0.05,
              color: active ? scheme.onSurface : extras.textDim,
            ),
          ),
        ),
      ),
    );
  }
}

/// "Jetzt aktiv" card (components.md): shows the viewed segment's current
/// submode + channel, plus the ambient equalizer while it is non-off. While
/// receiving, a faint animated layer lives behind the content (E9 —
/// implementation-plan.md): a radar sweep for SIGINT, a scrolling sine wave
/// for COMMS.
class _ActiveCard extends StatelessWidget {
  const _ActiveCard({required this.mode, required this.state});

  final MainMode mode;
  final ModeState state;

  static const _radius = 24.0;

  @override
  Widget build(BuildContext context) {
    final extras = Theme.of(context).extension<BalkonExtras>()!;
    final textTheme = Theme.of(context).textTheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(_radius),
      child: ColoredBox(
        color: extras.surface2,
        child: Stack(
          children: [
            _ActiveCardBackground(mode: mode, state: state),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('JETZT AKTIV', style: textTheme.labelLarge?.copyWith(color: extras.textDim)),
                        const SizedBox(height: 4),
                        Text(_label(), style: textTheme.titleLarge),
                      ],
                    ),
                  ),
                  EqBars(active: !state.isOff),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _label() {
    if (mode == MainMode.comms) {
      if (state.isOff) return 'COMMS · Aus';
      final bandLabel = Submodes.labelFor(MainMode.comms, state.submode);
      final chan = state.chan;
      final chanLabel = (chan != null ? Stations.byId(chan)?.name : null) ?? chan ?? bandLabel;
      return '$bandLabel · $chanLabel';
    }
    if (state.isOff) return 'SIGINT · Aus';
    return 'SIGINT · ${Submodes.labelFor(MainMode.sigint, state.submode)}';
  }
}

/// Ambient background layer behind the "Jetzt aktiv" card content (E9):
/// a rotating radar sweep while SIGINT is receiving, a scrolling sine wave
/// while COMMS is receiving, nothing while off. The controller only runs
/// while one of the two is active, and only exists while `_ActiveCard` (and
/// therefore this widget) is actually built — the Radio tab's content is
/// swapped out of the tree entirely when another tab is shown
/// (`shell.dart`'s `AnimatedSwitcher`+`KeyedSubtree`), so there's nothing
/// left ticking in the background once the user navigates away.
class _ActiveCardBackground extends StatefulWidget {
  const _ActiveCardBackground({required this.mode, required this.state});

  final MainMode mode;
  final ModeState state;

  @override
  State<_ActiveCardBackground> createState() => _ActiveCardBackgroundState();
}

class _ActiveCardBackgroundState extends State<_ActiveCardBackground>
    with SingleTickerProviderStateMixin {
  // Radar completes one revolution every 4s (task spec). The sine wave
  // shares the same controller — its phase advances at a fraction of the
  // radar's angular speed so it reads as "slowly scrolling", not spinning.
  static const _revolution = Duration(seconds: 4);
  static const _waveSpeedFraction = 0.35;

  late final AnimationController _controller =
      AnimationController(vsync: this, duration: _revolution);
  bool _reduceMotion = false;

  bool get _sweepActive => widget.mode == MainMode.sigint && !widget.state.isOff;
  bool get _waveActive => widget.mode == MainMode.comms && !widget.state.isOff;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.of(context).disableAnimations;
    _sync();
  }

  @override
  void didUpdateWidget(covariant _ActiveCardBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final shouldRun = (_sweepActive || _waveActive) && !_reduceMotion;
    if (shouldRun && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!shouldRun && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_sweepActive && !_waveActive) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final extras = Theme.of(context).extension<BalkonExtras>()!;

    return Positioned.fill(
      child: RepaintBoundary(
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              return CustomPaint(
                painter: _sweepActive
                    ? _RadarSweepPainter(angle: t * 2 * math.pi, color: scheme.primary)
                    : _SineWavePainter(
                        phase: t * 2 * math.pi * _waveSpeedFraction,
                        primary: scheme.primary,
                        cyan: extras.cyan,
                      ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Soft rotating cone (components.md/E9): a `SweepGradient` circle anchored
/// toward the card's right side, bright near the leading edge and fading
/// into a trail behind it — reads as a slow radar sweep, not a spinner.
class _RadarSweepPainter extends CustomPainter {
  const _RadarSweepPainter({required this.angle, required this.color});

  final double angle;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.82, size.height * 0.5);
    final radius = size.height * 1.6; // large enough to sweep the whole card.
    final rect = Rect.fromCircle(center: center, radius: radius);
    final gradient = SweepGradient(
      transform: GradientRotation(angle),
      colors: [
        color.withValues(alpha: 0.16),
        color.withValues(alpha: 0.0),
        color.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.28, 1.0], // bright leading edge + fading trail.
    );
    canvas.drawCircle(center, radius, Paint()..shader = gradient.createShader(rect));
  }

  @override
  bool shouldRepaint(covariant _RadarSweepPainter oldDelegate) =>
      oldDelegate.angle != angle || oldDelegate.color != color;
}

/// Two overlapping, slowly-scrolling sine curves (components.md/E9), full
/// card width — a subtle stand-in for a live COMMS waveform.
class _SineWavePainter extends CustomPainter {
  const _SineWavePainter({required this.phase, required this.primary, required this.cyan});

  final double phase;
  final Color primary;
  final Color cyan;

  @override
  void paint(Canvas canvas, Size size) {
    _drawWave(
      canvas,
      size,
      phase: phase,
      color: primary.withValues(alpha: 0.14),
      amplitude: size.height * 0.22,
      waveLength: size.width * 0.9,
    );
    _drawWave(
      canvas,
      size,
      phase: phase * 0.7 + math.pi / 3,
      color: cyan.withValues(alpha: 0.14),
      amplitude: size.height * 0.16,
      waveLength: size.width * 0.55,
    );
  }

  void _drawWave(
    Canvas canvas,
    Size size, {
    required double phase,
    required Color color,
    required double amplitude,
    required double waveLength,
  }) {
    final midY = size.height * 0.5;
    final path = Path();
    for (var x = 0.0; x <= size.width; x += 2) {
      final y = midY + amplitude * math.sin((x / waveLength) * 2 * math.pi + phase);
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _SineWavePainter oldDelegate) => oldDelegate.phase != phase;
}

/// COMMS content block: band chips + the selected band's preset list
/// (components.md "Chips", "Preset-Listen"; docs/use-cases.md §U10).
class _CommsBlock extends StatelessWidget {
  const _CommsBlock({required this.commsState});

  final ModeState commsState;

  static const _bands = [
    (id: 'fm', label: 'FM'),
    (id: 'dab', label: 'DAB+'),
    (id: 'shortwave', label: 'Kurzwelle'),
    (id: 'airband', label: 'Flugfunk'),
  ];

  @override
  Widget build(BuildContext context) {
    final extras = Theme.of(context).extension<BalkonExtras>()!;
    final selectedBand = commsState.isOff ? null : commsState.submode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final band in _bands)
              BorgChip(
                label: band.label,
                selected: selectedBand == band.id,
                selectedBackground: extras.cyan,
                selectedForeground: _cyanContrastText,
                onTap: () => _onBandTap(context, band.id),
              ),
          ],
        ),
        const SizedBox(height: 18),
        if (selectedBand != null) _bandBody(context, selectedBand),
      ],
    );
  }

  Widget _bandBody(BuildContext context, String band) {
    final extras = Theme.of(context).extension<BalkonExtras>()!;

    if (band == 'shortwave') {
      return Text(
        'freies Tuning — via Encoder/App später',
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: extras.textDim,
        ),
      );
    }

    final isDab = band == 'dab';
    final selectedBg = isDab ? extras.cyan : Theme.of(context).colorScheme.primary;
    final selectedFg = isDab ? _cyanContrastText : Colors.white;

    return Column(
      children: [
        for (final s in Stations.forBand(band))
          PresetRow(
            name: s.name,
            freq: s.freq,
            selected: commsState.chan == s.id,
            selectedBackground: selectedBg,
            selectedForeground: selectedFg,
            onTap: () => _onPresetTap(context, band, s.id),
          ),
      ],
    );
  }

  void _onBandTap(BuildContext context, String band) {
    if (commsState.submode == band) return; // already active, no-op re-tap.
    _activateWithDisplacement(
      context,
      mode: MainMode.comms,
      submode: band,
      chan: Stations.defaultFor(band),
      other: MainMode.sigint,
    );
  }

  void _onPresetTap(BuildContext context, String band, String stationId) {
    _activateWithDisplacement(
      context,
      mode: MainMode.comms,
      submode: band,
      chan: stationId,
      other: MainMode.sigint,
    );
  }
}

/// SIGINT content block: function chips + a short description of the
/// selected function (docs/use-cases.md §U10).
class _SigintBlock extends StatelessWidget {
  const _SigintBlock({required this.sigintState});

  final ModeState sigintState;

  static const _descriptions = {
    'adsb': 'Flugzeug-Tracking · MUC Anflug',
    'ism': '433/868 MHz Sensoren + TPMS',
    'aprs': 'Ballons · Wanderer · Digipeater',
    'radiosonde': 'DWD Oberschleißheim Verfolgung',
    'spectrum': 'Wasserfall — öffnet OpenWebRX (später)',
    'captures': 'NOAA · ISS SSTV · Meteor-Scatter',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extras = Theme.of(context).extension<BalkonExtras>()!;
    final textTheme = Theme.of(context).textTheme;
    final functions = Submodes.sigint.where((s) => s.id != 'off');
    final selected = sigintState.isOff ? null : sigintState.submode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final fn in functions)
              BorgChip(
                label: fn.label,
                selected: selected == fn.id,
                selectedBackground: scheme.primary,
                selectedForeground: Colors.white,
                onTap: () => _onFunctionTap(context, fn.id),
              ),
          ],
        ),
        if (selected != null) ...[
          const SizedBox(height: 18),
          Text(
            Submodes.labelFor(MainMode.sigint, selected).toUpperCase(),
            style: textTheme.labelLarge?.copyWith(color: extras.textDim),
          ),
          const SizedBox(height: 6),
          Text(_descriptions[selected] ?? '', style: textTheme.bodyMedium),
        ],
      ],
    );
  }

  void _onFunctionTap(BuildContext context, String fn) {
    if (sigintState.submode == fn) return; // already active, no-op re-tap.
    _activateWithDisplacement(context, mode: MainMode.sigint, submode: fn, other: MainMode.comms);
  }
}

/// Shared displacement rule (architecture.md §3/§4: COMMS and SIGINT share
/// one tuner). Activates [mode]/[submode] (+ optional [chan]), and if [other]
/// was genuinely non-off at the moment of the tap, turns it off too and
/// surfaces a brief notice.
void _activateWithDisplacement(
  BuildContext context, {
  required MainMode mode,
  required String submode,
  String? chan,
  required MainMode other,
}) {
  final state = context.read<AppState>();
  final otherState = state.modes[other];
  final displaced = otherState != null && !otherState.isOff;

  state.setSubmode(mode, submode, chan: chan);

  if (displaced) {
    state.setSubmode(other, 'off');
    final extras = Theme.of(context).extension<BalkonExtras>()!;
    final message =
        mode == MainMode.comms ? 'SIGINT pausiert — ein Tuner' : 'COMMS pausiert — ein Tuner';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: extras.surface3,
        duration: const Duration(seconds: 2),
        content: Text(message, style: Theme.of(context).textTheme.bodyLarge),
      ),
    );
  }
}
