import 'package:flutter_test/flutter_test.dart';

import 'package:balkon_borg/src/models/borg_event.dart';
import 'package:balkon_borg/src/services/sentry_glitch_trigger.dart';

void main() {
  final now = DateTime(2026, 7, 19, 20, 0);

  BorgEvent at(Duration ago, EventCategory category, [String text = 'x']) =>
      BorgEvent(ts: now.subtract(ago), category: category, text: text);

  group('SentryGlitchTrigger', () {
    test('the first check() establishes a baseline and never fires', () {
      final trigger = SentryGlitchTrigger();
      final ring = [at(const Duration(minutes: 1), EventCategory.security)];

      // Mounting the camera screen with a security event already sitting in
      // history must not itself glitch the view.
      expect(trigger.check(ring), isFalse);
    });

    test('a genuinely new security event after the baseline fires once', () {
      final trigger = SentryGlitchTrigger();
      final baseline = [at(const Duration(minutes: 10), EventCategory.security)];
      trigger.check(baseline);

      final withNewEvent = [at(const Duration(seconds: 5), EventCategory.security), ...baseline];
      expect(trigger.check(withNewEvent), isTrue);

      // The same ring handed in again (e.g. an unrelated AppState rebuild)
      // must not re-fire — nothing new arrived.
      expect(trigger.check(withNewEvent), isFalse);
    });

    test('new events in other categories do not fire the glitch', () {
      final trigger = SentryGlitchTrigger();
      final baseline = [at(const Duration(minutes: 10), EventCategory.bird)];
      trigger.check(baseline);

      final withNewBird = [at(const Duration(seconds: 5), EventCategory.bird), ...baseline];
      expect(trigger.check(withNewBird), isFalse);
    });

    test('a new security event mixed with other new categories still fires', () {
      final trigger = SentryGlitchTrigger();
      trigger.check(const []);

      final ring = [
        at(const Duration(seconds: 1), EventCategory.bird),
        at(const Duration(seconds: 2), EventCategory.security),
      ];
      expect(trigger.check(ring), isTrue);
    });

    test('an empty ring never fires, baseline or not', () {
      final trigger = SentryGlitchTrigger();
      expect(trigger.check(const []), isFalse);
      expect(trigger.check(const []), isFalse);
    });
  });
}
