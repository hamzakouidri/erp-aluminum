import 'dart:io';
import 'package:path/path.dart' as p;

void main() async {
  final userHome = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
  final searchPaths = [
    p.join(userHome, 'AppData', 'Local', 'database_data'),
    p.join(userHome, 'AppData', 'Local', 'com.example', 'database_data'),
    p.join(userHome, 'AppData', 'Roaming', 'database_data'),
    p.join(userHome, 'AppData', 'Local', 'database_data', 'databases'),
    p.join(userHome, 'AppData', 'Local', 'com.example', 'database_data', 'databases'),
  ];

  for (var sp in searchPaths) {
    var dir = Directory(sp);
    if (dir.existsSync()) {
      print('Found folder: $sp');
      var list = dir.listSync();
      for (var f in list) {
        print('  - ${f.path}');
      }
    }
  }
}
