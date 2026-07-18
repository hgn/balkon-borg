import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/borg_event.dart';
import '../state/settings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Broker', style: Theme.of(context).textTheme.titleMedium),
          _TextSetting(
            label: 'Host',
            value: settings.host,
            onSubmitted: (v) => settings.setBroker(host: v),
          ),
          _TextSetting(
            label: 'Port',
            value: '${settings.port}',
            keyboardType: TextInputType.number,
            onSubmitted: (v) =>
                settings.setBroker(port: int.tryParse(v) ?? settings.port),
          ),
          _TextSetting(
            label: 'Username',
            value: settings.username,
            onSubmitted: (v) => settings.setBroker(username: v),
          ),
          _TextSetting(
            label: 'Password',
            value: settings.password,
            obscure: true,
            onSubmitted: (v) => settings.setBroker(password: v),
          ),
          const SizedBox(height: 16),
          Text('Watch window', style: Theme.of(context).textTheme.titleMedium),
          ListTile(
            dense: true,
            title: const Text('Check interval'),
            subtitle: Text(
              'while the ${Settings.watchWindow.inHours} h watch window is armed',
            ),
            trailing: DropdownButton<int>(
              value: settings.checkInterval.inSeconds,
              items: const [
                DropdownMenuItem(value: 10, child: Text('10 s')),
                DropdownMenuItem(value: 30, child: Text('30 s')),
                DropdownMenuItem(value: 60, child: Text('60 s')),
                DropdownMenuItem(value: 120, child: Text('2 min')),
                DropdownMenuItem(value: 300, child: Text('5 min')),
              ],
              onChanged: (v) {
                if (v != null) settings.setCheckInterval(Duration(seconds: v));
              },
            ),
          ),
          const SizedBox(height: 16),
          Text('Notifications', style: Theme.of(context).textTheme.titleMedium),
          for (final c in EventCategory.values)
            if (c != EventCategory.other)
              SwitchListTile(
                dense: true,
                title: Text(c.name),
                value: settings.notify(c),
                onChanged: (on) => settings.setNotify(c, on),
              ),
        ],
      ),
    );
  }
}

class _TextSetting extends StatelessWidget {
  const _TextSetting({
    required this.label,
    required this.value,
    required this.onSubmitted,
    this.keyboardType,
    this.obscure = false,
  });

  final String label;
  final String value;
  final ValueChanged<String> onSubmitted;
  final TextInputType? keyboardType;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextFormField(
        initialValue: value,
        obscureText: obscure,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onFieldSubmitted: onSubmitted,
      ),
    );
  }
}
