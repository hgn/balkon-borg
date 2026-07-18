import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/bird_detection.dart';
import '../state/app_state.dart';
import '../theme/balkon_theme.dart';

/// Log tab (components.md "Vogel-Log", E5 — implementation-plan.md):
/// "Vogel des Tages" header followed by the full bird-detection log,
/// newest first.
class LogScreen extends StatelessWidget {
  const LogScreen({super.key});

  // tokens.json radius.birdInitial is 12, close to but distinct from
  // BalkonRadii.badge (13, a different component's token) — a local literal
  // is correct here rather than reusing badge.
  static const _birdInitialRadius = 12.0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final textTheme = Theme.of(context).textTheme;
    final extras = Theme.of(context).extension<BalkonExtras>()!;

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        _BirdOfDayHeader(birdOfDay: state.birdOfDay),
        const SizedBox(height: 22), // tokens.json spacing.sectionGap
        if (state.birdLog.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Text(
              'Noch keine Vogel-Erkennungen',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: extras.textDim),
            ),
          )
        else
          for (final entry in state.birdLog) _LogRow(entry: entry),
      ],
    );
  }
}

/// "Vogel des Tages" header (components.md): species title 30px/800, a
/// dimmer "zuletzt HH:MM · N× heute" line below. Reduced to just the eyebrow
/// + a hint when nothing was detected today yet.
class _BirdOfDayHeader extends StatelessWidget {
  const _BirdOfDayHeader({required this.birdOfDay});

  final BirdOfDay? birdOfDay;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final extras = Theme.of(context).extension<BalkonExtras>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'VOGEL DES TAGES',
          style: textTheme.labelLarge?.copyWith(color: extras.textDim),
        ),
        const SizedBox(height: 6),
        if (birdOfDay == null)
          Text(
            'noch keine Erkennung heute',
            style: textTheme.bodyMedium?.copyWith(color: extras.textDim),
          )
        else ...[
          Text(birdOfDay!.species, style: textTheme.headlineLarge),
          const SizedBox(height: 4),
          Text(
            'zuletzt ${_formatTime(birdOfDay!.lastSeen)} · ${birdOfDay!.count}× heute',
            style: textTheme.bodyMedium?.copyWith(color: extras.textDim),
          ),
        ],
      ],
    );
  }
}

/// One log row (components.md "Vogel-Log" row spec): initial badge, species
/// name, detail line (scientific name / confidence), right-aligned time,
/// bottom divider.
class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final BirdDetection entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final extras = Theme.of(context).extension<BalkonExtras>()!;
    final detail = _detailLine(entry);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outline)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: extras.surface2,
              borderRadius: BorderRadius.circular(LogScreen._birdInitialRadius),
            ),
            child: Text(
              entry.species.isEmpty ? '?' : entry.species[0].toUpperCase(),
              style: balkonMonoStyle(context, 17, FontWeight.w700, color: scheme.primary),
            ),
          ),
          const SizedBox(width: 14), // tokens.json spacing.cardGap
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.species.isEmpty ? 'Unbekannt' : entry.species,
                  style: textTheme.bodyLarge,
                ),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(detail, style: textTheme.bodySmall?.copyWith(color: extras.textDim)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatLogTime(entry.ts),
            style: balkonMonoStyle(context, 12, FontWeight.w600, color: extras.textDim),
          ),
        ],
      ),
    );
  }

  String? _detailLine(BirdDetection entry) {
    final parts = <String>[
      if (entry.scientific != null) entry.scientific!,
      if (entry.confidence != null) '${(entry.confidence! * 100).round()}%',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

String _twoDigits(int n) => n.toString().padLeft(2, '0');

String _formatTime(DateTime ts) => '${_twoDigits(ts.hour)}:${_twoDigits(ts.minute)}';

/// `HH:MM` for today's entries, `dd.MM.` otherwise (components.md doesn't
/// spell this out; a short date reads better than a stale-looking clock time
/// for older rows).
String _formatLogTime(DateTime ts) {
  final now = DateTime.now();
  final sameDay = ts.year == now.year && ts.month == now.month && ts.day == now.day;
  return sameDay ? _formatTime(ts) : '${_twoDigits(ts.day)}.${_twoDigits(ts.month)}.';
}
