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
    expect(find.text('Column B'), findsNothing);
    expect(find.text('Cell B'), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('resizable_table_layout_visibility-test'),
      contains('"hidden":["b"]'),
    );
  });

  testWidgets('selected rows receive shortcuts and double clicks separately',
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
    expect(actions, ['0 A', '1 F', 'edit 1']);
    expect(tester.takeException(), isNull);
  });
}
