import 'package:database_data/widgets/resizable_columns_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('right click header can hide a column and persists the choice',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ResizableColumnsTable(
            persistenceKey: 'visibility-test',
            columns: [
              ResizableTableColumn(id: 'a', label: Text('Column A'), initialWidth: 160),
              ResizableTableColumn(id: 'b', label: Text('Column B'), initialWidth: 160),
            ],
            rows: [
              ResizableTableRow(cells: [Text('Cell A'), Text('Cell B')]),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Column A'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Column A'), findsNWidgets(2));
    expect(find.text('Column B'), findsNWidgets(2));

    await tester.tap(find.text('Column B').last);
    await tester.pumpAndSettle();
    // The column is hidden and the list stays open: only its menu entry,
    // now unchecked, remains.
    expect(find.text('Column B'), findsOneWidget);
    expect(find.text('Cell B'), findsNothing);
    expect(
      tester.widget<Checkbox>(
        find.descendant(
          of: find.ancestor(
            of: find.text('Column B'),
            matching: find.byType(Row),
          ),
          matching: find.byType(Checkbox),
        ),
      ).value,
      isFalse,
    );

    // The last visible column cannot be hidden.
    await tester.tap(find.text('Column A').last);
    await tester.pumpAndSettle();
    expect(find.text('Cell A'), findsOneWidget);

    // A click outside closes the list.
    await tester.tapAt(const Offset(5, 590));
    await tester.pumpAndSettle();
    expect(find.text('Column B'), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('resizable_table_layout_visibility-test'),
      contains('"hidden":["b"]'),
    );
  });

  testWidgets('single click selects and double click opens the row',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final actions = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ResizableColumnsTable(
          columns: const [
            ResizableTableColumn(id: 'order', label: Text('Orders'), initialWidth: 300),
          ],
          rows: List.generate(2, (index) => ResizableTableRow(
            cells: [Text('Order $index')],
            onTap: () => actions.add('open $index'),
            onDoubleTap: () => actions.add('edit $index'),
            onKeyEvent: (event) {
              if (event is KeyDownEvent && HardwareKeyboard.instance.isControlPressed &&
                  (event.logicalKey == LogicalKeyboardKey.keyA ||
                      event.logicalKey == LogicalKeyboardKey.keyF)) {
                actions.add('$index ${event.logicalKey.keyLabel}');
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
          )),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Order 0'));
    await tester.pumpAndSettle();
    expect(actions, isEmpty);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(actions, ['0 A', '1 F']);
    await tester.tap(find.text('Order 1'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Order 1'));
    await tester.pumpAndSettle();
    expect(actions, ['0 A', '1 F', 'open 1']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop rows show hover shadow and a fallback context menu',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final actions = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ResizableColumnsTable(
          columns: const [
            ResizableTableColumn(
              id: 'item',
              label: Text('Items'),
              initialWidth: 300,
            ),
          ],
          rows: [
            ResizableTableRow(
              reorderId: '42',
              cells: const [Text('Window 42')],
              onTap: () => actions.add('open'),
              onDoubleTap: () => actions.add('edit'),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Window 42')));
    await tester.pump(const Duration(milliseconds: 150));
    final surface = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('table_row_surface_42')),
    );
    final decoration = surface.decoration! as BoxDecoration;
    expect(decoration.boxShadow, isNotEmpty);

    await tester.tap(find.text('Window 42'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(actions, ['edit']);
    expect(tester.takeException(), isNull);
  });
}
