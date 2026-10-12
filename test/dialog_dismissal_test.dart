import 'package:database_data/widgets/app_material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('all app dialogs close when the outside barrier is clicked', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                // Legacy callers may still pass false. The app-wide wrapper
                // must nevertheless keep outside-click dismissal consistent.
                barrierDismissible: false,
                builder: (_) => const AlertDialog(
                  content: Text('dialog-content'),
                ),
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
    expect(find.text('dialog-content'), findsNothing);
  });
}
