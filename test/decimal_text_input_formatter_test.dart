import 'package:database_data/utils/decimal_text_input_formatter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue _format(String text, {int decimalDigits = 2}) {
  return DecimalTextInputFormatter(
    decimalDigits: decimalDigits,
  ).formatEditUpdate(
    TextEditingValue.empty,
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    ),
  );
}

void main() {
  test('rejects letters and keeps only a valid number', () {
    expect(_format('1a00 دج').text, '100');
  });

  test('normalizes the first decimal separator and rejects later ones', () {
    expect(_format('1000,25.8').text, '1000.25');
    expect(_format('1000،25').text, '1000.25');
    expect(_format('1000٫25').text, '1000.25');
  });

  test('supports Arabic digits', () {
    expect(_format('١٠٠٠،٢٥').text, '1000.25');
  });

  test('limits quantity precision independently', () {
    expect(_format('12.3459', decimalDigits: 3).text, '12.345');
  });

  test('prefixes a leading decimal separator with zero', () {
    expect(_format('.25').text, '0.25');
  });
}
