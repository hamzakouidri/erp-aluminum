import 'dart:io';

import 'package:database_data/services/price_sync_service.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TemporaryPaths extends PathProviderPlatform {
  _TemporaryPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('profile and series publications apply on the workshop', () async {
    final directory = await Directory.systemTemp.createTemp('erp_price_pub_');
    final originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TemporaryPaths(directory.path);
    SharedPreferences.setMockInitialValues({});
    SqlDatabase.resetDb();
    final sqlDb = SqlDatabase();
    final connection = await sqlDb.initDb();
    addTearDown(() async {
      await connection.close();
      SqlDatabase.resetDb();
      PathProviderPlatform.instance = originalPaths;
      await directory.delete(recursive: true);
    });

    final profileId = await connection.insert('Profile', {
      'name': 'Profile',
      'type': 'Aluminium',
    });
    final seriesId = await connection.insert('Series', {
      'profile_id': profileId,
      'name': 'Series',
      'type': 'Coulissant',
      'price_per_meter': 100.0,
    });
    // The workshop already has a colour price row for this series.
    await connection.insert('SeriesColorPrices', {
      'series_id': seriesId,
      'color_id': 1,
      'price': 50.0,
    });

    final service = PriceSyncService.instance;
    final series = await service.applyPricePayload('series', {
      'Series': [
        {'id': seriesId, 'price_per_meter': 2500},
      ],
      'SeriesColorPrices': [
        {'series_id': seriesId, 'color_id': 1, 'price': 2600},
        {'series_id': seriesId, 'color_id': 2, 'price': 2700.5},
      ],
    });
    expect(series.updated, 3);
    expect(
      (await connection.query(
        'Series',
        where: 'id = ?',
        whereArgs: [seriesId],
      )).single['price_per_meter'],
      2500.0,
    );
    final colorRows = await connection.query(
      'SeriesColorPrices',
      where: 'series_id = ?',
      whereArgs: [seriesId],
      orderBy: 'color_id',
    );
    expect(colorRows.map((r) => r['price']), [2600.0, 2700.5]);

    final profiles = await service.applyPricePayload('profiles', {
      'SectionColorPrices': [
        {'section_id': 7, 'color_id': 1, 'price': 1100},
      ],
    });
    expect(profiles.updated, 1);

    // A price the manager typed is kept unless asked otherwise.
    await sqlDb.setSectionColorPrice(7, 1, 1200.0);
    final keep = await service.applyPricePayload('profiles', {
      'SectionColorPrices': [
        {'section_id': 7, 'color_id': 1, 'price': 1300},
      ],
    });
    expect(keep.kept, 1);
    final sectionPrice = (await connection.query(
      'SectionColorPrices',
      where: 'section_id = 7 AND color_id = 1',
    )).single['price'];
    expect(sectionPrice, 1200.0);

    // Each price page is its own category: accepting the shutter
    // components page never changes the m² selling prices, and vice versa.
    await connection.insert('ShutterSqmPrices', {
      'blade_type': 'Lame 40',
      'color_id': 1,
      'price_per_sqm': 3000.0,
    });
    final components = await service.applyPricePayload('shutters', {
      'ShutterSqmPrices': [
        {'blade_type': 'Lame 40', 'color_id': 1, 'price_per_sqm': 9999},
      ],
    });
    expect(components.updated, 0);
    final sqm = await service.applyPricePayload('shutter_sqm', {
      'ShutterSqmPrices': [
        {'blade_type': 'Lame 40', 'color_id': 1, 'price_per_sqm': 3500},
      ],
    });
    expect(sqm.updated, 1);
    expect(
      (await connection.query('ShutterSqmPrices')).single['price_per_sqm'],
      3500.0,
    );

    // Accepted base prices survive a catalogue refresh.
    await sqlDb.importGlobalCatalog({
      'Series': [
        {
          'id': seriesId,
          'profile_id': profileId,
          'name': 'Series',
          'type': 'Coulissant',
          'price_per_meter': 100.0,
        },
      ],
    });
    expect(
      (await connection.query(
        'Series',
        where: 'id = ?',
        whereArgs: [seriesId],
      )).single['price_per_meter'],
      2500.0,
    );
  });

  test('mosquito-net m² prices are their own category', () async {
    final directory = await Directory.systemTemp.createTemp('erp_price_mq_');
    final originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TemporaryPaths(directory.path);
    SharedPreferences.setMockInitialValues({});
    SqlDatabase.resetDb();
    final connection = await SqlDatabase().initDb();
    addTearDown(() async {
      await connection.close();
      SqlDatabase.resetDb();
      PathProviderPlatform.instance = originalPaths;
      await directory.delete(recursive: true);
    });

    // One payload carrying both kinds, as an older shutter m² publication.
    final payload = {
      'ShutterSqmPrices': [
        {'blade_type': 'Lame 39', 'color_id': 1, 'price_per_sqm': 4000},
        {'blade_type': 'Moustiquaire_Sqm', 'color_id': 1, 'price_per_sqm': 2500},
        {
          'blade_type': 'Moustiquaire_plissee',
          'color_id': 1,
          'price_per_sqm': 3200,
        },
      ],
    };
    Future<Map<String, double>> prices() async => {
      for (final row in await connection.query('ShutterSqmPrices'))
        row['blade_type'] as String: (row['price_per_sqm'] as num).toDouble(),
    };

    final service = PriceSyncService.instance;
    final mosquito = await service.applyPricePayload('moustiquaire', payload);
    expect(mosquito.updated, 2);
    expect(await prices(), {
      'Moustiquaire_Sqm': 2500.0,
      'Moustiquaire_plissee': 3200.0,
    });

    final shutter = await service.applyPricePayload('shutter_sqm', payload);
    expect(shutter.updated, 1);
    expect((await prices())['Lame 39'], 4000.0);
  });
}
