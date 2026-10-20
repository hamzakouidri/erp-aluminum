import 'dart:convert';

import 'package:database_data/Screen/audit_details_format.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final snapshot = jsonEncode({
    'before': {
      'header': {
        'id': 17,
        'order_code': 'C-0017',
        'status': 'Devis',
        'total': 54000.0,
        'client_id': 3,
        'updated_at': '2026-10-20T10:00:00Z',
      },
      'items': [
        {
          'id': 1,
          'game': 'Coulissant TPR 67000',
          'largeur': 1200,
          'hauteur': 1250,
          'quantity': 2,
          'price': 27000,
          'partitions_json': '{"zones": []}',
        },
        {'id': 2, 'game': 'Volet roulant', 'quantity': 1, 'price': 9000},
      ],
    },
    'after': {
      'header': {'order_code': 'C-0017', 'status': 'Devis', 'total': 60000},
      'items': [
        {
          'id': 1,
          'game': 'Coulissant TPR 67000',
          'largeur': 1200,
          'hauteur': 1250,
          'quantity': 3,
          'price': 27000,
        },
      ],
    },
  });

  test('a before/after snapshot reads as changes, then the document', () {
    final lines = formatAuditDetails(snapshot, AppLanguage.french);
    final text = lines.join('\n');
    expect(lines.first, contains('Modifications'));
    expect(text, contains('Total: 54000 → 60000'));
    expect(text, contains('Quantité: 2 → 3'));
    expect(text, contains('Ligne supprimée: Volet roulant'));
    expect(text, contains('1200 × 1250 mm'));
    expect(text, contains('N° de commande: C-0017'));
    // Ids, links, stored drawings and sync stamps stay out.
    expect(text, isNot(contains('partitions_json')));
    expect(text, isNot(contains('zones')));
    expect(text, isNot(contains('client_id')));
    expect(text, isNot(contains('updated_at')));
  });

  test('plain text and flat JSON stay readable', () {
    expect(formatAuditDetails('Devis → Commande', AppLanguage.arabic), [
      'Devis → Commande',
    ]);
    expect(
      formatAuditDetails(jsonEncode({'total': 12.5}), AppLanguage.english),
      ['Total: 12.50'],
    );
  });
}
