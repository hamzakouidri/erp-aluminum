import 'dart:async';
import 'package:database_data/services/auth_service.dart';
import 'package:database_data/widgets/auth_session_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sign out removes pushed workspace routes and shows login', (tester) async {
    final auth = StreamController<AppAuthUser?>();
    addTearDown(auth.close);
    await tester.pumpWidget(AuthSessionView(
      authStateChanges: auth.stream,
      initialUser: const AppAuthUser(uid: 'worker', email: null),
      builder: (_, user) => MaterialApp(
        home: Scaffold(body: Builder(builder: (context) => user == null
            ? const Text('Login')
            : TextButton(onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Order editor')))),
                child: const Text('Open order')))),
      ),
    ));
    await tester.tap(find.text('Open order'));
    await tester.pumpAndSettle();
    expect(find.text('Order editor'), findsOneWidget);
    auth.add(null);
    await tester.pumpAndSettle();
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Order editor'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
