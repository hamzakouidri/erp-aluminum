import 'package:database_data/Screen/inventory_item_history_screen.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Supabase is not initialised in tests; answer the cost permission here.
class _Settings extends AppSettingsProvider {
  @override
  bool canViewCostPrice() => true;
}

class _CannedCard extends SqlDatabase {
  @override
  Future<Map<String, dynamic>> readProductMovementCard({
    required int itemId,
    required String itemType,
    int? colorId,
  }) async => {
    'movements': <Map<String, dynamic>>[
      {
        'moved_at': '2026-10-18T08:20:00Z',
        'movement_type': SqlDatabase.movementPurchaseReceipt,
        'quantity': 100.0,
        'to_location_id': 1,
        'to_location_name': 'مستودع المحل',
        'party_supplier_id': 3,
        'supplier_name': 'مورد الألمنيوم',
        'doc_type': 'purchase',
        'doc_id': 45,
        'doc_code': 'ACH-45',
        'performed_by': 'أحمد',
        'running_balance': 100.0,
      },
      {
        'moved_at': '2026-10-18T10:30:00Z',
        'movement_type': SqlDatabase.movementInternalTransfer,
        'is_transfer': true,
        'legs': [{}, {}],
        'quantity': 0.0,
        'transfer_quantity': 20.0,
        'from_location_id': 1,
        'from_location_name': 'مستودع المحل',
        'to_location_id': 2,
        'to_location_name': 'مستودع الورشة',
        'out_document_code': 'INT-12',
        'performed_by': 'أحمد',
        'running_balance': 100.0,
      },
      {
        'moved_at': '2026-10-20T15:00:00Z',
        'movement_type': SqlDatabase.movementSaleIssue,
        'quantity': -5.0,
        'from_location_id': 1,
        'from_location_name': 'مستودع المحل',
        'party_client_id': 5,
        'client_name': 'زبون البيع',
        'doc_type': 'sale',
        'doc_id': 91,
        'doc_code': 'MAT-91',
        'performed_by': 'سمير',
        'running_balance': 95.0,
      },
    ],
    'balances': <Map<String, dynamic>>[
      {
        'location_id': 1,
        'location_name': 'مستودع المحل',
        'quantity': 75.0,
        'reserved_quantity': 10.0,
      },
      {
        'location_id': 2,
        'location_name': 'مستودع الورشة',
        'quantity': 20.0,
        'reserved_quantity': 0.0,
      },
    ],
    'total_quantity': 95.0,
    'reserved_quantity': 10.0,
    'last_purchase': null,
    'average_cost': null,
  };
}

void main() {
  testWidgets('the card lists movements and filters them by type', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = _Settings();
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppSettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          home: InventoryItemHistoryScreen(
            db: _CannedCard(),
            itemId: 7,
            itemType: 'Section',
            itemName: 'Frame 40',
            colorName: '',
            locationId: 1,
            locationName: 'مستودع المحل',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('+100'), findsOneWidget);
    expect(find.text('-20 / +20'), findsOneWidget);
    expect(find.text('-5'), findsOneWidget);
    expect(find.text('مورد الألمنيوم'), findsOneWidget);
    expect(find.text('زبون البيع'), findsOneWidget);
    // Total 95, of which 10 reserved.
    expect(find.text('95'), findsWidgets);
    expect(find.text('85'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String?>).first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(Localization.translate('بيع مواد', settings.language)).last,
    );
    await tester.pumpAndSettle();

    expect(find.text('-5'), findsOneWidget);
    expect(find.text('+100'), findsNothing);
    expect(find.text('-20 / +20'), findsNothing);
  });
}
