import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    return Scaffold(
      body: SafeArea(
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
                  // Staggered intervals instead of a plain cross-fade: the
                  // outgoing screen is fully gone within the first ~35% of
                  // the switch, the incoming one only starts after that —
                  // the two screens barely overlap (user feedback: the
                  // 450ms cross-fade showed both too visibly).
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
      onTap: () =>
          settings.setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark),
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
class _HealthDot extends StatelessWidget {
  const _HealthDot();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final color = switch (state.aggregateHealth) {
      AggregateHealth.ok => Colors.green,
      AggregateHealth.degraded => Colors.amber,
      AggregateHealth.bad => scheme.error,
      AggregateHealth.unknown => scheme.outline,
    };
    return GestureDetector(
      onTap: () => showHealthSheet(context, state),
      child: Container(
        width: 12,
        height: 12,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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

  @override
  Widget build(BuildContext context) {
    final extras = Theme.of(context).extension<BalkonExtras>()!;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: extras.surface3,
        borderRadius: BorderRadius.circular(BalkonRadii.bottomNav),
        boxShadow: const [
          BoxShadow(color: Color(0x2E000000), blurRadius: 30, offset: Offset(0, 12)),
        ],
      ),
      child: Row(
        children: [
          for (var i = 0; i < _items.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(child: _NavItem(item: _items[i], active: i == index, onTap: () => onTap(i))),
          ],
        ],
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
      onTap: onTap,
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
