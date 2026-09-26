import 'dart:convert';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('named finishes with placeholder white hex are not default white', () {
    final model = WindowModel(db: SqlDatabase());
    model.availableColors = [
      {'id': 37, 'name': 'Faux bois', 'hex_code': '#FFFFFF'},
      {'id': 34, 'name': 'Gris', 'hex_code': '#FFFFFF'},
      {'id': 32, 'name': 'الابيض', 'hex_code': '#FFFFFF'},
    ];
    model.clearAll();
    expect(model.selectedDbColor?['id'], 32);
  });

  test('missing white keeps white rendering without selecting wood', () {
    final model = WindowModel(db: SqlDatabase());
    model.availableColors = [
      {'id': 37, 'name': 'Faux bois', 'hex_code': '#FFFFFF'},
    ];
    model.clearAll();
    expect(model.selectedDbColor, isNull);
    expect(model.frameColor, FrameColor.white);
  });

  test('mojibake repair test', () {
    const unicodeToWin1252 = <int, int>{
      0x20AC: 0x80, 0x201A: 0x82, 0x0192: 0x83, 0x201E: 0x84,
      0x2026: 0x85, 0x2020: 0x86, 0x2021: 0x87, 0x02C6: 0x88,
      0x2030: 0x89, 0x0160: 0x8A, 0x2039: 0x8B, 0x0152: 0x8C,
      0x017D: 0x8E, 0x2018: 0x91, 0x2019: 0x92, 0x201C: 0x93,
      0x201D: 0x94, 0x2022: 0x95, 0x2013: 0x96, 0x2014: 0x97,
      0x02DC: 0x98, 0x2122: 0x99, 0x0161: 0x9A, 0x203A: 0x9B,
      0x0153: 0x9C, 0x017E: 0x9E, 0x0178: 0x9F,
    };

    String repair(String text) {
      try {
        final bytes = <int>[];
        for (final rune in text.runes) {
          if (rune <= 0xFF) {
            bytes.add(rune);
          } else if (unicodeToWin1252.containsKey(rune)) {
            bytes.add(unicodeToWin1252[rune]!);
          } else {
            return text;
          }
        }
        return utf8.decode(bytes, allowMalformed: false);
      } catch (_) {
        return text;
      }
    }

    expect(repair('DÃ©caissement'), 'Décaissement');
    expect(repair('ØªØ³ÙˆÙŠØ© Ø£Ø³Ø¨ÙˆØ¹ÙŠØ© Ù„Ù„Ø¹Ø§Ù…Ù„ HAMZAK'), 'تسوية أسبوعية للعامل HAMZAK');
    expect(repair('Ø§Ù„ØµÙ†Ø¯ÙˆÙ‚ Ø§Ù„Ø±Ø¦ÙŠØ³ÙŠ'), 'الصندوق الرئيسي');
  });
}
