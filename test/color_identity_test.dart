import 'package:database_data/sql_database.dart';
import 'package:database_data/utils/real_color_resolver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('spellings of one colour share an identity, variants do not', () {
    final champagne = {
      for (final name in [
        'Champagne',
        'شمبانيا',
        'شامبانيا',
        'شمبانيا (Champagne)',
        ' champagne ',
      ])
        SqlDatabase.colorIdentityKey(name),
    };
    expect(champagne, {'champagne'});
    expect(SqlDatabase.colorIdentityKey('Champagne Mat'), isNot('champagne'));
    expect(
      SqlDatabase.colorIdentityKey('أبيض'),
      SqlDatabase.colorIdentityKey('ابيض'),
    );
  });

  test('metallic colours keep their shine whatever their stored hex', () {
    final gold = realGradientColors({'name': 'ذهبي', 'hex_code': '#FFD700'});
    expect(gold.length, greaterThan(3));
    expect(gold, isNot(contains(const Color(0xFFFFD700))));
  });

  test('faux bois marron uses the light brown wood, not the antique', () {
    final image = realColorTextureImage({'name': 'Faux Bois Marron'});
    expect(
      (image!.image as AssetImage).assetName,
      'assets/images/wood_texture_light_brown.png',
    );
  });
}
