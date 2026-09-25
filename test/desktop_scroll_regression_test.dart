import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/widgets/desktop_scroll_behavior.dart';

void main() {
  testWidgets('wheel fallback never scrolls behind a modal barrier', (
    tester,
  ) async {
    final controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => Listener(
          onPointerSignal: DesktopScrollCoordinator.handlePointerSignal,
          child: child,
        ),
        home: Scaffold(
          body: DesktopScrollFallback(
            controller: controller,
            child: Builder(
              builder: (context) => Column(
                children: [
                  ElevatedButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) =>
                          const AlertDialog(content: Text('Dialog')),
                    ),
                    child: const Text('Open'),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: controller,
                      itemCount: 100,
                      itemBuilder: (_, i) =>
                          SizedBox(height: 60, child: Text('$i')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(200, 300),
        scrollDelta: Offset(0, 80),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    final beforeBurst = controller.offset;
    for (var i = 0; i < 5; i++) {
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(200, 300),
          scrollDelta: Offset(0, 40),
        ),
      );
    }
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(beforeBurst + 200, 0.01));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final before = controller.offset;
    for (var i = 0; i < 5; i++) {
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(20, 300),
          scrollDelta: Offset(0, 80),
        ),
      );
      await tester.pump();
    }
    expect(controller.offset, before);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
