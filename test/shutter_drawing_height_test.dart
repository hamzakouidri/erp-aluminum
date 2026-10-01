import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('split shutter may extend below the window', () {
    final model = WindowModel(db: SqlDatabase())
      ..width = 1200
      ..height = 2000
      ..hasShutter = true
      ..isShutterSplit = true
      ..shutterSplits = [
        const ShutterSplitSection(
          width: 1200,
          leftOffset: 0,
          customHeight: 2300,
        ),
      ];

    expect(model.shutterDrawingHeight, 2300);
    expect(model.shutterIsLongerThanWindow, isTrue);
  });

  test('normal shutter does not add a separate V dimension', () {
    final model = WindowModel(db: SqlDatabase())
      ..width = 1200
      ..height = 2000
      ..hasShutter = true;

    expect(model.shutterDrawingHeight, 2000);
    expect(model.shutterIsLongerThanWindow, isFalse);
  });
}
