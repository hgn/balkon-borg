import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:balkon_borg/src/contract/topics.dart';
import 'package:balkon_borg/src/models/borg_event.dart';
import 'package:balkon_borg/src/models/health.dart';
import 'package:balkon_borg/src/models/mode_state.dart';

void main() {
  group('ModeState', () {
    test('parses a full payload', () {
      final json = jsonDecode(
        '{"v":1,"submode":"dab","chan":"dlf","pinned":true,'
        '"since":"2026-07-18T21:14:03+02:00"}',
      ) as Map<String, dynamic>;
      final s = ModeState.fromJson(json);
      expect(s.submode, 'dab');
      expect(s.chan, 'dlf');
      expect(s.pinned, isTrue);
      expect(s.since, isNotNull);
      expect(s.isOff, isFalse);
    });

    test('defaults missing fields to off/unpinned', () {
      final s = ModeState.fromJson(const {'v': 1});
      expect(s.submode, 'off');
      expect(s.isOff, isTrue);
      expect(s.pinned, isFalse);
      expect(s.chan, isNull);
    });
  });

  group('CapabilityHealth', () {
    test('parses states and falls back to missing', () {
      expect(
        CapabilityHealth.fromJson(const {'state': 'degraded'}).state,
        HealthState.degraded,
      );
      expect(
        CapabilityHealth.fromJson(const {'state': 'nonsense'}).state,
        HealthState.missing,
      );
    });
  });

  group('BorgEvent', () {
    test('parses a ring entry, unknown category becomes other', () {
      final e = BorgEvent.fromJson(const {
        'ts': '2026-07-18T20:00:00+02:00',
        'category': 'tpms',
        'text': 'car passed',
      });
      expect(e.category, EventCategory.tpms);
      expect(e.text, 'car passed');
      expect(
        BorgEvent.fromJson(const {'category': 'weird'}).category,
        EventCategory.other,
      );
    });
  });

  group('Topics', () {
    test('mode/cmd topics follow the contract', () {
      expect(Topics.mode(MainMode.lumen), 'balkon/mode/lumen');
      expect(Topics.cmdMode(MainMode.sentry), 'balkon/cmd/mode/sentry');
      expect(
        BorgHttp.liveMjpeg('borg-pi').toString(),
        'http://borg-pi:1984/api/stream.mjpeg?src=cam',
      );
    });
  });
}
