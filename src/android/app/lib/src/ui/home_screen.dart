import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../contract/topics.dart';
import '../models/health.dart';
import '../state/app_state.dart';
import '../theme/balkon_theme.dart';

/// Status content for the Home tab. Styling (colors/typography) follows the
/// theme; the 2×2 mode-card / env-stat layout from components.md lands in E2
/// (implementation-plan.md) — this keeps the existing list-based layout.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        _ConnectionBanner(connected: state.connected),
        const SizedBox(height: 20),
        Text('MODES', style: textTheme.labelLarge),
        for (final m in MainMode.values)
          ListTile(
            dense: true,
            leading: Icon(
              state.focus == m ? Icons.radio_button_checked : Icons.radio_button_off,
              color: state.focus == m
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).extension<BalkonExtras>()!.textDim,
            ),
            title: Text(m.name.toUpperCase(), style: textTheme.bodyLarge),
            subtitle: Text(
              [
                state.modes[m]?.submode ?? '—',
                if (state.modes[m]?.chan != null) state.modes[m]!.chan!,
                if (state.modes[m]?.pinned ?? false) '(pinned)',
              ].join(' · '),
              style: textTheme.bodyMedium,
            ),
          ),
        const SizedBox(height: 20),
        Text('HEALTH', style: textTheme.labelLarge),
        if (state.health.isEmpty)
          ListTile(dense: true, title: Text('no health data yet', style: textTheme.bodyMedium)),
        for (final entry in state.health.entries)
          ListTile(
            dense: true,
            leading: Icon(
              switch (entry.value.state) {
                HealthState.ok => Icons.check_circle,
                HealthState.degraded => Icons.warning,
                HealthState.missing => Icons.cancel,
                HealthState.disabled => Icons.do_not_disturb_on,
              },
              color: switch (entry.value.state) {
                HealthState.ok => Colors.green,
                HealthState.degraded => Colors.amber,
                HealthState.missing => Theme.of(context).colorScheme.error,
                HealthState.disabled => Theme.of(context).extension<BalkonExtras>()!.textDim,
              },
            ),
            title: Text(entry.key, style: textTheme.bodyLarge),
            subtitle: entry.value.detail == null
                ? null
                : Text(entry.value.detail!, style: textTheme.bodyMedium),
          ),
        const SizedBox(height: 20),
        Text('EVENTS', style: textTheme.labelLarge),
        if (state.recentEvents.isEmpty)
          ListTile(dense: true, title: Text('no events yet', style: textTheme.bodyMedium)),
        for (final e in state.recentEvents)
          ListTile(
            dense: true,
            title: Text(e.text, style: textTheme.bodyLarge),
            subtitle: Text('${e.category.name} · ${e.ts.toLocal()}', style: textTheme.bodyMedium),
          ),
      ],
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.connected});

  final bool connected;

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
          Icon(
            connected ? Icons.link : Icons.link_off,
            color: connected ? scheme.primary : scheme.error,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              connected ? 'connected' : 'not connected',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          if (!connected)
            TextButton(
              onPressed: () => context.read<AppState>().connect(),
              child: const Text('retry'),
            ),
        ],
      ),
    );
  }
}
