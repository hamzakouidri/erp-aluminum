import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  var databaseFactory = databaseFactoryFfi;
  String path = await databaseFactory.getDatabasesPath();
  print('Databases path: $path');
  
  var dir = Directory(path);
  if (dir.existsSync()) {
    print('Databases found:');
    var files = dir.listSync();
    for (var file in files) {
      if (file is File) {
        print('${file.path} - ${file.lengthSync()} bytes');
      }
    }
  } else {
    print('Directory does not exist: $path');
  }
}
