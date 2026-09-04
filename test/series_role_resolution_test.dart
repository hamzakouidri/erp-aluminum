import 'package:database_data/Commande/Systeme/profile_selector_dialog.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';

class _RoleDatabase extends SqlDatabase {
  _RoleDatabase({required this.roles, required this.sections});

  final List<Map<String, dynamic>> roles;
  final List<Map<String, dynamic>> sections;

  @override
  Future<List<Map<String, dynamic>>> getSeriesDesignRoles(int seriesId) async =>
      roles;

  @override
  Future<List<Map<String, dynamic>>> getDesignSectionsForRoles(
    int seriesId,
    Iterable<String> roleKeys, {
    bool requireDialog = true,
    bool requireQuantity = false,
  }) async {
    final accepted = roleKeys.toSet();
    return roles
        .where((role) => accepted.contains(role['role_key']))
        .map(
          (role) => sections.firstWhere(
            (section) => section['id'] == role['section_id'],
          ),
        )
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> readSectionsBySeries(int seriesId) async =>
      sections;
}

void main() {
  test('a configured sash role returns only its configured section', () async {
    final database = _RoleDatabase(
      roles: [
        {
          'role_key': 'frame',
          'section_id': 1,
          'is_visible': 1,
          'show_in_dialog': 1,
          'show_in_quantity': 1,
        },
        {
          'role_key': 'sash',
          'section_id': 2,
          'is_visible': 1,
          'show_in_dialog': 1,
          'show_in_quantity': 1,
        },
      ],
      sections: [
        {
          'id': 1,
          'code': 'F1',
          'name': 'Frame',
          'type': 'frame',
          'is_frame': 1,
        },
        {'id': 2, 'code': 'TPL', 'name': 'TPR sash TPL', 'type': 'sash'},
        {'id': 3, 'code': 'S2', 'name': 'TPR sash alternative', 'type': 'sash'},
      ],
    );

    final result = await CatalogCandidateResolver(database: database).resolve(
      const CatalogCandidateQuery(
        category: 'profile',
        selectorType: 'sash',
        seriesId: 67000,
      ),
    );

    expect(result.map((row) => row['code']), <String>['TPL']);
  });

  test(
    'a missing role does not infer a section from legacy metadata',
    () async {
      final database = _RoleDatabase(
        roles: [
          {
            'role_key': 'frame',
            'section_id': 1,
            'is_visible': 1,
            'show_in_dialog': 1,
            'show_in_quantity': 1,
          },
        ],
        sections: [
          {
            'id': 1,
            'code': 'F1',
            'name': 'Frame',
            'type': 'frame',
            'is_frame': 1,
          },
          {'id': 2, 'code': 'TPL', 'name': 'TPR sash TPL', 'type': 'sash'},
        ],
      );

      final result = await CatalogCandidateResolver(database: database).resolve(
        const CatalogCandidateQuery(
          category: 'profile',
          selectorType: 'sash',
          seriesId: 67000,
        ),
      );

      expect(result, isEmpty);
    },
  );

  test('global catalogue rules do not leak into unrelated series', () {
    expect(
      catalogRuleMatchesExactScope(
        {'series_id': null, 'role_key': 'gache_simple'},
        67000,
      ),
      isFalse,
    );
    expect(
      catalogRuleMatchesExactScope(
        {'series_id': null, 'role_key': 'kit_screw'},
        67000,
      ),
      isTrue,
    );
    expect(
      catalogRuleMatchesExactScope(
        {'series_id': 67000, 'role_key': 'gache_simple'},
        67000,
      ),
      isTrue,
    );
  });

  test('series role cover rules override the base section capability', () {
    final section = AluminumSection.fromMap({
      'id': 12,
      'series_id': 67000,
      'code': 'ATPR-F',
      'name': 'ATPR frame',
      'type': 'frame',
      'allows_side_cover': 1,
      'design_allows_side_cover': 0,
    });

    expect(section.allowsSideCover, isFalse);
  });
}
