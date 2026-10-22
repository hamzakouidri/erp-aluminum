import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

enum TtsState { playing, stopped, paused }

class TtsService {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal();

  FlutterTts? _flutterTts;
  AudioPlayer? _audioPlayer;
  TtsState _ttsState = TtsState.stopped;
  bool _isInitialized = false;
  int _speakSessionId = 0;

  TtsState get ttsState => _ttsState;
  bool get isSpeaking => _ttsState == TtsState.playing;

  final StreamController<TtsState> _stateController =
      StreamController<TtsState>.broadcast();
  Stream<TtsState> get stateStream => _stateController.stream;

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      _audioPlayer = AudioPlayer();
      _audioPlayer!.onPlayerComplete.listen((_) {
        // Handled per session loop
      });

      if (!kIsWeb && !Platform.isWindows) {
        _flutterTts = FlutterTts();
        _flutterTts!.setStartHandler(() {
          _ttsState = TtsState.playing;
          _stateController.add(_ttsState);
        });
        _flutterTts!.setCompletionHandler(() {
          _ttsState = TtsState.stopped;
          _stateController.add(_ttsState);
        });
        _flutterTts!.setCancelHandler(() {
          _ttsState = TtsState.stopped;
          _stateController.add(_ttsState);
        });
        _flutterTts!.setErrorHandler((msg) {
          debugPrint('FlutterTts error: $msg');
          _ttsState = TtsState.stopped;
          _stateController.add(_ttsState);
        });

        await _flutterTts!.setLanguage("ar");
        await _flutterTts!.setSpeechRate(0.5);
        await _flutterTts!.setVolume(1.0);
        await _flutterTts!.setPitch(1.0);
      }

