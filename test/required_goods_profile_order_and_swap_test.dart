import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/profile_display_order.dart';
import 'package:database_data/Commande/order_required_goods_screen.dart';
import 'package:database_data/Commande/required_goods_profile_swap.dart';
import 'package:flutter_test/flutter_test.dart';

BomItem _profile(
  String originalName, {
  String? roleKey,
  String? selectorType,
}) => BomItem(
  category: 'profile',
  originalName: originalName,
  name: originalName,
  quantity: 1,
  unit: 'قطاع',
  unitPrice: 0,
  roleKey: roleKey,
  selectorType: selectorType,
);

int _rank(BomItem bom) => profileDisplayRank(
  roleKey: bom.roleKey,
  selectorType: bom.selectorType,
  originalName: bom.originalName,
);

AggregatedGoodItem _good(String name, int rank, {String? color}) =>
    AggregatedGoodItem(
      name: name,
      originalName: name,
      category: 'profile',
      unit: 'قطاع',
      unitPrice: 0,
      totalQuantity: 1,
      totalCost: 0,
      colorName: color,
      profileRank: rank,
    );

void main() {
  group('shared profile display order', () {
    test('lists the profiles in the workshop order', () {
      final shuffled = [
        _profile('Other profile', roleKey: 'other_profile'),
        _profile('بلانت (Plinthe)', roleKey: 'plant'),
        _profile('حديد التقسيم (Renfort Mullion)', roleKey: 'renfort'),
        _profile('التقسيم (Mullion)', roleKey: 'mullion'),
        _profile('باكيت الزجاج (Parclose)', roleKey: 'glazing_bead'),
        _profile('الباتمو (Batmo)', roleKey: 'batmo'),
        _profile('مكمل الضلفة', roleKey: 'sash_extension'),
        _profile('حديد الظلفة (Renfort Sash)', roleKey: 'renfort'),
        _profile('الظلفة (Sash)', selectorType: 'sash'),
        _profile('كومبليمو دورمو (Complément Dormant)',
            roleKey: 'frame_extension'),
        _profile('الغطاء الجانبي (Side Cover)', selectorType: 'side_cover'),
        _profile('حديد الإطار (Renfort Frame)', roleKey: 'renfort'),
        _profile('الإطار (Frame)', selectorType: 'frame'),
      ];
      final ordered = sortedByProfileDisplayRank(shuffled, _rank)
          .map((bom) => bom.originalName)
          .toList();
      expect(ordered, [
        'الإطار (Frame)',
        'حديد الإطار (Renfort Frame)',
        'الغطاء الجانبي (Side Cover)',
        'كومبليمو دورمو (Complément Dormant)',
        'الظلفة (Sash)',
        'حديد الظلفة (Renfort Sash)',
        'مكمل الضلفة',
        'الباتمو (Batmo)',
        'باكيت الزجاج (Parclose)',
        'التقسيم (Mullion)',
        'حديد التقسيم (Renfort Mullion)',
        'بلانت (Plinthe)',
        'Other profile',
      ]);
    });

    test('recognises legacy rows by their name', () {
      expect(_rank(_profile('الإطار')), profileRankFrame);
      expect(_rank(_profile('Parclose 20')), profileRankParclose);
      expect(_rank(_profile('قائم جانبي (Lateral)')), profileRankSash);
      expect(_rank(_profile('Porte-joint')), profileRankPlinthe);
    });

    test('covers and screws of a profile are not that profile', () {
      expect(
        _rank(_profile('Cache renfort', roleKey: 'cache_renfort')),
        profileRankOther,
      );
      expect(
        _rank(_profile('بوشون باتمو', roleKey: 'bouchon_batmo')),
        profileRankOther,
      );
    });

    test('equal ranks keep their original order', () {
      final rows = [
        _profile('B', roleKey: 'other_profile'),
        _profile('A', roleKey: 'other_profile'),
      ];
      expect(
        sortedByProfileDisplayRank(rows, _rank).map((b) => b.originalName),
        ['B', 'A'],
      );
    });

    test('required goods put the role before the colour', () {
      final goods = [
        _good('Sash white', profileRankSash, color: 'أبيض'),
        _good('Frame wood', profileRankFrame, color: 'خشبي'),
        _good('Frame white', profileRankFrame, color: 'أبيض'),
      ]..sort(
          (a, b) => compareRequiredGoods(
            a,
            b,
            colourSortKey: (item) => item.colorName == 'أبيض' ? '0' : '1',
          ),
        );
      expect(goods.map((g) => g.name), [
        'Frame white',
        'Frame wood',
        'Sash white',
      ]);
    });
  });

  group('profile replacement alternatives', () {
    test('a row offers only the profiles of its own role', () {
      expect(
        profileSwapRoleKeys(_profile('الإطار (Frame)', selectorType: 'frame')),
        ['frame'],
      );
      expect(
        profileSwapRoleKeys(_profile('الظلفة (Sash)', selectorType: 'sash')),
        ['sash'],
      );
      expect(
        profileSwapRoleKeys(
          _profile('باكيت الزجاج (Parclose)', roleKey: 'glazing_bead'),
        ),
        ['glazing_bead'],
      );
      expect(
        profileSwapRoleKeys(_profile('Parclose', selectorType: 'parclose')),
        ['glazing_bead'],
      );
      expect(
        profileSwapRoleKeys(
          _profile('الغطاء الجانبي (Side Cover)', selectorType: 'side_cover'),
        ),
        ['side_cover'],
      );
      expect(
        profileSwapRoleKeys(_profile('قائم جانبي', roleKey: 'sash_lateral')),
        ['sash_lateral', 'sash_lateral_reinforced'],
      );
    });

    test('a row whose role is unknown offers nothing', () {
      expect(profileSwapRoleKeys(_profile('Unknown thing')), isEmpty);
    });

    test('a PVC profile never replaces an aluminium one', () {
      expect(
        profileSwapMaterialMatches({'material_type': 'PVC'}, 'Aluminium'),
        isFalse,
      );
      expect(
        profileSwapMaterialMatches({'material_type': 'aluminium'}, 'PVC'),
        isFalse,
      );
      expect(
        profileSwapMaterialMatches({'material_type': 'Aluminium'}, 'Aluminium'),
        isTrue,
      );
      expect(profileSwapMaterialMatches({'material_type': 'both'}, 'PVC'),
          isTrue);
      expect(profileSwapMaterialMatches(const {}, 'PVC'), isTrue);
    });
  });

  group('side cover after a frame swap', () {
    const takesCover = <String, dynamic>{
      'name': 'Cadre 40',
      'allows_side_cover': 1,
    };
    const noCover = <String, dynamic>{
      'name': 'Cadre 50',
      'allows_side_cover': 0,
    };
    const builtIn = <String, dynamic>{
      'name': 'Cadre monobloc',
      'couvre_joint_width': 30,
    };

    test('a frame without a separate cover removes it', () {
      expect(
        sideCoversAfterFrameSwap(
          hadSideCovers: true,
          oldFrame: takesCover,
          newFrame: noCover,
        ),
        isFalse,
      );
    });

    test('the reverse swap adds the side cover', () {
      expect(
        sideCoversAfterFrameSwap(
          hadSideCovers: false,
          oldFrame: noCover,
          newFrame: takesCover,
        ),
        isTrue,
      );
    });

    test('a built-in cover frame always shows its cover', () {
      expect(
        sideCoversAfterFrameSwap(
          hadSideCovers: false,
          oldFrame: takesCover,
          newFrame: builtIn,
        ),
        isTrue,
      );
    });

    test('between two frames taking a cover the drawing keeps its choice', () {
      expect(
        sideCoversAfterFrameSwap(
          hadSideCovers: false,
          oldFrame: takesCover,
          newFrame: takesCover,
        ),
        isFalse,
      );
      expect(
        sideCoversAfterFrameSwap(
          hadSideCovers: true,
          oldFrame: takesCover,
          newFrame: takesCover,
        ),
        isTrue,
      );
    });
  });
}
