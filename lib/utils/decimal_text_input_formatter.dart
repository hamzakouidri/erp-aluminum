import 'package:flutter/services.dart';

/// Strict numeric input for prices, quantities and measurements.
///
/// Accepts Western and Arabic digits, normalizes comma/Arabic decimal marks to
/// a single dot, rejects every other character, and limits decimal precision.
class DecimalTextInputFormatter extends TextInputFormatter {
  final int decimalDigits;
  final bool allowNegative;

  const DecimalTextInputFormatter({
    this.decimalDigits = 2,
    this.allowNegative = false,
  });

  static const _arabicDigits = <String, String>{
    '٠': '0',
    '١': '1',
    '٢': '2',
    '٣': '3',
    '٤': '4',
    '٥': '5',
    '٦': '6',
    '٧': '7',
    '٨': '8',
    '٩': '9',
    '۰': '0',
    '۱': '1',
    '۲': '2',
    '۳': '3',
    '۴': '4',
    '۵': '5',
    '۶': '6',
    '۷': '7',
    '۸': '8',
    '۹': '9',
  };

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final buffer = StringBuffer();
    var hasSeparator = false;
    var decimals = 0;
    var acceptedBeforeCursor = 0;

    for (var index = 0; index < newValue.text.length; index++) {
      var character = newValue.text[index];
      character = _arabicDigits[character] ?? character;
      final beforeCursor = index < newValue.selection.extentOffset;
      var accepted = false;

      if (RegExp(r'[0-9]').hasMatch(character)) {
        if (!hasSeparator || decimals < decimalDigits) {
          buffer.write(character);
          if (hasSeparator) decimals++;
          accepted = true;
        }
      } else if (character == '.' ||
          character == ',' ||
          character == '،' ||
          character == '٫') {
        if (!hasSeparator && decimalDigits > 0) {
          if (buffer.isEmpty || buffer.toString() == '-') buffer.write('0');
          buffer.write('.');
          hasSeparator = true;
          accepted = true;
        }
      } else if (character == '-' &&
          allowNegative &&
          buffer.isEmpty &&
          index == 0) {
        buffer.write('-');
        accepted = true;
      }

      if (beforeCursor && accepted) {
        acceptedBeforeCursor = buffer.length;
      }
    }

    final text = buffer.toString();
    final cursor = acceptedBeforeCursor.clamp(0, text.length);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor),
    );
  }
}
