import 'package:database_data/services/gemini_live_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a native-audio model holds the live call, newest first', () {
    expect(
      GeminiLiveSession.pickModel([
        'gemini-2.0-flash-live-001',
        'gemini-2.5-flash-native-audio-preview-09-2025',
        'gemini-3.0-flash-native-audio-preview',
        'gemini-2.5-flash-live-preview',
      ]),
      'gemini-3.0-flash-native-audio-preview',
    );
  });

  test('without a model list the known live model is used', () {
    expect(GeminiLiveSession.pickModel([]), GeminiLiveSession.fallbackModel);
  });
}
