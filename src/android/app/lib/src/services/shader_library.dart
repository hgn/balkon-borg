import 'dart:io';
import 'dart:ui' as ui;

/// Compiles and caches the app's fragment-shader programs once at startup
/// (E11, implementation-plan.md D6): the SENTRY detection glitch and the
/// condensation wash. `FragmentProgram.fromAsset` can fail — an old device,
/// an Impeller quirk, and always under `flutter test` (shaders never compile
/// in the test environment) — so every load is wrapped individually. A
/// failure logs to stderr once and leaves that program `null`; callers treat
/// `null` as "render nothing extra", never as an error to retry or surface.
class ShaderLibrary {
  ShaderLibrary._({required this.sentryGlitch, required this.condensation});

  static const sentryGlitchAsset = 'shaders/sentry-glitch.frag';
  static const condensationAsset = 'shaders/condensation.frag';

  final ui.FragmentProgram? sentryGlitch;
  final ui.FragmentProgram? condensation;

  /// An instance with both programs unavailable — the constant fallback for
  /// widget tests and any codepath that must not touch shader compilation.
  static const empty = ShaderLibrary._empty();

  const ShaderLibrary._empty()
      : sentryGlitch = null,
        condensation = null;

  /// Compiles both programs. Call once at startup and hand the result down
  /// via `Provider` — there is no internal cache here, the caller owns the
  /// single instance's lifetime (matches how `Settings`/`AppState` are
  /// constructed once in `main.dart`).
  static Future<ShaderLibrary> load() async => ShaderLibrary._(
        sentryGlitch: await _tryLoad(sentryGlitchAsset),
        condensation: await _tryLoad(condensationAsset),
      );

  static Future<ui.FragmentProgram?> _tryLoad(String asset) async {
    try {
      return await ui.FragmentProgram.fromAsset(asset);
    } catch (e) {
      stderr.writeln('ShaderLibrary: failed to compile $asset: $e');
      return null;
    }
  }
}
