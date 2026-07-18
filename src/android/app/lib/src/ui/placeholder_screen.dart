import 'package:flutter/material.dart';

/// Shared body for tab screens not yet built — a centered eyebrow-style
/// label, styled per the theme so it doesn't look broken, nothing more.
class BorgPlaceholderScreen extends StatelessWidget {
  const BorgPlaceholderScreen({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}
