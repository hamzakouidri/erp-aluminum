import 'package:database_data/widgets/system_development_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('development badge fits a narrow system card', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 145,
              child: SystemDevelopmentBadge(
                label: 'En développement — indisponible pour le moment',
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.text('En développement — indisponible pour le moment'),
      findsOneWidget,
    );
  });
}
