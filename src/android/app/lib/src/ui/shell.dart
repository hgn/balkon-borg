import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/haptics.dart';
import '../services/ui_sounds.dart';
import '../services/watch_window.dart';
import '../state/app_state.dart';
import '../state/settings.dart';
import '../theme/balkon_theme.dart';
import 'camera_screen.dart';
import 'home_screen.dart';
import 'log_screen.dart';
import 'radio_screen.dart';
import 'settings_screen.dart';
import 'widgets/health_sheet.dart';
import 'widgets/wled_glow.dart';

/// The app shell: header (eyebrow/wordmark/theme toggle/health dot/settings)
/// + floating bottom nav + animated tab content (components.md, motion.md §3).
class BorgShell extends StatefulWidget {
  const BorgShell({super.key});

  @override
  State<BorgShell> createState() => _BorgShellState();
}

class _BorgShellState extends State<BorgShell> with WidgetsBindingObserver {
  int _index = 0;
  static const _watchWindow = WatchWindowService();

  static const _tabs = [
    HomeScreen(),
    CameraScreen(),
    RadioScreen(),
    LogScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _armWatchWindow(); // app start (src/shared/README.md notification model).
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _armWatchWindow(); // app resume.
  }

  /// Fire-and-forget: a no-op in demo mode (no real broker to watch — the
  /// Settings screen's status row is the discoverable hint for that, chosen
  /// over a SnackBar here so the default demo-mode-on first launch doesn't
  /// greet the user with an unsolicited notice).
  void _armWatchWindow() => unawaited(_watchWindow.arm(context.read<Settings>()));

  @override
  Widget build(BuildContext context) {
    final wledColor = context.watch<AppState>().wledColor;
    return Scaffold(
      // The frosted bottom nav (E9) needs scrolling content to actually
      // paint behind it for the BackdropFilter blur to have anything to
      // shimmer — without this, Scaffold insets the body above the nav and
      // there's nothing but flat background color underneath it.
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(child: WledGlow(color: wledColor)),
          ),
          SafeArea(
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(22, 14, 22, 4),
                  child: _BorgHeader(),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: AnimatedSwitcher(
                      duration: balkonScreenEnterDuration,
                      // Staggered intervals instead of a plain cross-fade:
                      // the outgoing screen is fully gone within the first
                      // ~35% of the switch, the incoming one only starts
                      // after that — the two screens barely overlap (user
                      // feedback: the 450ms cross-fade showed both too
                      // visibly).
                      switchInCurve: const Interval(0.35, 1.0, curve: balkonScreenEnterCurve),
                      switchOutCurve: const Interval(0.65, 1.0),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: AnimatedBuilder(
                          animation: animation,
                          // ignore: sort_child_properties_last
                          child: child,
                          builder: (context, child) {
                            final t = animation.value;
                            return Transform.translate(
                              offset: Offset(0, (1 - t) * 10),
                              child: Transform.scale(scale: 0.99 + 0.01 * t, child: child),
                            );
                          },
                        ),
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(_index),
                        child: _tabs[_index],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
        child: SafeArea(
          top: false,
          child: _BorgBottomNav(
            index: _index,
            onTap: (i) => setState(() => _index = i),
          ),
        ),
      ),
    );
  }
}

class _BorgHeader extends StatelessWidget {
  const _BorgHeader();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'BALKON',
                style: balkonMonoStyle(context, 12, FontWeight.w600).copyWith(
                  letterSpacing: 12 * 0.22,
                  color: scheme.primary,
                ),
              ),
              Text('Borg', style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
        ),
        const _ThemeTogglePill(),
        const SizedBox(width: 10),
        const _HealthDot(),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.settings_rounded),
          tooltip: 'Settings',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
          ),
        ),
      ],
    );
  }
}

/// Theme-toggle pill (components.md): 60×32 track, 26×26 thumb, sun/moon
/// glyph, spring-slide between left (light) and right (dark).
class _ThemeTogglePill extends StatelessWidget {
  const _ThemeTogglePill();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final scheme = Theme.of(context).colorScheme;
    final extras = Theme.of(context).extension<BalkonExtras>()!;
    final isDark = settings.themeMode == ThemeMode.dark;

