import 'package:database_data/Screen/treasury_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _icons = [
  Icons.add_circle_outline_rounded,
  Icons.lock_clock_rounded,
  Icons.search,
  Icons.filter_alt,
  Icons.refresh,
  Icons.settings_outlined,
];

Future<void> _pumpTreasuryAppBar(
  WidgetTester tester, {
  required double width,
  required TextDirection direction,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final actions = [
    for (final icon in _icons)
      TreasuryAppBarAction(icon: icon, label: '$icon', onPressed: () {}),
  ];

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          Directionality(textDirection: direction, child: child!),
      home: const Scaffold(body: Text('home')),
    ),
  );
  // Push the treasury page so the AppBar shows its back arrow.
  final navigator = tester.state<NavigatorState>(find.byType(Navigator));
  navigator.push(
    MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: TreasuryAppBar(
          title: 'الخزينة (Caisse)',
          caisseSelectorBuilder: (labelMaxWidth) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.account_balance_wallet_outlined, size: 19),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: labelMaxWidth),
                  child: const Text(
                    'Toutes les caisses de la société',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 18),
              ],
            ),
          ),
          actions: actions,
          moreLabel: 'More options',
        ),
        body: const SizedBox(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectNoOverlapWithBackArrow(WidgetTester tester) {
  final back = tester.getRect(find.byType(BackButton));
  final insideBack = find
      .descendant(
        of: find.byType(BackButton),
        matching: find.byType(IconButton),
      )
      .evaluate()
      .toSet();
  final actions = [
    ...find
        .descendant(of: find.byType(AppBar), matching: find.byType(IconButton))
        .evaluate()
        .where((e) => !insideBack.contains(e)),
    ...find.byIcon(Icons.account_balance_wallet_outlined).evaluate(),
  ];
  expect(actions, isNotEmpty);
  final screen = Offset.zero & tester.view.physicalSize;
  for (final element in actions) {
    final box = element.renderObject! as RenderBox;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    expect(
      rect.overlaps(back),
      isFalse,
      reason: 'action at $rect overlaps the back arrow at $back',
    );
    expect(screen.intersect(rect), rect, reason: '$rect is off screen');
  }
}

void main() {
  for (final direction in TextDirection.values) {
    testWidgets('phone width 360 ($direction): no overflow, actions in menu', (
      tester,
    ) async {
      await _pumpTreasuryAppBar(tester, width: 360, direction: direction);

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      _expectNoOverlapWithBackArrow(tester);

      // Every hidden action is still reachable from the overflow menu.
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      for (final icon in _icons) {
        expect(find.byIcon(icon), findsOneWidget);
      }
    });

    testWidgets('tablet width 700 ($direction): no overflow', (tester) async {
      await _pumpTreasuryAppBar(tester, width: 700, direction: direction);

      expect(tester.takeException(), isNull);
      _expectNoOverlapWithBackArrow(tester);
    });

    testWidgets('desktop width 1366 ($direction): every action inline', (
      tester,
    ) async {
      await _pumpTreasuryAppBar(tester, width: 1366, direction: direction);

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.more_vert), findsNothing);
      for (final icon in _icons) {
        expect(find.byIcon(icon), findsOneWidget);
      }
      _expectNoOverlapWithBackArrow(tester);
    });
  }
}
