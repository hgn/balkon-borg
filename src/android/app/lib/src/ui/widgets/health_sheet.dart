import 'package:flutter/material.dart';

import '../../models/health.dart';
import '../../state/app_state.dart';
import '../../theme/balkon_theme.dart';
import 'borg_sheet.dart';

/// Health bottom sheet (E6, replaces the E1 placeholder): an aggregate
/// summary line under the title, then one row per capability — colored
/// state dot, name (15/700), an optional detail line (12/600 `textDim`),
/// and a right-aligned "seit HH:MM" from [CapabilityHealth.since] when
/// present. Reuses [showBorgSheet] for the shared panel chrome/motion.
void showHealthSheet(BuildContext context, AppState state) {
  showBorgSheet<void>(
    context: context,
    builder: (_) => _HealthSheetContent(state: state),
  );
}

class _HealthSheetContent extends StatelessWidget {
  const _HealthSheetContent({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final extras = Theme.of(context).extension<BalkonExtras>()!;
    final textTheme = Theme.of(context).textTheme;
    final entries = state.health.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BorgSheetGrabber(),
          const SizedBox(height: 18),
          const BorgSheetHeader(title: 'Health'),
          const SizedBox(height: 6),
          Text(_summaryLine(), style: textTheme.bodyMedium?.copyWith(color: extras.textDim)),
          const SizedBox(height: 14),
          if (entries.isEmpty)
            Text(
              'Noch keine Health-Daten',
              style: textTheme.bodyMedium?.copyWith(color: extras.textDim),
            )
          else
            for (final entry in entries) _CapabilityRow(name: entry.key, health: entry.value),
        ],
      ),
    );
  }

  String _summaryLine() {
    if (state.health.isEmpty) return 'Warte auf Health-Daten…';
    if (state.healthSummary.isNotEmpty) return state.healthSummary;
    return switch (state.aggregateHealth) {
      AggregateHealth.ok => 'Alles in Ordnung',
      AggregateHealth.degraded => 'Eingeschränkt',
      AggregateHealth.bad => 'Fehler erkannt',
      AggregateHealth.unknown => 'Unbekannt',
    };
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({required this.name, required this.health});

  final String name;
  final CapabilityHealth health;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extras = Theme.of(context).extension<BalkonExtras>()!;
    final textTheme = Theme.of(context).textTheme;
    final detail = health.detail;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outline))),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: _dotColor(health.state, scheme, extras),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: textTheme.bodyLarge),
                if (detail != null && detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(detail, style: textTheme.bodySmall?.copyWith(color: extras.textDim)),
                ],
              ],
            ),
          ),
          if (health.since != null) ...[
            const SizedBox(width: 8),
            Text(
              'seit ${_formatTime(health.since!)}',
              style: balkonMonoStyle(context, 12, FontWeight.w600, color: extras.textDim),
            ),
          ],
        ],
      ),
    );
  }

  Color _dotColor(HealthState s, ColorScheme scheme, BalkonExtras extras) => switch (s) {
        HealthState.ok => Colors.green,
        HealthState.degraded => Colors.amber,
        HealthState.missing => scheme.error,
        HealthState.disabled => extras.textDim,
      };
}

String _twoDigits(int n) => n.toString().padLeft(2, '0');

String _formatTime(DateTime ts) => '${_twoDigits(ts.hour)}:${_twoDigits(ts.minute)}';
