import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every translation key is defined once per language file: `jsonDecode`
/// keeps the last of two repeated keys and silently drops the earlier text.
void main() {
  test('translation keys are not repeated in a language file', () {
    final files = Directory('assets/i18n')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    expect(files, isNotEmpty);
    final repeated = <String>[];
    for (final file in files) {
      final seen = <String>{};
      final reader = _KeyReader(file.readAsStringSync());
      for (final key in reader.stringKeys()) {
        if (!seen.add(key)) repeated.add('"$key" in ${file.path}');
      }
    }
    expect(repeated, isEmpty, reason: repeated.take(20).join('\n'));
  });
}

/// Reads the keys of the `strings` object in file order, repeats included.
class _KeyReader {
  _KeyReader(this.source);

  final String source;

  Iterable<String> stringKeys() sync* {
    final start = source.indexOf('"strings"');
    if (start < 0) return;
    var i = source.indexOf('{', start) + 1;
    var depth = 1;
    var expectKey = true;
    while (i < source.length && depth > 0) {
      final c = source[i];
      if (c == '"') {
        final end = _stringEnd(i);
        if (expectKey && depth == 1) {
          yield jsonDecode(source.substring(i, end)) as String;
        }
        expectKey = false;
        i = end;
        continue;
      }
      if (c == '{') depth++;
      if (c == '}') depth--;
      if (c == ',' && depth == 1) expectKey = true;
      i++;
    }
  }

  int _stringEnd(int open) {
    var i = open + 1;
    while (source[i] != '"') {
      i += source[i] == r'\' ? 2 : 1;
    }
    return i + 1;
  }
}