      _isInitialized = true;
    } catch (e) {
      debugPrint('TtsService init failed: $e');
    }
  }

  /// Speaks the provided text in the target language (default 'ar'), stopping any ongoing speech first.
  Future<void> speak(String text, {String languageCode = 'ar'}) async {
    if (text.trim().isEmpty) return;
    await init();
    await stop();

    final cleanText = _sanitizeForSpeech(text);
    if (cleanText.isEmpty) return;

    final currentSession = ++_speakSessionId;
    _ttsState = TtsState.playing;
    _stateController.add(_ttsState);

    // Always use high-quality Google Studio Neural voice stream via AudioPlayer first
    final unspoken = await _speakWithAudioPlayer(
      cleanText,
      currentSession,
      languageCode: languageCode,
    );
    // The online voice reports failure by returning what it could not say
    // (offline, blocked, non-200). Say that part with the device's own engine
    // instead of staying silent.
    if (unspoken.isEmpty || _speakSessionId != currentSession) return;
    debugPrint('Google online TTS failed, falling back to flutter_tts.');
    if (_flutterTts == null) return;
    try {
      await _flutterTts!.setLanguage(languageCode);
      await _flutterTts!.setSpeechRate(0.5);
      await _flutterTts!.setPitch(1.0);
      await _flutterTts!.speak(unspoken);
    } catch (e) {
      debugPrint('flutterTts fallback failed: $e');
      _ttsState = TtsState.stopped;
      _stateController.add(_ttsState);
    }
  }

  /// High quality speech synthesis played via AudioPlayer.
  ///
  /// Returns the text it could not play (empty when everything was said or
  /// the speech was cancelled), so [speak] can hand it to flutter_tts.
  Future<String> _speakWithAudioPlayer(
    String text,
    int sessionId, {
    String languageCode = 'ar',
  }) async {
    final chunks = _splitIntoChunks(text, 140);
    var played = 0;
    try {
      final tempDir = await getTemporaryDirectory();

      for (int i = 0; i < chunks.length; i++) {
        if (_speakSessionId != sessionId) return '';

        final chunk = chunks[i];
        if (chunk.trim().isEmpty) {
          played = i + 1;
          continue;
        }

        final url = Uri.parse(
          'https://translate.google.com/translate_tts?ie=UTF-8&q=${Uri.encodeComponent(chunk)}&tl=$languageCode&client=tw-ob',
        );

        final response = await http
            .get(url, headers: {'User-Agent': 'Mozilla/5.0'})
            .timeout(const Duration(seconds: 8));

        if (_speakSessionId != sessionId) return '';

        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          final tempFile = File(
            p.join(tempDir.path, 'tts_voice_${sessionId}_$i.mp3'),
          );
          await tempFile.writeAsBytes(response.bodyBytes);

          if (_speakSessionId != sessionId) {
            tempFile.delete().ignore();
            return '';
          }

          final completer = Completer<void>();
          late StreamSubscription sub;
          sub = _audioPlayer!.onPlayerComplete.listen((_) {
            sub.cancel();
            if (!completer.isCompleted) completer.complete();
          });

          await _audioPlayer!.play(DeviceFileSource(tempFile.path));
          await completer.future.timeout(
            const Duration(seconds: 25),
            onTimeout: () => null,
          );

          tempFile.delete().ignore();
          played = i + 1;
        } else {
          debugPrint('Google TTS returned HTTP ${response.statusCode}.');
          break;
        }
      }
    } catch (e) {
      debugPrint('TtsService AudioPlayer playback error: $e');
    } finally {
      if (_speakSessionId == sessionId) {
        _ttsState = TtsState.stopped;
        _stateController.add(_ttsState);
      }
    }
    if (_speakSessionId != sessionId) return '';
    return chunks.skip(played).where((c) => c.trim().isNotEmpty).join('. ');
  }

  /// Splits long Arabic text into sensible chunks for the TTS engine
  List<String> _splitIntoChunks(String text, int maxLength) {
    final List<String> chunks = [];
    final sentences = text.split(RegExp(r'[\n\r.،؛!?؟]+'));

    String current = '';
    for (var sentence in sentences) {
      final s = sentence.trim();
      if (s.isEmpty) continue;

      if ((current + ' ' + s).length <= maxLength) {
        current = current.isEmpty ? s : '$current، $s';
      } else {
        if (current.isNotEmpty) {
          chunks.add(current);
        }
        if (s.length > maxLength) {
          // Break very long single sentences by words
          final words = s.split(' ');
          String sub = '';
          for (final w in words) {
            if ((sub + ' ' + w).length <= maxLength) {
              sub = sub.isEmpty ? w : '$sub $w';
            } else {
              if (sub.isNotEmpty) chunks.add(sub);
              sub = w;
            }
          }
          if (sub.isNotEmpty) chunks.add(sub);
          current = '';
        } else {
          current = s;
        }
      }
    }

    if (current.isNotEmpty) {
      chunks.add(current);
    }

    return chunks;
  }

  /// Stops current speech immediately
  Future<void> stop() async {
    _speakSessionId++;
    try {
      if (_audioPlayer != null) {
        await _audioPlayer!.stop();
      }
      if (_flutterTts != null) {
        await _flutterTts!.stop();
      }
    } catch (e) {
      debugPrint('TtsService stop failed: $e');
    } finally {
      _ttsState = TtsState.stopped;
      _stateController.add(_ttsState);
    }
  }

  /// Clean Markdown characters, URLs, emojis, and JSON fragments for smooth voice reading
  String _sanitizeForSpeech(String text) {
    var result = text;
    // Remove markdown code blocks
    result = result.replaceAll(RegExp(r'```[\s\S]*?```'), '');
    // Remove raw JSON keys if leaked
    result = result.replaceAll(
      RegExp(
        r'"?(speech_response|transcribed_text|action_type|detected_language|parameters)"?\s*:\s*',
      ),
      '',
    );
    // Remove emojis and UI decorative symbols
    result = result.replaceAll(
      RegExp(
        r'[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}🔹🔸💰🗣️🎙️🔴•]',
        unicode: true,
      ),
      ' ',
    );
    // Remove markdown headers and bold/italics
    result = result.replaceAll(RegExp(r'[*_#`~]'), '');
    // Remove brackets and parenthetical URLs
    result = result.replaceAll(RegExp(r'\[(.*?)\]\(.*?\)'), r'$1');
    // Remove JSON braces and quotes if any leaked
    result = result.replaceAll(RegExp(r'[{}"\\]'), ' ');
    // Normalize extra whitespace
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
    return result;
  }

  void dispose() {
    _stateController.close();
    _audioPlayer?.dispose();
  }
}
