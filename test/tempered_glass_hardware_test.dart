import 'package:database_data/Commande/tempered_glass_hardware.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an accessory lists its holes with their diameters and spacings', () {
    final template = GlassAccessoryTemplate.fromItem({
      'holes_count': 3,
      'hole_diameters': '12, 10',
      'hole_spacings': '150;200',
      'hole_layout': 'vertical',
      'mount_target': 'door',
      'glass_thickness_mm': 8,
    });

    expect(template.holeDiameters, [12, 10, 10]);
    expect(template.spanMm, 350);
    final holes = template.holes();
    expect(holes.map((h) => h.dyMm), [0, 150, 350]);
    expect(holes.every((h) => h.dxMm == 0), isTrue);
    expect(template.fitsThickness(8), isTrue);
    expect(template.fitsThickness(10), isFalse);
    expect(GlassMountTarget.fitsPanel(template.mountTarget, 'door'), isTrue);
    expect(GlassMountTarget.fitsPanel(template.mountTarget, 'fixed'), isFalse);
  });

  test('an older item with one entraxe keeps it between every hole', () {
    final template = GlassAccessoryTemplate.fromItem({
      'holes_count': 2,
      'entraxe': 200,
    });

    expect(template.holeDiameters, [12, 12]);
    expect(template.holeSpacings, [200]);
    expect(template.vertical, isFalse);
    expect(template.mountTarget, GlassMountTarget.all);
    expect(
      template.fitsGlass(widthMm: 300, heightMm: 500, xMm: 50, yMm: 50),
      isTrue,
    );
    expect(
      template.fitsGlass(widthMm: 240, heightMm: 500, xMm: 50, yMm: 50),
      isFalse,
    );
  });

  test('a sliding shower measures its channels, rail and gasket', () {
    const profiles = SlidingGlassProfiles(
      fixedWidthMm: 800,
      fixedHeightMm: 1900,
      overallWidthMm: 1500,
    );

    expect(profiles.bottomChannelMm, 800);
    expect(profiles.wallChannelMm, 1885);
    expect(profiles.uChannelMm, 2685);
    expect(profiles.topRailMm, 1500);
    expect(profiles.profileGasketMm, 3485);
    expect(GlassGasketType.soldByMetre(GlassGasketType.rail), isTrue);
    expect(GlassGasketType.soldByMetre(GlassGasketType.magnetic90), isFalse);
  });

  test('an accessory is priced by its colour, else by its base price', () {
    final item = {
      'price': 1500,
      'color_prices': encodeColorPrices(const [
        GlassItemColorPrice(color: 'Noir mat', price: 2100),
        GlassItemColorPrice(color: 'Doré', price: 2600),
      ]),
    };

    expect(parseColorPrices(item['color_prices']).length, 2);
    expect(glassItemPriceForColor(item, 'noir mat'), 2100);
    expect(glassItemPriceForColor(item, 'Doré'), 2600);
    expect(glassItemPriceForColor(item, 'Chromé'), 1500);
    expect(glassItemPriceForColor(item, ''), 1500);
    expect(parseColorPrices('not json'), isEmpty);
  });
}
