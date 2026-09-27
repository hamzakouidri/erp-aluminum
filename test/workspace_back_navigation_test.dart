import 'package:database_data/Screen/app_workspace_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Back at a tab root returns home and keeps the tab open', (
    tester,
  ) async {
    final workspace = WorkspaceController();
    workspace.open(
      entryId: 'order',
      title: 'Order',
      icon: Icons.description,
      content: const SizedBox(),
    );
    var rootBackCalls = 0;
    final key = workspace.navigatorKeyFor('order');
    await tester.pumpWidget(MaterialApp(
      home: Navigator(
        key: key,
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) => PopScope(
            canPop: false,
            onPopInvokedWithResult: (_, _) => rootBackCalls++,
            child: const SizedBox(),
          ),
        ),
      ),
    ));

    await workspace.handleBackNavigation();
    expect(workspace.isHomeActive, isTrue);
    expect(workspace.entries.any((entry) => entry.id == 'order'), isTrue);
    expect(rootBackCalls, 0);
    await tester.pumpWidget(const SizedBox());
    workspace.dispose();
  });

  testWidgets('Back pops an inner page before returning home', (tester) async {
    final workspace = WorkspaceController();
    workspace.open(
      entryId: 'order',
      title: 'Order',
      icon: Icons.description,
      content: const SizedBox(),
    );
    final key = workspace.navigatorKeyFor('order');
    await tester.pumpWidget(MaterialApp(
      home: Navigator(
        key: key,
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) => const SizedBox(),
        ),
      ),
    ));
    key.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const SizedBox(),
    ));
    await tester.pumpAndSettle();
    await workspace.handleBackNavigation();
    await tester.pumpAndSettle();
    expect(workspace.isHomeActive, isFalse);
    expect(key.currentState!.canPop(), isFalse);
    await workspace.handleBackNavigation();
    expect(workspace.isHomeActive, isTrue);
    await tester.pumpWidget(const SizedBox());
    workspace.dispose();
  });
}
