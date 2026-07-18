import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/balkon_theme.dart';

/// Shared bottom-sheet chrome + motion (components.md "Bottom Sheet —
/// Submode-Auswahl" / "— Umgebungs-Chart", motion.md §2/§4). Every sheet in
/// the app funnels through this so panel styling and the slide-up/backdrop
/// timing stay identical everywhere.
///
/// Implementation note: motion.md sketches a hand-rolled AnimationController
/// for the sheet-enter curve, written before `AnimationStyle` existed as a
/// public API. Flutter (since 3.22) lets `showModalBottomSheet` take a
/// `sheetAnimationStyle` with its own curve, which drives the exact same
/// overshoot transition without a bespoke controller/route — used here
/// instead, it's less code and stays a supported path across Flutter
/// upgrades. The backdrop keeps Flutter's default `Curves.ease` fade
/// (`PopupRoute.barrierCurve`), matching motion.md §4.
///
/// Glassmorphism (E9): the Material itself stays transparent so a
/// `BackdropFilter` blur + a translucent `surface3` fill can shine through
/// instead of a flat panel color, clipped to the same top radius so the
/// blur never bleeds past the sheet's rounded shape. Grabber/header/content
/// (the caller's `builder`) are unchanged — only the backdrop behind them
/// changes.
Future<T?> showBorgSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  final extras = Theme.of(context).extension<BalkonExtras>()!;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  // 0.72 (dark) reads as intended, but on the light theme's pale background
  // it washed out to near-invisible — bumped to 0.8 there to keep the panel
  // legibly distinct from whatever's scrolling behind it.
  final fillOpacity = isDark ? 0.72 : 0.8;
  const topRadius = BorderRadius.vertical(top: Radius.circular(BalkonRadii.sheet));

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x8C05020C), // rgba(5,2,12,.55), components.md
    shape: const RoundedRectangleBorder(borderRadius: topRadius),
    sheetAnimationStyle: const AnimationStyle(
      curve: balkonSheetCurve,
      duration: balkonSheetDuration,
    ),
    builder: (context) => ClipRRect(
      borderRadius: topRadius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          color: extras.surface3.withValues(alpha: fillOpacity),
          child: builder(context),
        ),
      ),
    ),
  );
}

/// Grabber pill at the top of a sheet panel (components.md: 36×4 pill, `border`).
class BorgSheetGrabber extends StatelessWidget {
  const BorgSheetGrabber({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: scheme.outline,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// Round close button (30×30, `surface2`) shared by every sheet header.
class BorgSheetCloseButton extends StatelessWidget {
  const BorgSheetCloseButton({super.key});

  @override
  Widget build(BuildContext context) {
    final extras = Theme.of(context).extension<BalkonExtras>()!;
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: extras.surface2, shape: BoxShape.circle),
        child: Icon(Icons.close_rounded, size: 16, color: scheme.onSurface),
      ),
    );
  }
}

/// Sheet header row: title (18/800) + [BorgSheetCloseButton].
class BorgSheetHeader extends StatelessWidget {
  const BorgSheetHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        const BorgSheetCloseButton(),
      ],
    );
  }
}
