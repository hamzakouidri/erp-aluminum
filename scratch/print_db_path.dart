import 'package:sqflite_common_ffi/sqflite_ffi.dart';
void main() async {
  sqfliteFfiInit();
  var path = await databaseFactoryFfi.getDatabasesPath();
  print('DB PATH: ' + path);
}
