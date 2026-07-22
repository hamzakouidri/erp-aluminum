import 'dart:io';

void main() {
  String content = File('lib/Screen/achat_details_screen.dart').readAsStringSync();
  
  String target = """
    final XFile? pickedImage = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
    );
""";
  String replacement = """
    final XFile? pickedImage = await ImagePicker().pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 1080,
    );
""";
  if (content.contains(target)) {
    content = content.replaceFirst(target, replacement);
  }

  File('lib/Screen/achat_details_screen.dart').writeAsStringSync(content);
  print("Updated image picker compression.");
}
