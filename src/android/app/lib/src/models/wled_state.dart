import 'dart:ui' show Color;

/// Parses WLED's own "verbose state" JSON (`wled/balkon/v`, WLED's built-in
/// MQTT status topic — not part of the arbiter contract in
/// `src/shared/README.md`, see `contract/feeds.dart`). Used only for the
/// ambient glow (E9 — implementation-plan.md), so all this needs is a color;
/// everything else in the payload (effects, per-LED state, ...) is ignored.
///
/// Defensive by necessity: WLED omits fields depending on firmware/config
/// (no segments configured, `seg` missing entirely on some builds), and a
/// flaky publish can carry out-of-range ints. Returns `null` whenever the
/// light is off, unset, or the payload doesn't resolve to a usable color —
/// callers treat `null` as "no glow".
Color? parseWledColor(Map<String, dynamic> json) {
  if (json['on'] == false) return null;

  final bri = _clampedInt(json['bri'], fallback: 255);
  if (bri == 0) return null;

  final segments = json['seg'];
  if (segments is! List || segments.isEmpty) return null;
  final segment0 = segments[0];
  if (segment0 is! Map) return null;

  final colors = segment0['col'];
  if (colors is! List || colors.isEmpty) return null;
  final color0 = colors[0];
  if (color0 is! List || color0.length < 3) return null;

  // [r,g,b] or [r,g,b,w] — the trailing white channel isn't representable
  // in an RGB glow tint, so it's ignored rather than folded in.
  final r = _clampedInt(color0[0], fallback: 0);
  final g = _clampedInt(color0[1], fallback: 0);
  final b = _clampedInt(color0[2], fallback: 0);
  if (r == 0 && g == 0 && b == 0) return null; // black/unset reads as "off".

  return Color.fromARGB(255, r, g, b);
}

int _clampedInt(dynamic value, {required int fallback}) {
  if (value is num) return value.round().clamp(0, 255);
  return fallback;
}
