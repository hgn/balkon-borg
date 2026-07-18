import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/borg_event.dart';
import '../state/settings.dart';
import '../theme/balkon_theme.dart';
import 'widgets/borg_chip.dart';
import 'widgets/borg_switch.dart';

/// Mirrors pubspec.yaml's `version: 0.1.0+1` (versionName+versionCode).
/// Hardcoded for E6 rather than pulling in a `package_info_plus` runtime
/// dependency just for this; revisit if the app ever needs to read its own
/// version back (e.g. to compare against the borg-pi's `/apk/version.json`).
const _appVersionName = '0.1.0';
const _appVersionCode = 1;

const _intervalOptions = [
  (seconds: 10, label: '10s'),
  (seconds: 30, label: '30s'),
  (seconds: 60, label: '60s'),
  (seconds: 120, label: '2 min'),
  (seconds: 300, label: '5 min'),
];

const _notifyCategories = [
  (category: EventCategory.security, label: 'Sicherheit (SENTRY)'),
  (category: EventCategory.bird, label: 'Vögel'),
  (category: EventCategory.aircraft, label: 'Flugzeuge (Tiefflug)'),
  (category: EventCategory.storm, label: 'Sturm (Luftdruck)'),
  (category: EventCategory.tpms, label: 'Reifensensoren'),
];

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 40),
        children: [
          _SettingsSection(
            title: 'ALLGEMEIN',
            children: [
              _SwitchRow(
                label: 'Demo-Modus',
                subtitle: 'Beispieldaten statt echtem Broker',
                value: settings.demoMode,
                onChanged: settings.setDemoMode,
              ),
              _SwitchRow(
                label: 'Haptik',
                subtitle: 'Vibration bei Auswahl, Zustandswechseln, PTT',
                value: settings.hapticsEnabled,
                onChanged: settings.setHapticsEnabled,
              ),
              _BrokerField(
                label: 'Name',
                subtitle: 'für die Begrüßung (optional)',
                value: settings.displayName,
                onSubmitted: settings.setDisplayName,
              ),
            ],
          ),
          const SizedBox(height: 22), // tokens.json spacing.sectionGap
          _SettingsSection(
            title: 'BROKER',
            children: [
              _BrokerField(
                label: 'Host',
                value: settings.host,
                onSubmitted: (v) => settings.setBroker(host: v),
              ),
              _BrokerField(
                label: 'Port',
                value: '${settings.port}',
                keyboardType: TextInputType.number,
                onSubmitted: (v) =>
                    settings.setBroker(port: int.tryParse(v) ?? settings.port),
              ),
              _BrokerField(
                label: 'Benutzername',
                value: settings.username,
                onSubmitted: (v) => settings.setBroker(username: v),
              ),
              _BrokerField(
                label: 'Passwort',
                value: settings.password,
                obscure: true,
                onSubmitted: (v) => settings.setBroker(password: v),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _SettingsSection(
            title: 'WATCH-WINDOW',
            children: [
              _CardLabel(
                label: 'Prüfintervall',
                subtitle: 'wie oft während des ${Settings.watchWindow.inHours} h Watch-Windows geprüft wird',
              ),
              _IntervalChips(settings: settings),
              _InfoRow(label: 'Watch-Window', value: _watchWindowStatus(settings)),
            ],
          ),
          const SizedBox(height: 22),
          _SettingsSection(
            title: 'BENACHRICHTIGUNGEN',
            children: [
              for (final c in _notifyCategories)
                _SwitchRow(
                  label: c.label,
                  value: settings.notify(c.category),
                  onChanged: (on) => settings.setNotify(c.category, on),
                ),
            ],
          ),
          const SizedBox(height: 22),
          _SettingsSection(
            title: 'APP',
            children: [
              _InfoRow(label: 'Version', value: '$_appVersionName ($_appVersionCode)'),
              const _AppHint('APK-Quelle: borg-pi/apk'),
            ],
          ),
        ],
      ),
    );
  }

  String _watchWindowStatus(Settings settings) {
    if (settings.demoMode) return 'Demo-Modus — kein Watch-Window';
    final until = settings.watchWindowArmedUntil;
    if (until == null || !until.isAfter(DateTime.now())) return 'inaktiv';
    return 'aktiv bis ${_hhmm(until)}';
  }
}

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Section eyebrow (11/700, uppercase, `textDim` — components.md eyebrow
/// style) above a `surface2` card holding the section's rows, divided by
/// thin `border` lines (same treatment as the log rows / health-sheet rows).
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final extras = Theme.of(context).extension<BalkonExtras>()!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: textTheme.labelLarge?.copyWith(color: extras.textDim)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: extras.surface2,
            border: Border.all(color: scheme.outline),
            borderRadius: BorderRadius.circular(BalkonRadii.statTile),
          ),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1) Divider(height: 1, color: scheme.outline),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A plain label + optional dim subtitle, used above the interval chips
