import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  final url = Uri.parse('https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-2.4.6/sqlite3.wasm');
  print('Downloading sqlite3.wasm from $url...');
  try {
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final destDir = Directory('web');
      if (!destDir.existsSync()) {
        destDir.createSync(recursive: true);
      }
      final file = File('web/sqlite3.wasm');
      await file.writeAsBytes(response.bodyBytes);
      print('Successfully saved sqlite3.wasm to web/sqlite3.wasm (${response.bodyBytes.length} bytes)');
    } else {
      print('Failed to download: HTTP status ${response.statusCode}');
    }
  } catch (e) {
    print('Error: $e');
  }
}
