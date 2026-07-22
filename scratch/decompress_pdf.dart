import 'dart:io';

void main() {
  final file = File("test_invoice_10.pdf");
  if (!file.existsSync()) {
    print("test_invoice_10.pdf not found!");
    return;
  }
  final bytes = file.readAsBytesSync();
  final out = StringBuffer();

  int i = 0;
  while (i < bytes.length - 6) {
    // Look for "stream" keyword
    if (bytes[i] == 115 && // s
        bytes[i+1] == 116 && // t
        bytes[i+2] == 114 && // r
        bytes[i+3] == 101 && // e
        bytes[i+4] == 97 && // a
        bytes[i+5] == 109) { // m
      
      // Found stream!
      // Let's find "endstream"
      int streamStart = i + 6;
      // Skip whitespace after "stream"
      while (streamStart < bytes.length && (bytes[streamStart] == 10 || bytes[streamStart] == 13)) {
        streamStart++;
      }
      
      int endStream = -1;
      for (int j = streamStart; j < bytes.length - 9; j++) {
        if (bytes[j] == 101 && // e
            bytes[j+1] == 110 && // n
            bytes[j+2] == 100 && // d
            bytes[j+3] == 115 && // s
            bytes[j+4] == 116 && // t
            bytes[j+5] == 114 && // r
            bytes[j+6] == 101 && // e
            bytes[j+7] == 97 && // a
            bytes[j+8] == 109) { // m
          endStream = j;
          break;
        }
      }
      
      if (endStream != -1) {
        final streamBytes = bytes.sublist(streamStart, endStream);
        try {
          final decompressed = zlib.decode(streamBytes);
          final text = String.fromCharCodes(decompressed);
          out.writeln("=== STREAM [Length: ${streamBytes.length} -> Decompressed: ${decompressed.length}] ===");
          out.writeln(text);
        } catch (_) {
          // Probably image bytes or not zlib compressed
        }
        i = endStream + 9;
        continue;
      }
    }
    i++;
  }
  
  File("decompressed_pdf.txt").writeAsStringSync(out.toString());
  print("Decompressed streams saved to decompressed_pdf.txt");
}
