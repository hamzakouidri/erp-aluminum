import 'package:flutter/material.dart';

/// Provides home navigation callback to descendants if needed.
class HomeBackScope extends InheritedWidget {
  final VoidCallback onBack;

  const HomeBackScope({super.key, required this.onBack, required super.child});

  static VoidCallback? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<HomeBackScope>()?.onBack;
  }

  @override
  bool updateShouldNotify(HomeBackScope oldWidget) =>
      onBack != oldWidget.onBack;
}

/// A standalone workspace page has Home as its fallback parent. The button is
/// layered over the page AppBar, so it never reserves horizontal screen space.
class HomeBackBoundary extends StatelessWidget {
  const HomeBackBoundary({
    super.key,
    required this.onBack,
    this.label = '',
    required this.child,
  });

  final VoidCallback onBack;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return HomeBackScope(
      onBack: onBack,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) onBack();
        },
        child: Theme(
          data: Theme.of(context).copyWith(
            appBarTheme: Theme.of(context).appBarTheme.copyWith(
              titleSpacing: 64,
            ),
          ),
          child: Stack(
          children: [
            child,
            SafeArea(
              bottom: false,
              left: false,
              right: false,
              child: Align(
                alignment: AlignmentDirectional.topStart,
                child: SizedBox.square(
                  dimension: kToolbarHeight,
                  child: Material(
                    type: MaterialType.transparency,
                    child: IconButton(
                      icon: const BackButtonIcon(),
                      color: Theme.of(context).appBarTheme.foregroundColor ??
                          Theme.of(context).colorScheme.onPrimary,
                      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                      onPressed: onBack,
                    ),
                  ),
                ),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}
