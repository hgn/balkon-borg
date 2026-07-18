import 'dart:convert';

import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import 'package:balkon_borg/src/models/wled_state.dart';

Map<String, dynamic> _decode(String json) => jsonDecode(json) as Map<String, dynamic>;

void main() {
  group('parseWledColor', () {
    test('parses a plain rgb segment color', () {
      final json = _decode('{"on":true,"bri":128,"seg":[{"col":[[255,80,0]]}]}');
      expect(parseWledColor(json), const Color(0xFFFF5000));
    });

    test('tolerates a 4-channel rgbw color, ignoring the white channel', () {
      final json = _decode('{"on":true,"bri":255,"seg":[{"col":[[10,20,30,255]]}]}');
      expect(parseWledColor(json), const Color(0xFF0A141E));
    });

    test('null when "on" is false, regardless of a set color', () {
      final json = _decode('{"on":false,"bri":128,"seg":[{"col":[[255,0,0]]}]}');
      expect(parseWledColor(json), isNull);
    });

    test('null when brightness is 0', () {
      final json = _decode('{"on":true,"bri":0,"seg":[{"col":[[255,0,0]]}]}');
      expect(parseWledColor(json), isNull);
    });

    test('null when "seg" is missing entirely', () {
      final json = _decode('{"on":true,"bri":128}');
      expect(parseWledColor(json), isNull);
    });

    test('null when "seg" is an empty list', () {
      final json = _decode('{"on":true,"bri":128,"seg":[]}');
      expect(parseWledColor(json), isNull);
    });

    test('null when the first segment has no "col"', () {
      final json = _decode('{"on":true,"bri":128,"seg":[{}]}');
      expect(parseWledColor(json), isNull);
    });

    test('null when the color is black/unset', () {
      final json = _decode('{"on":true,"bri":128,"seg":[{"col":[[0,0,0]]}]}');
      expect(parseWledColor(json), isNull);
    });

    test('missing "on" defaults to considering the light on', () {
      final json = _decode('{"bri":128,"seg":[{"col":[[100,150,200]]}]}');
      expect(parseWledColor(json), const Color(0xFF6496C8));
    });

    test('missing "bri" defaults to full brightness, not off', () {
      final json = _decode('{"on":true,"seg":[{"col":[[100,150,200]]}]}');
      expect(parseWledColor(json), const Color(0xFF6496C8));
    });

    test('clamps out-of-range channel values instead of throwing', () {
      final json = _decode('{"on":true,"bri":128,"seg":[{"col":[[999,-40,255]]}]}');
      expect(parseWledColor(json), const Color(0xFFFF00FF));
    });
  });
}
