import 'package:database_data/widgets/app_material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'app dialogs stay open on an outside click and close with Escape',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  // Callers passing true no longer change the app-wide rule:
                  // a stray click must not close a dialog or answer it.
                  barrierDismissible: true,
                  builder: (_) =>
                      const AlertDialog(content: Text('dialog-content')),
                ),
                child: const Text('open-dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open-dialog'));
      await tester.pumpAndSettle();
      expect(find.text('dialog-content'), findsOneWidget);

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('dialog-content'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('dialog-content'), findsNothing);
    },
  );
}
