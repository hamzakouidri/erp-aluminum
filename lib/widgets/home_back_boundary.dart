import 'package:flutter/material.dart';

/// A standalone workspace page has Home as its fallback parent.
class HomeBackBoundary extends StatelessWidget {
  const HomeBackBoundary({super.key, required this.onBack, required this.label,
    required this.child});
  final VoidCallback onBack;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) onBack();
    },
    child: Column(children: [
      Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(bottom: false, child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: onBack,
            icon: const BackButtonIcon(),
            label: Text(label),
          ),
        )),
      ),
      Expanded(child: child),
    ]),
  );
}
