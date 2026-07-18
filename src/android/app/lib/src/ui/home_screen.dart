import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../contract/submodes.dart';
import '../contract/topics.dart';
import '../models/env_sample.dart';
import '../models/mode_state.dart';
import '../services/greeting.dart';
import '../services/haptics.dart';
import '../services/ui_sounds.dart';
import '../state/app_state.dart';
import '../state/settings.dart';
import '../theme/balkon_theme.dart';
import 'widgets/animated_value.dart';
import 'widgets/borg_sheet.dart';
import 'widgets/env_chart.dart';
import 'widgets/mode_card.dart';
import 'widgets/stat_tile.dart';

/// Home tab (components.md, E2 — implementation-plan.md): greeting header,
/// 2×2 mode-card grid, environment stats. Health/events moved behind the
/// header status dot / the Log tab (E5); only a slim connection banner
/// remains here, and only while not connected.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final settings = context.watch<Settings>();
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        if (!state.connected) ...[
          const _ConnectionBanner(),
          const SizedBox(height: 16),
        ],
        Text(
          greetingEngine.greet(name: settings.displayName),
          style: textTheme.headlineMedium,
        ),
        const SizedBox(height: 4),
        Text(_statusLine(state, settings), style: textTheme.bodyMedium),
        const SizedBox(height: 22),
        _ModeGrid(state: state),
        const SizedBox(height: 22),
        _EnvStatsRow(history: state.envHistory),
      ],
    );
  }

  String _statusLine(AppState state, Settings settings) {
    if (settings.demoMode) return 'Demo-Modus · Beispieldaten aktiv';
    if (state.connected) return 'Verbunden mit ${settings.host}';
    return 'Nicht verbunden';
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner();

  @override
  Widget build(BuildContext context) {
    final extras = Theme.of(context).extension<BalkonExtras>()!;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: extras.surface2,
        border: Border.all(color: scheme.outline),
        borderRadius: BorderRadius.circular(BalkonRadii.statTile),
      ),
      child: Row(
        children: [
          Icon(Icons.link_off, color: scheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text('not connected', style: Theme.of(context).textTheme.bodyLarge),
          ),
          TextButton(
            onPressed: () => context.read<AppState>().connect(),
            child: const Text('retry'),
          ),
        ],
      ),
    );
  }
}

/// 2×2 grid (components.md "Mode-Card"), fixed order matching `MainMode`
/// (lumen, comms / sigint, sentry).
class _ModeGrid extends StatelessWidget {
  const _ModeGrid({required this.state});

  final AppState state;

  static const _gap = 14.0; // tokens.json spacing.cardGap

  @override
  Widget build(BuildContext context) {
    Widget cardFor(MainMode m) => ModeCard(
          mode: m,
          state: state.modes[m] ?? const ModeState(submode: 'off'),
          onTap: () => showBorgSheet<void>(
            context: context,
            builder: (_) => _SubmodeSheet(mode: m),
          ),
        );

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: cardFor(MainMode.lumen)),
            const SizedBox(width: _gap),
            Expanded(child: cardFor(MainMode.comms)),
          ],
        ),
        const SizedBox(height: _gap),
        Row(
          children: [
            Expanded(child: cardFor(MainMode.sigint)),
            const SizedBox(width: _gap),
            Expanded(child: cardFor(MainMode.sentry)),
          ],
        ),
      ],
    );
  }
}

/// Submode picker sheet (components.md "Bottom Sheet — Submode-Auswahl").
class _SubmodeSheet extends StatelessWidget {
  const _SubmodeSheet({required this.mode});

  final MainMode mode;

  @override
  Widget build(BuildContext context) {
    // components.md: "max-height 70% Screen". LUMEN alone has 10 options, so
    // the row list needs to be able to scroll rather than overflow.
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BorgSheetGrabber(),
            const SizedBox(height: 18),
            BorgSheetHeader(title: mode.name.toUpperCase()),
            const SizedBox(height: 12),
            for (final option in Submodes.forMode(mode)) _SubmodeRow(mode: mode, option: option),
          ],
        ),
      ),
    );
  }
}

