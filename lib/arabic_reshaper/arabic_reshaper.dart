import 'reshaper_config.dart';
import 'letters.dart';
import 'ligatures.dart';

// Helper class for reshaped characters in processing
class _ReshapedChar {
  String letter;
  int form;
  _ReshapedChar(this.letter, this.form);
}

class ArabicReshaper {
  static ArabicReshaper? _instance;
  static ArabicReshaper get instance {
    _instance ??= ArabicReshaper();
    return _instance!;
  }

  final ArabicReshaperConfig configuration;
  final Map<String, List<String>> _letters;

  // Cache for Ligature Regex and Forms
  RegExp? _ligaturesRegex;
  Map<int, List<String>>? _groupIndexToForms;

  // Regex to detect Harakat (Tashkeel)
  static final RegExp _harakatRegex = RegExp(
    '[\u0610-\u061a\u064b-\u065f\u0670\u06d6-\u06dc\u06df-\u06e8\u06ea-\u06ed\u08d4-\u08e1\u08d4-\u08ed\u08e3-\u08ff]',
    unicode: true,
  );
  // Regex to detect if text contains Arabic characters (Standard & Extended)
  static final RegExp _arabicBlockRegex = RegExp(
    r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]',
    unicode: true,
  );

  ArabicReshaper({this.configuration = const ArabicReshaperConfig()})
    : _letters = LETTERS_ARABIC;

  /// Checks if the given text contains any Arabic characters.
  static bool isArabic(String text) {
    return _arabicBlockRegex.hasMatch(text);
  }

  /// Lazily builds the combined Regex for all enabled ligatures.
  void _initLigatures() {
    if (_ligaturesRegex != null) return;

    final patterns = <String>[];
    _groupIndexToForms = {};
    int index =
        0; // Regex group index (0-based in Dart list, but RegExp groups are 1-based)

    // LIGATURES is the list from ligatures.dart
    for (final lig in LIGATURES) {
      if (configuration.isLigatureEnabled(lig.name)) {
        // We wrap the match in () to create a capture group.
        patterns.add('(${lig.match})');
        _groupIndexToForms![index] = lig.replacement;
        index++;
      }
    }

    if (patterns.isNotEmpty) {
      // Create one giant regex: (Ligature1)|(Ligature2)|...
      _ligaturesRegex = RegExp(patterns.join('|'), unicode: true);
    }
  }

  List<String>? _getLigatureForms(int groupIndex) {
    if (_groupIndexToForms == null) return null;
    return _groupIndexToForms![groupIndex];
  }

  /// Main Reshape Function
  String reshape(String text) {
    if (text.isEmpty) return '';

    final output = <_ReshapedChar>[];
    final int notSupported = -1;

    // Config flags
    final bool deleteHarakat = configuration.deleteHarakat;
    final bool deleteTatweel = configuration.deleteTatweel;
    final bool supportZwj = configuration.supportZwj;
    final bool shiftHarakat = configuration.shiftHarakatPosition;
    final bool useUnshaped = configuration.useUnshapedInsteadOfIsolated;

    final positionsHarakat = <int, List<String>>{};

    final int isolatedForm = useUnshaped ? UNSHAPED : ISOLATED;

    // ---------------------------------------------------------
    // 1. FIRST PASS: Basic Shaping (Contextual Analysis)
    // ---------------------------------------------------------
    for (int i = 0; i < text.characters.length; i++) {
      final letter = text.characters.elementAt(i);

      if (_harakatRegex.hasMatch(letter)) {
        if (!deleteHarakat) {
          int position = output.length - 1;
          if (shiftHarakat) {
            position -= 1;
          }
          positionsHarakat.putIfAbsent(position, () => []);
          if (shiftHarakat) {
            positionsHarakat[position]!.insert(0, letter);
          } else {
            positionsHarakat[position]!.add(letter);
          }
        }
        continue;
      } else if (letter == TATWEEL && deleteTatweel) {
        continue;
      } else if (letter == ZWJ && !supportZwj) {
        continue;
      }

      // Check if letter exists in our database
      if (!_letters.containsKey(letter)) {
        output.add(_ReshapedChar(letter, notSupported));
      } else if (output.isEmpty) {
        // First letter
        output.add(_ReshapedChar(letter, isolatedForm));
      } else {
        final previous = output.last;

        if (previous.form == notSupported) {
          output.add(_ReshapedChar(letter, isolatedForm));
        } else if (!connectsWithLetterBefore(letter, _letters)) {
          output.add(_ReshapedChar(letter, isolatedForm));
        } else if (!connectsWithLetterAfter(previous.letter, _letters)) {
          output.add(_ReshapedChar(letter, isolatedForm));
        } else if (previous.form == FINAL &&
            !connectsWithLettersBeforeAndAfter(previous.letter, _letters)) {
          output.add(_ReshapedChar(letter, isolatedForm));
        } else if (previous.form == isolatedForm) {
          // Prev was Isolated, now it connects to this -> Prev becomes Initial
          previous.form = INITIAL;
          output.add(_ReshapedChar(letter, FINAL));
        } else {
          // Prev connects to this -> Prev becomes Medial
          previous.form = MEDIAL;
          output.add(_ReshapedChar(letter, FINAL));
        }
      }

      // Remove ZWJ if it's the second to last item
      if (supportZwj &&
          output.length > 1 &&
          output[output.length - 2].letter == ZWJ) {
        output.removeAt(output.length - 2);
      }
    }

    if (supportZwj && output.isNotEmpty && output.last.letter == ZWJ) {
      output.removeLast();
    }

    // ---------------------------------------------------------
    // 2. SECOND PASS: Ligatures (Lam-Alef, Allah, etc.)
    // ---------------------------------------------------------
    if (configuration.supportLigatures) {
      _initLigatures();
      if (_ligaturesRegex != null) {
        // We need to run the regex on the "Clean" text (no harakat, no tatweel)
        // so that indices match the `output` list logic.
        String cleanText = text.replaceAll(_harakatRegex, '');
        if (deleteTatweel) {
          cleanText = cleanText.replaceAll(TATWEEL, '');
        }

        // Find all matches
        final matches = _ligaturesRegex!.allMatches(cleanText).toList();

        // Iterate BACKWARDS to avoid index shifting issues when we replace items
        for (final match in matches.reversed) {
          int groupIndex = -1;

          // Determine which group matched
          // RegExp matches groups are 1-indexed. group(0) is full match.
          for (int g = 0; g < match.groupCount; g++) {
            if (match.group(g + 1) != null) {
              groupIndex = g;
              break;
            }
          }

          if (groupIndex == -1) continue;

          final forms = _getLigatureForms(groupIndex);
          if (forms == null) continue;

          final a = match.start;
          final b = match.end;

          // Check Bounds safety
          if (a >= output.length || b > output.length) continue;

          // Determine Context for Ligature
          final aForm = output[a].form;
          final bForm = output[b - 1].form;
          int ligatureForm = ISOLATED;

          if (aForm == isolatedForm || aForm == INITIAL) {
            if (bForm == isolatedForm || bForm == FINAL) {
              ligatureForm = ISOLATED;
            } else {
              ligatureForm = INITIAL;
            }
          } else {
            if (bForm == isolatedForm || bForm == FINAL) {
              ligatureForm = FINAL;
            } else {
              ligatureForm = MEDIAL;
            }
          }

          if (forms[ligatureForm].isEmpty)
            continue; // Ligature doesn't support this form

          // Perform Replacement
          // 1. Replace the FIRST char of the sequence with the Ligature Char
          output[a] = _ReshapedChar(forms[ligatureForm], notSupported);

          // 2. Mark the rest as empty/deleted
          // We use a loop to set them to empty strings with notSupported form.
          // Later logic will skip them.
          for (int k = a + 1; k < b; k++) {
            output[k] = _ReshapedChar('', notSupported);
          }
        }
      }
    }

    // ---------------------------------------------------------
    // 3. CONSTRUCTION: Build Final String
    // ---------------------------------------------------------
    final result = StringBuffer();

    // Check Harakat at position -1 (Start of string)
    if (!deleteHarakat && positionsHarakat.containsKey(-1)) {
      result.write(positionsHarakat[-1]!.join());
    }

    for (int i = 0; i < output.length; i++) {
      final o = output[i];
      if (o.letter.isNotEmpty) {
        if (o.form == notSupported || o.form == UNSHAPED) {
          result.write(o.letter);
        } else {
          // Look up the form in the letters map
          if (_letters.containsKey(o.letter)) {
            result.write(_letters[o.letter]![o.form]);
          } else {
            result.write(o.letter); // Should not happen if logic is correct
          }
        }
      }

      // Re-insert Harakat
      if (!deleteHarakat && positionsHarakat.containsKey(i)) {
        result.write(positionsHarakat[i]!.join());
      }
    }

    return result.toString();
  }
}

// Extension to get characters (Unicode aware split)
extension StringChars on String {
  Iterable<String> get characters sync* {
    for (var i = 0; i < length; i++) {
      yield this[i];
    }
  }
}
