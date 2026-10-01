import 'package:database_data/Screen/app_workspace_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/widgets/home_back_boundary.dart';

void main() {
  testWidgets('standalone page has a home button and intercepts route back', (tester) async {
    var backs = 0;
    await tester.pumpWidget(MaterialApp(home: HomeBackBoundary(
      label: 'Home', onBack: () => backs++, child: const Scaffold(body: Text('Quote')),
    )));
    await tester.tap(find.text('Home'));
    expect(backs, 1);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(backs, 2);
    expect(find.text('Quote'), findsOneWidget);
  });

  test('exit callback is only reached from home', () async {
    final workspace = WorkspaceController();
    var exits = 0;
    workspace.open(entryId: 'quote', title: 'Quote', icon: Icons.description,
        content: const SizedBox());
    await workspace.handleBackNavigation(onHome: () async { exits++; });
    expect(workspace.isHomeActive, isTrue);
    expect(exits, 0);
    await workspace.handleBackNavigation(onHome: () async { exits++; });
    expect(exits, 1);
    workspace.dispose();
  });
  testWidgets('Back at a tab root returns home and closes the tab', (
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
    expect(workspace.entries.any((entry) => entry.id == 'order'), isFalse);
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
    expect(workspace.entries.any((entry) => entry.id == 'order'), isFalse);
    await tester.pumpWidget(const SizedBox());
    workspace.dispose();
  });
}
