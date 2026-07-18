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
/// submode + channel, plus the ambient equalizer while it is non-off.
class _ActiveCard extends StatelessWidget {
  const _ActiveCard({required this.mode, required this.state});

  final MainMode mode;
  final ModeState state;

  @override
  Widget build(BuildContext context) {
    final extras = Theme.of(context).extension<BalkonExtras>()!;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: extras.surface2,
        borderRadius: BorderRadius.circular(24),
      ),
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
