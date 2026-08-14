import 'package:database_data/Commande/decor_panel_designs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decor panel designs have stable unique database codes', () {
    final codes = DecorPanelDesignCatalog.designs
        .map((design) => design.code)
        .toList();

    expect(codes, hasLength(7));
    expect(codes.toSet(), hasLength(codes.length));
    expect(codes.every(DecorPanelDesignCatalog.isSupported), isTrue);
  });

  test('decor drawing resolves by product ID and survives a name change', () {
    final products = <Map<String, dynamic>>[
      {
        'id': 42,
        'name': 'يمكن تغيير هذا الاسم لاحقاً',
        'type': 'Panneau',
        'subtype': 'panneau décor',
        'decor_design_code': 'decor_clover_columns',
      },
    ];

    expect(
      DecorPanelDesignCatalog.resolveForProduct(
        productId: 42,
        glassProducts: products,
      ),
      'decor_clover_columns',
    );
    expect(
      DecorPanelDesignCatalog.resolveForProduct(
        productId: 7,
        glassProducts: products,
      ),
      isNull,
    );
  });

  testWidgets('every lightweight decor design can be painted', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Wrap(
            children: DecorPanelDesignCatalog.designs
                .map(
                  (design) => DecorPanelDesignPreview(
                    designCode: design.code,
                    width: 80,
                    height: 150,
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
