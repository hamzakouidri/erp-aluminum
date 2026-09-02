import 'dart:ui';

import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'multiple frames default to no side cover but allow explicit enable',
    () async {
    final model = WindowModel(
      db: SqlDatabase(),
      width: 500,
      height: 200,
      profileThickness: 10,
    );
    model.zones = [
      WindowZone(
        id: 'left',
        boundary: const Rect.fromLTWH(10, 10, 100, 100),
      ),
      WindowZone(
        id: 'right',
        boundary: const Rect.fromLTWH(250, 10, 100, 100),
      ),
    ];
    model.hasSideCovers = true;

    model.notifyListeners();
    expect(model.getFrameRects(), hasLength(2));
    expect(model.hasSideCovers, isFalse);

    await model.toggleSideCovers(true);
    expect(model.hasSideCovers, isTrue);

    model.notifyListeners();
    expect(model.hasSideCovers, isTrue);
    },
  );
}
