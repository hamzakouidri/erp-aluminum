import 'package:flutter/material.dart';

/// Provides home navigation callback to descendants if needed.
class HomeBackScope extends InheritedWidget {
  final VoidCallback onBack;

  const HomeBackScope({
    super.key,
    required this.onBack,
    required super.child,
  });

  static VoidCallback? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<HomeBackScope>()?.onBack;
  }

  @override
  bool updateShouldNotify(HomeBackScope oldWidget) => onBack != oldWidget.onBack;
}

/// A standalone workspace page has Home as its fallback parent.
/// Places a clean back arrow directly in the page's top title bar
/// without taking any extra vertical space, allowing maximum room for scrolling.
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
        child: Stack(
          children: [
            child,
            SafeArea(
              bottom: false,
              left: false,
              right: false,
              child: Align(
                alignment: AlignmentDirectional.topStart,
                child: SizedBox(
                  width: 56,
                  height: kToolbarHeight,
                  child: Material(
                    type: MaterialType.transparency,
                    child: IconButton(
                      icon: const BackButtonIcon(),
                      color: Colors.white,
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
    );
  }
}
