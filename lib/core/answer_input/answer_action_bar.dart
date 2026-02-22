import 'package:flutter/material.dart';

/// Bottom bar wrapper with SafeArea + elevation + AnimatedSwitcher,
/// shared by all answer input screens.
class AnswerActionBar extends StatelessWidget {
  final Widget child;

  const AnswerActionBar({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Material(
        elevation: 6,
        color: theme.colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: child,
          ),
        ),
      ),
    );
  }
}
