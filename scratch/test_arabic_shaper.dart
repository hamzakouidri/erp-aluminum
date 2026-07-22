import '../lib/arabic_reshaper/arabic_reshaper.dart';

void main() {
  final input = "نافذة منزلقة غرفتين";
  final reshaped = ArabicReshaper.instance.reshape(input);
  
  print("Input text: $input");
  print("Reshaped text: $reshaped");
  
  // Let's print character by character in hex format
  print("Input hex: ${input.runes.map((r) => r.toRadixString(16).toUpperCase().padLeft(4, '0')).toList()}");
  print("Reshaped hex: ${reshaped.runes.map((r) => r.toRadixString(16).toUpperCase().padLeft(4, '0')).toList()}");
}
