import 'dart:io';

void main() {
  final files = [
    'assets/images/wood_texture.png',
    'assets/images/wood_texture_antique.png',
    'assets/images/wood_texture_d0.png',
  ];

  for (final path in files) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    
    // Simple JPEG SOF parser
    int i = 2; // skip SOI marker
    int width = 0;
    int height = 0;
    while (i < bytes.length - 1) {
      if (bytes[i] == 0xFF) {
        final marker = bytes[i + 1];
        if (marker == 0xD9) break; // EOI
        if (marker >= 0xC0 && marker <= 0xC3) {
          // SOF marker
          // Length is next 2 bytes
          final length = (bytes[i + 2] << 8) | bytes[i + 3];
          // Precision: bytes[i + 4]
          // Height is next 2 bytes: bytes[i + 5], bytes[i + 6]
          height = (bytes[i + 5] << 8) | bytes[i + 6];
          // Width is next 2 bytes: bytes[i + 7], bytes[i + 8]
          width = (bytes[i + 7] << 8) | bytes[i + 8];
          break;
        } else {
          // Skip segment
          final length = (bytes[i + 2] << 8) | bytes[i + 3];
          i += 2 + length;
        }
      } else {
        i++;
      }
    }
    print('$path: ${width}x${height}, size: ${bytes.length} bytes');
  }
}
