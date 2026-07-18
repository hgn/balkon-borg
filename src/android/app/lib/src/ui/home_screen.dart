import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../contract/topics.dart';
import '../models/health.dart';
import '../state/app_state.dart';
import 'settings_screen.dart';

/// Skeleton status screen: connection, health, mode states, recent events.
/// Placeholder until the real design (src/android/design/) is applied.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Balkon-Borg'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ConnectionBanner(connected: state.connected),
          const SizedBox(height: 16),
          Text('Modes', style: Theme.of(context).textTheme.titleMedium),
          for (final m in MainMode.values)
            ListTile(
              dense: true,
              leading: Icon(
                state.focus == m
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              title: Text(m.name.toUpperCase()),
              subtitle: Text(
                [
                  state.modes[m]?.submode ?? '—',
                  if (state.modes[m]?.chan != null) state.modes[m]!.chan!,
                  if (state.modes[m]?.pinned ?? false) '(pinned)',
                ].join(' · '),
              ),
            ),
          const SizedBox(height: 16),
          Text('Health', style: Theme.of(context).textTheme.titleMedium),
          if (state.health.isEmpty)
            const ListTile(dense: true, title: Text('no health data yet')),
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
                  HealthState.degraded => Colors.orange,
                  HealthState.missing => Colors.red,
                  HealthState.disabled => Colors.grey,
                },
              ),
              title: Text(entry.key),
              subtitle: entry.value.detail == null
                  ? null
                  : Text(entry.value.detail!),
            ),
          const SizedBox(height: 16),
          Text('Events', style: Theme.of(context).textTheme.titleMedium),
          if (state.recentEvents.isEmpty)
            const ListTile(dense: true, title: Text('no events yet')),
          for (final e in state.recentEvents)
            ListTile(
              dense: true,
              title: Text(e.text),
              subtitle: Text('${e.category.name} · ${e.ts.toLocal()}'),
            ),
        ],
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: connected
          ? Colors.green.withValues(alpha: 0.2)
          : Colors.red.withValues(alpha: 0.2),
      child: ListTile(
        leading: Icon(connected ? Icons.link : Icons.link_off),
        title: Text(connected ? 'connected' : 'not connected'),
        trailing: connected
            ? null
            : TextButton(
                onPressed: () => context.read<AppState>().connect(),
                child: const Text('retry'),
              ),
      ),
    );
  }
}