/// (which aren't themselves a switch/text row).
class _CardLabel extends StatelessWidget {
  const _CardLabel({required this.label, this.subtitle});

  final String label;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final extras = Theme.of(context).extension<BalkonExtras>()!;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: textTheme.bodyLarge),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: textTheme.bodySmall?.copyWith(color: extras.textDim)),
          ],
        ],
      ),
    );
  }
}

/// Label + trailing dim value, one line (watch-window status, app version).
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final extras = Theme.of(context).extension<BalkonExtras>()!;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Text(label, style: textTheme.bodyLarge)),
          Text(value, style: textTheme.bodyMedium?.copyWith(color: extras.textDim)),
        ],
      ),
    );
  }
}

/// Dim single-line hint (components.md doesn't spec this — reuses the same
/// `bodySmall`/`textDim` treatment as detail lines elsewhere, e.g. log rows).
class _AppHint extends StatelessWidget {
  const _AppHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final extras = Theme.of(context).extension<BalkonExtras>()!;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text, style: textTheme.bodySmall?.copyWith(color: extras.textDim)),
    );
  }
}

/// Toggle row: label (+ optional dim subtitle) on the left, [BorgSwitch] on
/// the right (components.md pill-switch treatment, generalized).
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final extras = Theme.of(context).extension<BalkonExtras>()!;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: textTheme.bodyLarge),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: textTheme.bodySmall?.copyWith(color: extras.textDim)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          BorgSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Check-interval picker as chips (replaces the E1 dropdown — components.md
/// "Chips" treatment, primary color when selected).
class _IntervalChips extends StatelessWidget {
  const _IntervalChips({required this.settings});

  final Settings settings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = settings.checkInterval.inSeconds;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Wrap(
        spacing: 8, // tokens.json spacing.chipGap
        runSpacing: 8,
        children: [
          for (final o in _intervalOptions)
            BorgChip(
              label: o.label,
              selected: current == o.seconds,
              selectedBackground: scheme.primary,
              selectedForeground: Colors.white,
              onTap: () => settings.setCheckInterval(Duration(seconds: o.seconds)),
            ),
        ],
      ),
    );
  }
}

/// Broker text field, restyled onto `surface` (one step below the `surface2`
/// section card) with the design's radii instead of the default M3 outline.
/// Also reused for the ALLGEMEIN "Name" row (optional [subtitle], dim, same
/// treatment as `_SwitchRow`'s subtitle line).
class _BrokerField extends StatelessWidget {
  const _BrokerField({
    required this.label,
    required this.value,
    required this.onSubmitted,
    this.keyboardType,
    this.obscure = false,
    this.subtitle,
  });

  final String label;
  final String value;
  final ValueChanged<String> onSubmitted;
  final TextInputType? keyboardType;
  final bool obscure;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final extras = Theme.of(context).extension<BalkonExtras>()!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(BalkonRadii.chip),
      borderSide: BorderSide(color: scheme.outline),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: textTheme.bodySmall?.copyWith(color: extras.textDim)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: textTheme.bodySmall?.copyWith(color: extras.textDim)),
          ],
          const SizedBox(height: 6),
          TextFormField(
            initialValue: value,
            obscureText: obscure,
            keyboardType: keyboardType,
            style: textTheme.bodyLarge,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: extras.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: border,
              enabledBorder: border,
              focusedBorder: border.copyWith(borderSide: BorderSide(color: scheme.primary)),
            ),
            onFieldSubmitted: onSubmitted,
          ),
        ],
      ),
    );
  }
}
