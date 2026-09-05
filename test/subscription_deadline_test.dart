import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/widgets/subscription_deadline.dart';

void main() {
  testWidgets('expires locally without a server event and reopens on extension', (tester) async {
    Widget gate(DateTime date) => Directionality(
      textDirection: TextDirection.ltr,
      child: SubscriptionDeadline(endsAt: date,
        child: const Text('open'), expired: const Text('expired')));
    await tester.pumpWidget(gate(DateTime.now().toUtc().add(const Duration(minutes: 1))));
    expect(find.text('open'), findsOneWidget);
    await tester.pump(const Duration(seconds: 61));
    expect(find.text('expired'), findsOneWidget);
    await tester.pumpWidget(gate(DateTime.now().toUtc().add(const Duration(minutes: 2))));
    expect(find.text('open'), findsOneWidget);
  });
  test('UTC and Algeria offsets represent the same deadline', () {
    expect(DateTime.parse('2026-09-05T18:00:00+01:00'),
      DateTime.parse('2026-09-05T17:00:00Z'));
  });
}
