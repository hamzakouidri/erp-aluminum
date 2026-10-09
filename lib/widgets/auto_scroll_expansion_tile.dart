import 'package:flutter/material.dart';

/// An [ExpansionTile] wrapper that automatically scrolls the parent [Scrollable]
/// when expanded, ensuring all newly opened items are completely visible on screen.
class AutoScrollExpansionTile extends StatelessWidget {
  const AutoScrollExpansionTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.onExpansionChanged,
    this.children = const <Widget>[],
    this.trailing,
    this.initiallyExpanded = false,
    this.maintainState = false,
    this.tilePadding,
    this.expandedCrossAxisAlignment,
    this.expandedAlignment,
    this.childrenPadding,
    this.backgroundColor,
    this.collapsedBackgroundColor,
    this.textColor,
    this.collapsedTextColor,
    this.iconColor,
    this.collapsedIconColor,
    this.shape,
    this.collapsedShape,
    this.clipBehavior,
    this.controlAffinity,
    this.controller,
    this.dense,
    this.visualDensity,
    this.minTileHeight,
    this.enableFeedback,
    this.enabled = true,
    this.expansionAnimationStyle,
    this.scrollAlignment = 0.92,
  });

  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final ValueChanged<bool>? onExpansionChanged;
  final List<Widget> children;
  final Widget? trailing;
  final bool initiallyExpanded;
  final bool maintainState;
  final EdgeInsetsGeometry? tilePadding;
  final Alignment? expandedAlignment;
  final CrossAxisAlignment? expandedCrossAxisAlignment;
  final EdgeInsetsGeometry? childrenPadding;
  final Color? backgroundColor;
  final Color? collapsedBackgroundColor;
  final Color? textColor;
  final Color? collapsedTextColor;
  final Color? iconColor;
  final Color? collapsedIconColor;
  final ShapeBorder? shape;
  final ShapeBorder? collapsedShape;
  final Clip? clipBehavior;
  final ListTileControlAffinity? controlAffinity;
  final ExpansionTileController? controller;
  final bool? dense;
  final VisualDensity? visualDensity;
  final double? minTileHeight;
  final bool? enableFeedback;
  final bool enabled;
  final AnimationStyle? expansionAnimationStyle;
  final double scrollAlignment;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (tileContext) {
        return ExpansionTile(
          key: key,
          leading: leading,
          title: title,
          subtitle: subtitle,
          onExpansionChanged: (expanded) {
            onExpansionChanged?.call(expanded);
            if (expanded) {
              Future.delayed(const Duration(milliseconds: 260), () {
                if (tileContext.mounted) {
                  Scrollable.ensureVisible(
                    tileContext,
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeInOutCubic,
                    alignment: scrollAlignment,
                    alignmentPolicy:
                        ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
                  );
                }
              });
            }
          },
          children: children,
          trailing: trailing,
          initiallyExpanded: initiallyExpanded,
          maintainState: maintainState,
          tilePadding: tilePadding,
          expandedCrossAxisAlignment: expandedCrossAxisAlignment,
          expandedAlignment: expandedAlignment,
          childrenPadding: childrenPadding,
          backgroundColor: backgroundColor,
          collapsedBackgroundColor: collapsedBackgroundColor,
          textColor: textColor,
          collapsedTextColor: collapsedTextColor,
          iconColor: iconColor,
          collapsedIconColor: collapsedIconColor,
          shape: shape,
          collapsedShape: collapsedShape,
          clipBehavior: clipBehavior,
          controlAffinity: controlAffinity,
          controller: controller,
          dense: dense,
          visualDensity: visualDensity,
          minTileHeight: minTileHeight,
          enableFeedback: enableFeedback,
          enabled: enabled,
          expansionAnimationStyle: expansionAnimationStyle,
        );
      },
    );
  }
}
