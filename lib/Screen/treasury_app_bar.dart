import 'package:flutter/material.dart';

/// One action button of the treasury AppBar.
class TreasuryAppBarAction {
  const TreasuryAppBarAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
}

/// Treasury AppBar that fits any width.
///
/// The actions stay inline while there is room and the rest go into an
/// overflow menu. Otherwise the actions row grows past the leading back arrow
/// and the first action (the daily closing) is drawn under it.
class TreasuryAppBar extends StatelessWidget implements PreferredSizeWidget {
  const TreasuryAppBar({
    super.key,
    required this.title,
    required this.caisseSelectorBuilder,
    required this.actions,
    required this.moreLabel,
    this.backgroundColor,
  });

  final String title;

  /// Builds the cash box selector, its label limited to the given width.
  final Widget Function(double labelMaxWidth) caisseSelectorBuilder;

  /// Ordered by priority: the first ones stay inline on narrow screens.
  final List<TreasuryAppBarAction> actions;
  final String moreLabel;
  final Color? backgroundColor;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final labelMaxWidth = width < 600 ? 90.0 : 125.0;
        final hasLeading =
            ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
        // Selector: padding + wallet icon + gap + label + drop-down arrow.
        final selectorWidth = 53 + labelMaxWidth;
        final titleMinWidth = width < 600 ? 72.0 : 160.0;
        final free =
            width -
            (hasLeading ? kToolbarHeight : 0) -
            NavigationToolbar.kMiddleSpacing -
            titleMinWidth -
            selectorWidth;
        final slots = free <= 0 ? 0 : (free / kMinInteractiveDimension).floor();
        final inlineCount = slots >= actions.length
            ? actions.length
            : (slots - 1).clamp(0, slots);
        final overflow = actions.skip(inlineCount).toList();

        return AppBar(
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: backgroundColor,
          actions: [
            caisseSelectorBuilder(labelMaxWidth),
            for (final action in actions.take(inlineCount))
              IconButton(
                icon: Icon(action.icon),
                tooltip: action.label,
                onPressed: action.onPressed,
              ),
            if (overflow.isNotEmpty)
              PopupMenuButton<int>(
                icon: const Icon(Icons.more_vert),
                tooltip: moreLabel,
                onSelected: (index) => overflow[index].onPressed(),
                itemBuilder: (context) => [
                  for (var i = 0; i < overflow.length; i++)
                    PopupMenuItem<int>(
                      value: i,
                      child: Row(
                        children: [
                          Icon(overflow[i].icon, size: 20),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              overflow[i].label,
                              style: const TextStyle(fontFamily: 'Cairo'),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}
