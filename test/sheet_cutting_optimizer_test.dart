import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/services/sheet_cutting_optimizer_engine.dart';

void main() {
  group('SheetCuttingOptimizerEngine Tests', () {
    test('Packs pieces correctly into standard sheets and reports metrics', () {
      final pieces = [
        const SheetDemandPiece(
          id: 'p1',
          orderId: 10,
          windowName: 'F1',
          materialType: 'resine',
          color: 'Chêne',
          lengthMm: 1200,
          widthMm: 600,
          count: 2,
        ),
        const SheetDemandPiece(
          id: 'p2',
          orderId: 10,
          windowName: 'F2',
          materialType: 'resine',
          color: 'Chêne',
          lengthMm: 1000,
          widthMm: 500,
          count: 2,
        ),
      ];

      final standards = [
        {
          'id': 1,
          'material_type': 'resine',
          'name': 'لوح ريزين قياسي',
          'length_mm': 2800.0,
          'width_mm': 1300.0,
          'allow_rotation': 1,
          'price_per_sheet': 12000.0,
        }
      ];

      final report = SheetCuttingOptimizerEngine.optimize(
        demandPieces: pieces,
        availableStandardSheets: standards,
        availableRemnants: const [],
        sawKerfMm: 3.0,
      );

      expect(report.groups.containsKey('resine__chêne'), isTrue);
      final group = report.groups['resine__chêne']!;
      expect(group.placedPiecesCount, 4);
      expect(group.sheets.isNotEmpty, isTrue);
      // All 4 pieces total area is 2*(1.2*0.6) + 2*(1.0*0.5) = 1.44 + 1.0 = 2.44 m2
      // Sheet area is 2.8*1.3 = 3.64 m2 -> All fit on 1 sheet!
      expect(group.newSheetsUsedCount, 1);
      expect(group.sheets.first.cuts.length, 4);
    });

    test('Prioritizes available remnants before opening full standard sheet', () {
      final pieces = [
        const SheetDemandPiece(
          id: 'p1',
          orderId: 10,
          windowName: 'F1',
          materialType: 'panneau_sandwich',
          color: 'Blanc',
          lengthMm: 800,
          widthMm: 600,
          count: 1,
        ),
      ];

      final standards = [
        {
          'id': 1,
          'material_type': 'panneau_sandwich',
          'name': 'لوح بانو ساندويتش',
          'length_mm': 3000.0,
          'width_mm': 1200.0,
          'allow_rotation': 1,
        }
      ];

      final remnants = [
        {
          'id': 99,
          'ticket_code': 'RM-99',
          'material_type': 'panneau_sandwich',
          'color_name': 'Blanc',
          'length_mm': 1000.0,
          'width_mm': 800.0,
          'allow_rotation': 1,
        }
      ];

      final report = SheetCuttingOptimizerEngine.optimize(
        demandPieces: pieces,
        availableStandardSheets: standards,
        availableRemnants: remnants,
      );

      final group = report.groups['panneau_sandwich__blanc']!;
      expect(group.placedPiecesCount, 1);
      expect(group.remnantsUsedCount, 1);
      expect(group.newSheetsUsedCount, 0);
      expect(group.sheets.first.isFromRemnant, isTrue);
      expect(group.sheets.first.sourceRemnantTicket, 'RM-99');
    });

    test('Respects grain direction when allow_rotation is false', () {
      final pieces = [
        const SheetDemandPiece(
          id: 'p1',
          orderId: 10,
          windowName: 'F1',
          materialType: 'alucobond',
          color: 'Wood',
          lengthMm: 1400,
          widthMm: 800,
          count: 1,
          allowRotation: false,
        ),
      ];

      // A sheet with length 1000 and width 1500 (Piece fits rotated 800x1400, but not without rotation: 1400>1000)
      final standards = [
        {
          'id': 1,
          'material_type': 'alucobond',
          'name': 'لوح',
          'length_mm': 1000.0,
          'width_mm': 1500.0,
          'allow_rotation': 0, // No rotation allowed
        }
      ];

      final report = SheetCuttingOptimizerEngine.optimize(
        demandPieces: pieces,
        availableStandardSheets: standards,
      );

      final group = report.groups['alucobond__wood']!;
      // Piece length 1400 cannot fit on length 1000 without rotation!
      expect(group.placedPiecesCount, 0);
    });
  });
}
