import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/widgets/desktop_scroll_behavior.dart';

void main() {
  testWidgets('wheel over translated page chrome handles every tick', (
    tester,
  ) async {
    final controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => Listener(
          onPointerSignal: DesktopScrollCoordinator.handlePointerSignal,
          child: child,
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.only(left: 120, top: 80),
            child: DesktopScrollFallback(
              controller: controller,
              child: Column(
                children: [
                  const SizedBox(
                    key: ValueKey('toolbar'),
                    height: 80,
                    width: double.infinity,
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
    final pointer = tester.getCenter(find.byKey(const ValueKey('toolbar')));
    for (var i = 0; i < 5; i++) {
      await tester.sendEventToBinding(
        PointerScrollEvent(position: pointer, scrollDelta: const Offset(0, 40)),
      );
    }
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(200, 0.01));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: pointer, scrollDelta: const Offset(0, -40)),
    );
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(160, 0.01));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

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
