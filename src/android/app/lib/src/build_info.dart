/// Build identity, injected by the Makefile at build time (`--dart-define`).
///
/// [revision] is the commit count of the built tree, so a bigger number is
/// unambiguously the newer build — the one thing a version string on a phone
/// has to answer ("is this the one I just installed?"). [commit] and [date]
/// make it traceable back to the tree it came from. Running from the IDE or
/// in tests, none of it is defined and the defaults mark the build as `dev`.
library;

abstract final class BuildInfo {
  static const revision = int.fromEnvironment('BORG_REVISION');
  static const commit = String.fromEnvironment('BORG_COMMIT');
  static const date = String.fromEnvironment('BORG_DATE');

  /// True when the tree had uncommitted changes at build time — a build whose
  /// [commit] does not fully describe what is running on the phone.
  static const dirty = bool.fromEnvironment('BORG_DIRTY');

  static bool get isRelease => revision > 0;

  /// Short form for the settings row: `r412` (`r412+` if dirty), or `dev`.
  static String get version =>
      isRelease ? 'r$revision${dirty ? '+' : ''}' : 'dev';

  /// The traceable part below it: `2026-07-19 · ba74387`.
  static String get origin {
    if (!isRelease) return 'nicht aus einem Build-Lauf';
    final parts = [if (date.isNotEmpty) date, if (commit.isNotEmpty) commit];
    return parts.isEmpty ? 'unbekannt' : parts.join(' · ');
  }
}
