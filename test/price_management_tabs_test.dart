import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the price page controller has one entry per tab', () {
    final source = File(
      'lib/Screen/price_management_screen.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final length = int.parse(
      RegExp(r'TabController\(\s*(?://[^\n]*\n\s*)*length: (\d+)')
          .firstMatch(source)!
          .group(1)!,
    );
    final tabBar = source.substring(
      source.indexOf('bottom: TabBar('),
      source.indexOf('body: PageStorage('),
    );
    final tabs = RegExp(r'(?:const )?Tab\(').allMatches(tabBar).length;
    // A tab without a controller entry can never be selected: the
    // mosquito-net tab was left out when two tabs were added at once.
    expect(length, tabs);
  });
}