class _SubmodeRow extends StatelessWidget {
  const _SubmodeRow({required this.mode, required this.option});

  final MainMode mode;
  final Submode option;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final selected = (state.modes[mode]?.submode ?? 'off') == option.id;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: GestureDetector(
        onTap: () {
          context.read<Haptics>().lightImpact();
          context.read<UiSounds>().blip();
          context.read<AppState>().setSubmode(mode, option.id);
          Navigator.of(context).pop();
        },
        child: AnimatedContainer(
          duration: balkonSpringDuration,
          curve: balkonSpring,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: selected ? scheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            option.label,
            style: textTheme.bodyLarge?.copyWith(
              color: selected ? Colors.white : scheme.onSurface,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// One environment-stat column: display metadata + how to read it out of an
/// [EnvSample]. The single source both the tile row and the chart sheet draw
/// from, so the two stay in lockstep.
class _EnvStatSpec {
  const _EnvStatSpec({
    required this.title,
    required this.unit,
    required this.decimals,
    required this.select,
  });

  final String title;
  final String unit;
  final int decimals;
  final double Function(EnvSample) select;

  String format(double v) => '${v.toStringAsFixed(decimals)}$unit';
}

final _envStats = <_EnvStatSpec>[
  _EnvStatSpec(title: 'Temperatur', unit: '°C', decimals: 1, select: (s) => s.t),
  _EnvStatSpec(title: 'Luftfeuchte', unit: '%', decimals: 0, select: (s) => s.h),
  _EnvStatSpec(title: 'Luftdruck', unit: 'hPa', decimals: 0, select: (s) => s.p),
];

/// 3-column stat row (components.md "Umgebungs-Stats").
class _EnvStatsRow extends StatelessWidget {
  const _EnvStatsRow({required this.history});

  final List<EnvSample> history;

  @override
  Widget build(BuildContext context) {
    final latest = history.isEmpty ? null : history.last;

    return Row(
      children: [
        for (var i = 0; i < _envStats.length; i++) ...[
          if (i > 0) const SizedBox(width: 10), // tokens.json spacing.statGap
          Expanded(
            child: StatTile(
              value: latest == null ? null : _envStats[i].select(latest),
              format: _envStats[i].format,
              label: _envStats[i].title,
              onTap: () => showBorgSheet<void>(
                context: context,
                builder: (_) => _EnvChartSheet(spec: _envStats[i], history: history),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Chart sheet (components.md "Bottom Sheet — Umgebungs-Chart"): eyebrow +
/// big value header, [EnvChart] line chart, min/max/now footer.
class _EnvChartSheet extends StatelessWidget {
  const _EnvChartSheet({required this.spec, required this.history});

  final _EnvStatSpec spec;
  final List<EnvSample> history;

  @override
  Widget build(BuildContext context) {
    final extras = Theme.of(context).extension<BalkonExtras>()!;
    final values = [for (final s in history) spec.select(s)];
    final latest = values.isEmpty ? 0.0 : values.last;
    final minV = values.isEmpty ? 0.0 : values.reduce(math.min);
    final maxV = values.isEmpty ? 0.0 : values.reduce(math.max);
    final footerStyle = TextStyle(
      fontFamily: 'Manrope',
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: extras.textDim,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BorgSheetGrabber(),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${spec.title.toUpperCase()} · 24H VERLAUF',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: extras.textDim),
                ),
              ),
              const BorgSheetCloseButton(),
            ],
          ),
          const SizedBox(height: 6),
          AnimatedValue(
            value: latest,
            format: spec.format,
            style: balkonMonoStyle(context, 26, FontWeight.w700),
          ),
          const SizedBox(height: 18),
          EnvChart(values: values),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('vor 24h', style: footerStyle),
              Text('min ${spec.format(minV)} · max ${spec.format(maxV)}', style: footerStyle),
              Text('jetzt', style: footerStyle),
            ],
          ),
        ],
      ),
    );
  }
}
