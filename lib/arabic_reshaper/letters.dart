// Constants
const int UNSHAPED = 255;
const int ISOLATED = 0;
const int INITIAL = 1;
const int MEDIAL = 2;
const int FINAL = 3;

const String TATWEEL = '\u0640';
const String ZWJ = '\u200D';

// Mapping: Char -> [Isolated, Initial, Medial, Final]
// If a form is empty string '', it's not supported.
const Map<String, List<String>> LETTERS_ARABIC = {
  '\u0621': ['\uFE80', '', '', ''],
  '\u0622': ['\uFE81', '', '', '\uFE82'],
  '\u0623': ['\uFE83', '', '', '\uFE84'],
  '\u0624': ['\uFE85', '', '', '\uFE86'],
  '\u0625': ['\uFE87', '', '', '\uFE88'],
  '\u0626': ['\uFE89', '\uFE8B', '\uFE8C', '\uFE8A'],
  '\u0627': ['\uFE8D', '', '', '\uFE8E'],
  '\u0628': ['\uFE8F', '\uFE91', '\uFE92', '\uFE90'],
  '\u0629': ['\uFE93', '', '', '\uFE94'],
  '\u062A': ['\uFE95', '\uFE97', '\uFE98', '\uFE96'],
  '\u062B': ['\uFE99', '\uFE9B', '\uFE9C', '\uFE9A'],
  '\u062C': ['\uFE9D', '\uFE9F', '\uFEA0', '\uFE9E'],
  '\u062D': ['\uFEA1', '\uFEA3', '\uFEA4', '\uFEA2'],
  '\u062E': ['\uFEA5', '\uFEA7', '\uFEA8', '\uFEA6'],
  '\u062F': ['\uFEA9', '', '', '\uFEAA'],
  '\u0630': ['\uFEAB', '', '', '\uFEAC'],
  '\u0631': ['\uFEAD', '', '', '\uFEAE'],
  '\u0632': ['\uFEAF', '', '', '\uFEB0'],
  '\u0633': ['\uFEB1', '\uFEB3', '\uFEB4', '\uFEB2'],
  '\u0634': ['\uFEB5', '\uFEB7', '\uFEB8', '\uFEB6'],
  '\u0635': ['\uFEB9', '\uFEBB', '\uFEBC', '\uFEBA'],
  '\u0636': ['\uFEBD', '\uFEBF', '\uFEC0', '\uFEBE'],
  '\u0637': ['\uFEC1', '\uFEC3', '\uFEC4', '\uFEC2'],
  '\u0638': ['\uFEC5', '\uFEC7', '\uFEC8', '\uFEC6'],
  '\u0639': ['\uFEC9', '\uFECB', '\uFECC', '\uFECA'],
  '\u063A': ['\uFECD', '\uFECF', '\uFED0', '\uFECE'],
  TATWEEL: [TATWEEL, TATWEEL, TATWEEL, TATWEEL],
  '\u0641': ['\uFED1', '\uFED3', '\uFED4', '\uFED2'],
  '\u0642': ['\uFED5', '\uFED7', '\uFED8', '\uFED6'],
  '\u0643': ['\uFED9', '\uFEDB', '\uFEDC', '\uFEDA'],
  '\u0644': ['\uFEDD', '\uFEDF', '\uFEE0', '\uFEDE'],
  '\u0645': ['\uFEE1', '\uFEE3', '\uFEE4', '\uFEE2'],
  '\u0646': ['\uFEE5', '\uFEE7', '\uFEE8', '\uFEE6'],
  '\u0647': ['\uFEE9', '\uFEEB', '\uFEEC', '\uFEEA'],
  '\u0648': ['\uFEED', '', '', '\uFEEE'],
  '\u0649': ['\uFEEF', '\uFBE8', '\uFBE9', '\uFEF0'],
  '\u064A': ['\uFEF1', '\uFEF3', '\uFEF4', '\uFEF2'],
  '\u0671': ['\uFB50', '', '', '\uFB51'],
  '\u0677': ['\uFBDD', '', '', ''],
  '\u0679': ['\uFB66', '\uFB68', '\uFB69', '\uFB67'],
  '\u067A': ['\uFB5E', '\uFB60', '\uFB61', '\uFB5F'],
  '\u067B': ['\uFB52', '\uFB54', '\uFB55', '\uFB53'],
  '\u067E': ['\uFB56', '\uFB58', '\uFB59', '\uFB57'],
  '\u067F': ['\uFB62', '\uFB64', '\uFB65', '\uFB63'],
  '\u0680': ['\uFB5A', '\uFB5C', '\uFB5D', '\uFB5B'],
  '\u0683': ['\uFB76', '\uFB78', '\uFB79', '\uFB77'],
  '\u0684': ['\uFB72', '\uFB74', '\uFB75', '\uFB73'],
  '\u0686': ['\uFB7A', '\uFB7C', '\uFB7D', '\uFB7B'],
  '\u0687': ['\uFB7E', '\uFB80', '\uFB81', '\uFB7F'],
  '\u0688': ['\uFB88', '', '', '\uFB89'],
  '\u068C': ['\uFB84', '', '', '\uFB85'],
  '\u068D': ['\uFB82', '', '', '\uFB83'],
  '\u068E': ['\uFB86', '', '', '\uFB87'],
  '\u0691': ['\uFB8C', '', '', '\uFB8D'],
  '\u0698': ['\uFB8A', '', '', '\uFB8B'],
  '\u06A4': ['\uFB6A', '\uFB6C', '\uFB6D', '\uFB6B'],
  '\u06A6': ['\uFB6E', '\uFB70', '\uFB71', '\uFB6F'],
  '\u06A9': ['\uFB8E', '\uFB90', '\uFB91', '\uFB8F'],
  '\u06AD': ['\uFBD3', '\uFBD5', '\uFBD6', '\uFBD4'],
  '\u06AF': ['\uFB92', '\uFB94', '\uFB95', '\uFB93'],
  '\u06B1': ['\uFB9A', '\uFB9C', '\uFB9D', '\uFB9B'],
  '\u06B3': ['\uFB96', '\uFB98', '\uFB99', '\uFB97'],
  '\u06BA': ['\uFB9E', '', '', '\uFB9F'],
  '\u06BB': ['\uFBA0', '\uFBA2', '\uFBA3', '\uFBA1'],
  '\u06BE': ['\uFBAA', '\uFBAC', '\uFBAD', '\uFBAB'],
  '\u06C0': ['\uFBA4', '', '', '\uFBA5'],
  '\u06C1': ['\uFBA6', '\uFBA8', '\uFBA9', '\uFBA7'],
  '\u06C5': ['\uFBE0', '', '', '\uFBE1'],
  '\u06C6': ['\uFBD9', '', '', '\uFBDA'],
  '\u06C7': ['\uFBD7', '', '', '\uFBD8'],
  '\u06C8': ['\uFBDB', '', '', '\uFBDC'],
  '\u06C9': ['\uFBE2', '', '', '\uFBE3'],
  '\u06CB': ['\uFBDE', '', '', '\uFBDF'],
  '\u06CC': ['\uFBFC', '\uFBFE', '\uFBFF', '\uFBFD'],
  '\u06D0': ['\uFBE4', '\uFBE6', '\uFBE7', '\uFBE5'],
  '\u06D2': ['\uFBAE', '', '', '\uFBAF'],
  '\u06D3': ['\uFBB0', '', '', '\uFBB1'],
  ZWJ: [ZWJ, ZWJ, ZWJ, ZWJ],
};

// Helper Functions

bool connectsWithLetterBefore(String letter, Map<String, List<String>> letters) {
  if (!letters.containsKey(letter)) return false;
  final forms = letters[letter]!;
  // Connects before if it has a Final or Medial form
  return forms[FINAL].isNotEmpty || forms[MEDIAL].isNotEmpty;
}

bool connectsWithLetterAfter(String letter, Map<String, List<String>> letters) {
  if (!letters.containsKey(letter)) return false;
  final forms = letters[letter]!;
  // Connects after if it has an Initial or Medial form
  return forms[INITIAL].isNotEmpty || forms[MEDIAL].isNotEmpty;
}

bool connectsWithLettersBeforeAndAfter(String letter, Map<String, List<String>> letters) {
  if (!letters.containsKey(letter)) return false;
  final forms = letters[letter]!;
  return forms[MEDIAL].isNotEmpty;
}