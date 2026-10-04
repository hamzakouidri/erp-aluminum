import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/Commande/pdf_fiche_coupe_api.dart';
import 'package:database_data/sql_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generateFicheCoupe respects passed language (French)', () async {
    SharedPreferences.setMockInitialValues({
      'app_language': AppLanguage.french.index,
    });

    final order = {
      'id': 101,
      'firstname': 'Jean',
      'lastname': 'Dupont',
      'created_at': '2026-09-28',
      'username': 'Admin',
    };

    final bytes = await PdfFicheCoupeApi.generateFicheCoupe(
      order: order,
      items: [],
      workshopName: 'Atelier Aluminium',
      db: SqlDatabase(),
      language: AppLanguage.french,
    );

    expect(bytes, isNotNull);
    expect(bytes.isNotEmpty, isTrue);
  });

  test('generateFicheCoupe respects passed language (Arabic)', () async {
    SharedPreferences.setMockInitialValues({
      'app_language': AppLanguage.arabic.index,
    });

    final order = {
      'id': 102,
      'firstname': 'محمد',
      'lastname': 'علي',
      'created_at': '2026-09-28',
      'username': 'المدير',
    };

    final bytes = await PdfFicheCoupeApi.generateFicheCoupe(
      order: order,
      items: [],
      workshopName: 'ورشة الألمنيوم',
      db: SqlDatabase(),
      language: AppLanguage.arabic,
    );

    expect(bytes, isNotNull);
    expect(bytes.isNotEmpty, isTrue);
  });

  test('generateFicheCoupe with window and shutter item in French', () async {
    SharedPreferences.setMockInitialValues({
      'app_language': AppLanguage.french.index,
    });

    final order = {
      'id': 103,
      'firstname': 'Client',
      'lastname': 'Test',
      'created_at': '2026-09-28',
      'username': 'Admin',
    };

    final item = {
      'largeur': 1200,
      'hauteur': 1400,
      'quantity': 1,
      'game': 'TPR',
      'color': 'Blanc',
      'window_type': 'Fenêtre',
      'partitions_json': '{"width":1200,"height":1400,"hasShutter":true,"shutterBoxHeight":165,"zones":[{"content":"slidingSash","slidingSashesCount":2}]}',
    };

    final bytes = await PdfFicheCoupeApi.generateFicheCoupe(
      order: order,
      items: [item],
      workshopName: 'Atelier Aluminium',
      db: SqlDatabase(),
      language: AppLanguage.french,
    );

    expect(bytes, isNotNull);
    expect(bytes.isNotEmpty, isTrue);
  });

  test('generateFicheCoupe with window and shutter item in Arabic', () async {
    SharedPreferences.setMockInitialValues({
      'app_language': AppLanguage.arabic.index,
    });

    final order = {
      'id': 104,
      'firstname': 'أحمد',
      'lastname': 'بن علي',
      'created_at': '2026-09-28',
      'username': 'المسؤول',
    };

    final item = {
      'largeur': 1200,
      'hauteur': 1400,
      'quantity': 1,
      'game': 'TPR',
      'color': 'أبيض',
      'window_type': 'نافذة',
      'partitions_json': '{"width":1200,"height":1400,"hasShutter":true,"shutterBoxHeight":165,"zones":[{"content":"slidingSash","slidingSashesCount":2}]}',
    };

    final bytes = await PdfFicheCoupeApi.generateFicheCoupe(
      order: order,
      items: [item],
      workshopName: 'ورشة الألمنيوم والزجاج',
      db: SqlDatabase(),
      language: AppLanguage.arabic,
    );

    expect(bytes, isNotNull);
    expect(bytes.isNotEmpty, isTrue);
  });
}
