library speech_to_text_windows;

import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';

export 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart'
    show SpeechListenOptions;

class SpeechToTextWindows extends SpeechToTextPlatform {
  static void registerWith() {
    SpeechToTextPlatform.instance = SpeechToTextWindows();
  }

  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<bool> initialize({
    debugLogging = false,
    List<SpeechConfigOption>? options,
  }) async {
    return false;
  }

  @override
  Future<bool> listen({
    String? localeId,
    @Deprecated('Use SpeechListenOptions.partialResults instead')
    partialResults = true,
    @Deprecated('Use SpeechListenOptions.onDevice instead') onDevice = false,
    @Deprecated('Use SpeechListenOptions.listenMode instead') int listenMode = 0,
    @Deprecated('Use SpeechListenOptions.sampleRate instead') sampleRate = 0,
    SpeechListenOptions? options,
  }) async {
    return false;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}

  @override
  Future<List<dynamic>> locales() async => const [];
}
