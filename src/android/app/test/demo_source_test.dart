import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:balkon_borg/src/contract/topics.dart';
import 'package:balkon_borg/src/models/borg_event.dart';
import 'package:balkon_borg/src/services/demo_source.dart';
import 'package:balkon_borg/src/services/mqtt_service.dart';
import 'package:balkon_borg/src/state/app_state.dart';
import 'package:balkon_borg/src/state/settings.dart';

void main() {
  group('DemoSource', () {
    test('build() produces a fully populated snapshot', () {
      final snapshot = const DemoSource().build();

      expect(snapshot.modes.keys.toSet(), MainMode.values.toSet());
      expect(snapshot.modes[MainMode.lumen]!.submode, 'info-ticker');
      expect(snapshot.modes[MainMode.comms]!.submode, 'off');
      expect(snapshot.modes[MainMode.sigint]!.submode, 'adsb');
      expect(snapshot.modes[MainMode.sentry]!.submode, 'off');
      expect(snapshot.focus, MainMode.lumen);

      expect(snapshot.health, isNotEmpty);
      expect(
        snapshot.health.keys,
        containsAll(['clock', 'sdr', 'mic', 'speaker', 'camera', 'esp', 'wled']),
      );

      expect(snapshot.events, isNotEmpty);
      expect(snapshot.events.map((e) => e.category), contains(EventCategory.bird));

      expect(snapshot.envHistory, isNotEmpty);
      expect(snapshot.envHistory.length, greaterThan(20));
      for (final sample in snapshot.envHistory) {
        expect(sample.t, greaterThan(-40));
        expect(sample.t, lessThan(60));
      }
    });

    test('populates AppState via connect() when demoMode is on', () async {
      SharedPreferences.setMockInitialValues({'demo_mode': true});
      final settings = await Settings.load();
      final state = AppState(MqttService(), settings);
      addTearDown(state.dispose);

      await state.connect();

      expect(state.connected, isTrue);
      expect(state.modes, isNotEmpty);
      expect(state.focus, MainMode.lumen);
      expect(state.health, isNotEmpty);
      expect(state.recentEvents, isNotEmpty);
      expect(state.envHistory, isNotEmpty);
    });
  });
}
