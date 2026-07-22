import 'dart:io';
import 'dart:convert';

void main() {
  var file = File('lib/settings/localization.dart');
  var content = file.readAsStringSync();

  // Find all keys that map to objects containing AppLanguage.arabic, french, english
  var regex = RegExp(
    r"r?'''?([^']+)'''?:\s*\{\s*AppLanguage\.arabic:\s*r?'''?([^']+)'''?,\s*AppLanguage\.french:\s*r?'''?([^']+)'''?,\s*AppLanguage\.english:\s*r?'''?([^']+)'''?,",
    dotAll: true,
  );

  var matches = regex.allMatches(content);
  Map<String, String> needsTranslation = {};

  for (var match in matches) {
    var key = match.group(1)!;
    var ar = match.group(2)!;
    var fr = match.group(3)!;
    var en = match.group(4)!;

    // If french and english are exactly the same as arabic, it means they are untranslated
    if (fr == ar && en == ar) {
      needsTranslation[key] = ar;
    }
  }

  print("Found ${needsTranslation.length} untranslated items.");

  // We'll write this to a file
  File(
    'C:/Users/hp/.gemini/antigravity/brain/7af0fd0b-4fa0-4dfa-a76f-e68960420348/scratch/untranslated.json',
  ).writeAsStringSync(jsonEncode(needsTranslation));
}
