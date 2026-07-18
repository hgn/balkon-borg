import 'package:flutter/material.dart';

import 'placeholder_screen.dart';

/// Camera tab placeholder. Full SENTRY card / live view / PTT UI lands in E4
/// (implementation-plan.md).
class CameraScreen extends StatelessWidget {
  const CameraScreen({super.key});

  @override
  Widget build(BuildContext context) => const BorgPlaceholderScreen(label: 'E4 folgt');
}
