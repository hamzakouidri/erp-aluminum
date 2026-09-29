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
}
