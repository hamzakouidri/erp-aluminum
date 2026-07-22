import 'dart:io';

void main() {
  final file = File("test_invoice_10.pdf");
  if (!file.existsSync()) {
    print("test_invoice_10.pdf does not exist!");
    return;
  }
  final bytes = file.readAsBytesSync();
  print("PDF bytes length: ${bytes.length}");
  
  // Parse PDF basic structure to find "/Page" count
  final content = String.fromCharCodes(bytes);
  final pageMatches = RegExp(r'/Type\s*/Page\b').allMatches(content);
  print("Found /Page markers: ${pageMatches.length}");

  // Print raw content snippets around /Page to understand what pages exist
  print("Done checking.");
}