    return GestureDetector(
      onTap: () {
        context.read<Haptics>().lightImpact();
        context.read<UiSounds>().blip();
        settings.setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);
      },
      child: Container(
        width: 60,
        height: 32,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: extras.surface2,
          borderRadius: BorderRadius.circular(16), // tokens.json: themeToggleTrack
          border: Border.all(color: scheme.outline),
        ),
        child: AnimatedAlign(
          duration: balkonSpringDuration,
          curve: balkonSpring,
          alignment: isDark ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
            child: Icon(
              isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              size: 15,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// Aggregate health status dot (D1): green/amber/red, grey while
/// disconnected. Tap opens the health sheet (widgets/health_sheet.dart, E6).
///
/// E8 (implementation-plan.md): while "live" (connected or demo — i.e.
/// anything but the grey/unknown disconnected state), the dot emits a
/// subtle sonar ping every few seconds — an expanding, fading ring in the
/// dot's own color, same ambient-loop family as the live-status/LIVE-camera
/// pulse dots (design/motion.md).
class _HealthDot extends StatefulWidget {
  const _HealthDot();

  @override
  State<_HealthDot> createState() => _HealthDotState();
}

class _HealthDotState extends State<_HealthDot> with SingleTickerProviderStateMixin {
  static const _dotSize = 12.0;
  // "expands to ~2x-2.5x the dot's diameter" (task spec) — 12 * ~2.3.
  static const _pingMaxDiameter = 28.0;
  static const _pingInterval = Duration(seconds: 3);

  late final AnimationController _pingController;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _pingController = AnimationController(vsync: this, duration: _pingInterval);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.of(context).disableAnimations;
  }

  /// Starts/stops the repeating ping to match the current "live" state.
  /// Called from `build()` (not `didUpdateWidget`): the widget's own
  /// constructor never changes, `state.aggregateHealth` does — this keeps
  /// the controller in sync with that Provider-driven value directly.
  void _syncPing(bool live) {
    final shouldRun = live && !_reduceMotion;
    if (shouldRun && !_pingController.isAnimating) {
      _pingController.repeat();
    } else if (!shouldRun && _pingController.isAnimating) {
      _pingController.stop();
    }
  }

  @override
  void dispose() {
    _pingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final health = state.aggregateHealth;
    final color = switch (health) {
      AggregateHealth.ok => Colors.green,
      AggregateHealth.degraded => Colors.amber,
      AggregateHealth.bad => scheme.error,
      AggregateHealth.unknown => scheme.outline,
    };
    // "unknown" is the only grey/disconnected state (AppState.aggregateHealth)
    // — everything else (ok/degraded/bad) implies connected-or-demo.
    final live = health != AggregateHealth.unknown;
    _syncPing(live);

    return GestureDetector(
      onTap: () => showHealthSheet(context, state),
      child: Container(
        width: _dotSize,
        height: _dotSize,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        child: RepaintBoundary(
          child: Stack(
            clipBehavior: Clip.none, // the ping ring paints beyond the 12px dot.
            alignment: Alignment.center,
            children: [
              if (live && !_reduceMotion)
                AnimatedBuilder(
                  key: const ValueKey('health-ping-ring'),
                  animation: _pingController,
                  builder: (context, _) {
                    final t = _pingController.value;
                    final diameter = _dotSize + (_pingMaxDiameter - _dotSize) * t;
                    // Soft edge: a thin stroke starting around 0.5 opacity,
                    // fading to zero as the ring expands.
                    final alpha = (1 - t) * 0.5;
                    return Container(
                      width: diameter,
                      height: diameter,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: color.withValues(alpha: alpha), width: 1.5),
                      ),
                    );
                  },
                ),
              Container(
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Floating bottom nav (components.md): 4 equal-width items, active item
/// gets a primary-color pill background (spring-overshoot fade-in).
class _BorgBottomNav extends StatelessWidget {
  const _BorgBottomNav({required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  static const _items = [
    (icon: Icons.home_rounded, label: 'Home'),
    (icon: Icons.camera_alt_rounded, label: 'Kamera'),
    (icon: Icons.sensors_rounded, label: 'Radio'),
    (icon: Icons.list_alt_rounded, label: 'Log'),
  ];

  // Glassmorphism (E9): surface3 at 0.72 opacity dark / 0.8 light behind a
  // blurred backdrop — 0.72 read fine on the dark theme's near-black
  // background but washed out on the light theme's pale one, so light gets
  // a higher fill to stay legible against whatever scrolls underneath.
  static const _fillOpacityDark = 0.72;
  static const _fillOpacityLight = 0.8;
  static const _blurSigma = 16.0;

  @override
  Widget build(BuildContext context) {
    final extras = Theme.of(context).extension<BalkonExtras>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillOpacity = isDark ? _fillOpacityDark : _fillOpacityLight;

    return Container(
      // Shadow lives on this outer, unclipped box — the blur clip below
      // would otherwise cut it off at the rounded corners.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(BalkonRadii.bottomNav),
        boxShadow: const [
          BoxShadow(color: Color(0x2E000000), blurRadius: 30, offset: Offset(0, 12)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(BalkonRadii.bottomNav),
        // Blur must stay clipped to the nav's own rounded shape — a
        // fullscreen backdrop blur would be both visually wrong (blurring
        // content far outside the nav) and needlessly expensive.
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: _blurSigma, sigmaY: _blurSigma),
          child: Container(
            padding: const EdgeInsets.all(8),
            color: extras.surface3.withValues(alpha: fillOpacity),
            child: Row(
              children: [
                for (var i = 0; i < _items.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(child: _NavItem(item: _items[i], active: i == index, onTap: () => onTap(i))),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.item, required this.active, required this.onTap});

  final ({IconData icon, String label}) item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extras = Theme.of(context).extension<BalkonExtras>()!;
    final fg = active ? Colors.white : extras.textDim;
    return GestureDetector(
      onTap: () {
        context.read<Haptics>().selectionClick();
        context.read<UiSounds>().blip();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: balkonSpringDuration,
        curve: balkonSpring,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(BalkonRadii.navItem),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.icon, size: active ? 19 : 17, color: fg),
            const SizedBox(height: 2),
            Text(
              item.label,
              style: TextStyle(fontFamily: 'Manrope', fontSize: 10, fontWeight: FontWeight.w700, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}
