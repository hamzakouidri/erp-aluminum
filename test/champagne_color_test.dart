import 'package:database_data/Commande/Systeme/model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Arabic Champagne colour keeps its real champagne finish', () {
    final colors = getEffectiveGradientColors(FrameColor.white, {
      'name': 'شومبان',
      'hex_code': '#F5F5DC',
    });

    expect(colors[1], const Color(0xFFF7E7CE));
  });
}
