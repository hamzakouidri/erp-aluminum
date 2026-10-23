import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../settings/app_settings.dart';
import 'ai_agent_service.dart';
import 'gemini_gateway.dart';

enum GeminiLiveState { connecting, listening, thinking, speaking, closed }

/// A real-time voice conversation with Gemini (the Live API), the way the
/// Gemini app talks: the microphone streams to the model, its own voice
/// streams back, and it understands speech directly, with no transcription
/// step in between. It works on the app's data through the same tools,
/// permissions and approvals as [AiAgentService].
///
/// With the server (no personal key) the gemini-live-token Edge Function
/// hands out a one-session token, so the real key never reaches the app.
class GeminiLiveSession {
  GeminiLiveSession({
    required this.agent,
    required this.permissions,
    required this.language,
    required this.confirm,
    this.history = const [],
  });

  final AiAgentService agent;
  final AiAgentPermissions permissions;
  final AppLanguage language;
  final AiConfirm confirm;

  /// Earlier messages of the chat ({'role', 'content'}), so the call picks
  /// up the conversation where the text chat left it.
  final List<Map<String, String>> history;

  final state = ValueNotifier(GeminiLiveState.connecting);

  /// Microphone level from 0 to 1, for the animation.
  final level = ValueNotifier(0.0);

  /// What the user said, as it is heard (a new turn when [newTurn]).
  void Function(String text, {required bool newTurn})? onUserSpeech;

  /// What the model says, as it speaks.
  void Function(String text, {required bool newTurn})? onModelSpeech;

  /// One trace line per tool used.
  void Function(String step)? onStep;

  /// A screen the model asked to open; the session ends first.
  void Function(String screen)? onNavigate;
  void Function(String message)? onError;

  /// The model that holds the session.
  String? model;

  static const _wsHost = 'wss://generativelanguage.googleapis.com/ws';
  static const fallbackModel = 'gemini-2.5-flash-native-audio-preview-09-2025';

  WebSocketChannel? _channel;
  StreamSubscription? _socketSub;
  final _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _micSub;
  bool _micMuted = false;
  bool _closed = false;
  Completer<void>? _setupDone;

  // Playback of the model's voice: one buffer stream per model turn.
  AudioSource? _voice;
  SoundHandle? _voiceHandle;
  DateTime _voiceEndsAt = DateTime.now();
  Timer? _speakingTimer;
  bool _turnComplete = true;
  bool _dropRestOfTurn = false;
  bool _userTurnOpen = false;
  bool _modelTurnOpen = false;

  bool get micMuted => _micMuted;

  void setMicMuted(bool muted) {
    _micMuted = muted;
    if (muted) level.value = 0;
  }

  /// Opens the session, then starts listening. Throws [GeminiException]
  /// (429 for the daily limit) or a readable error.
  Future<void> start() async {
    final gateway = await GeminiGateway.current();
    final Uri uri;
    final List<String> models;
    if (gateway.usesServer) {
      final response = await Supabase.instance.client.functions
          .invoke('gemini-live-token')
          .timeout(const Duration(seconds: 20));
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : jsonDecode(response.data.toString()) as Map<String, dynamic>;
      final token = data['token']?.toString() ?? '';
      if (token.isEmpty) throw GeminiException(response.status, '$data');
      models = [for (final m in data['models'] as List? ?? []) m.toString()];
      uri = Uri.parse(
        '$_wsHost/google.ai.generativelanguage.v1alpha.GenerativeService.'
        'BidiGenerateContentConstrained?access_token=$token',
      );
    } else {
      final listed = await gateway.listModels();
      models = [
        for (final m in (listed?['models'] as List? ?? []))
          if ((m['supportedGenerationMethods'] as List? ?? []).contains(
            'bidiGenerateContent',
          ))
            m['name'].toString().replaceFirst('models/', ''),
      ];
      uri = Uri.parse(
        '$_wsHost/google.ai.generativelanguage.v1beta.GenerativeService.'
        'BidiGenerateContent?key=${gateway.personalKey}',
      );
    }
    model = pickModel(models);

    if (!SoLoud.instance.isInitialized) {
      await SoLoud.instance.init(sampleRate: 24000, channels: Channels.mono);
    }

    final channel = WebSocketChannel.connect(uri);
    _channel = channel;
    await channel.ready.timeout(const Duration(seconds: 15));
    _setupDone = Completer<void>();
    _socketSub = channel.stream.listen(
      _onMessage,
      onError: (Object error) => _fail('$error'),
      onDone: () {
        if (!_closed) {
          final reason = channel.closeReason ?? '';
          _fail(reason.isEmpty ? 'connection closed' : reason);
        }
      },
    );
    _send({'setup': _setup()});
    await _setupDone!.future.timeout(const Duration(seconds: 15));

    final turns = _historyTurns();
    if (turns.isNotEmpty) {
      _send({
        'clientContent': {'turns': turns, 'turnComplete': false},
      });
    }
    await _startMicrophone();
    state.value = GeminiLiveState.listening;
  }

  /// A native-audio model first (it hears and speaks itself, the most
  /// natural voice), the newest version first.
  @visibleForTesting
  static String pickModel(List<String> models) {
    double rank(String name) {
      final n = name.toLowerCase();
      final version =
          double.tryParse(
            RegExp(r'gemini-(\d+(?:\.\d+)?)').firstMatch(n)?.group(1) ?? '',
          ) ??
          0;
      return (n.contains('native-audio') ? 1000 : 0) +
          (n.contains('live') ? 100 : 0) +
          version * 10;
    }

    final live = models.where((m) => m.startsWith('gemini')).toList()
      ..sort((a, b) => rank(b).compareTo(rank(a)));
    return live.isEmpty ? fallbackModel : live.first;
  }

  Map<String, dynamic> _setup() {
    final declarations = agent.functionDeclarations(permissions, language);
    return {
      'model': 'models/$model',
      'generationConfig': {
        'responseModalities': ['AUDIO'],
        'speechConfig': {
          'voiceConfig': {
            'prebuiltVoiceConfig': {'voiceName': 'Puck'},
          },
        },
      },
      'systemInstruction': {
        'parts': [
          {
            'text': AiAgentService.voiceInstruction(
              language,
              permissions.userName,
            ),
          },
        ],
      },
      if (declarations.isNotEmpty)
        'tools': [
          {'functionDeclarations': declarations},
        ],
      'inputAudioTranscription': <String, dynamic>{},
      'outputAudioTranscription': <String, dynamic>{},
      'contextWindowCompression': {'slidingWindow': <String, dynamic>{}},
    };
  }

  List<Map<String, dynamic>> _historyTurns() {
    final turns = <Map<String, dynamic>>[];
    for (final turn in history.reversed.take(12).toList().reversed) {
      final text = turn['content']?.trim() ?? '';
      if (text.isEmpty) continue;
      final role = turn['role'] == 'user' ? 'user' : 'model';
      if (turns.isEmpty && role != 'user') continue;
      turns.add({
        'role': role,
        'parts': [
          {'text': text},
        ],
      });
    }
    return turns;
  }

  Future<void> _startMicrophone() async {
    if (!await _recorder.hasPermission()) {
      throw StateError('microphone permission');
    }
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
        autoGain: true,
      ),
    );
    _micSub = stream.listen((chunk) {
      if (_closed || _micMuted) return;
      // Half duplex: the speaker is not sent back as the user's voice
      // (desktops have no echo cancelling). Tapping the orb interrupts.
      if (_isSpeaking) {
        level.value = 0;
        return;
      }
      level.value = _rms(chunk);
      _send({
        'realtimeInput': {
          'audio': {
            'data': base64Encode(chunk),
            'mimeType': 'audio/pcm;rate=16000',
          },
        },
      });
    });
  }

  bool get _isSpeaking =>
      state.value == GeminiLiveState.speaking ||
      DateTime.now().isBefore(_voiceEndsAt);

  static double _rms(Uint8List pcm) {
    if (pcm.length < 2) return 0;
    final samples = ByteData.sublistView(pcm);
    var sum = 0.0;
    final count = pcm.length ~/ 2;
    for (var i = 0; i < count; i++) {
      final s = samples.getInt16(i * 2, Endian.little) / 32768;
      sum += s * s;
    }
    return math.min(1, math.sqrt(sum / count) * 4);
  }

  /// Types a message into the call.
  void sendText(String text) {
    if (text.trim().isEmpty) return;
    _stopVoice();
    _send({
      'clientContent': {
        'turns': [
          {
            'role': 'user',
            'parts': [
              {'text': text},
            ],
          },
        ],
        'turnComplete': true,
      },
    });
    state.value = GeminiLiveState.thinking;
  }

  /// Stops the model's voice now; the rest of its answer is skipped.
  void interrupt() {
    if (_turnComplete) {
      _stopVoice();
      return;
    }
    _dropRestOfTurn = true;
    _stopVoice();
    state.value = GeminiLiveState.listening;
  }

  void _send(Map<String, dynamic> message) {
    if (_closed) return;
    try {
      _channel?.sink.add(jsonEncode(message));
    } catch (error) {
      debugPrint('Gemini Live send failed: $error');
    }
  }

  Future<void> _onMessage(dynamic raw) async {
    final Map<String, dynamic> message;
    try {
      final text = raw is String ? raw : utf8.decode(raw as List<int>);
      message = jsonDecode(text) as Map<String, dynamic>;
    } catch (error) {
      debugPrint('Gemini Live: unreadable message: $error');
      return;
    }

    if (message.containsKey('setupComplete')) {
      if (!(_setupDone?.isCompleted ?? true)) _setupDone!.complete();
      return;
    }

    final content = message['serverContent'] as Map?;
    if (content != null) {
      if (content['interrupted'] == true) {
        // The user spoke over the model: it stops at once.
        _stopVoice();
        _dropRestOfTurn = false;
        _turnComplete = true;
        _modelTurnOpen = false;
        state.value = GeminiLiveState.listening;
      }
      final heard = (content['inputTranscription'] as Map?)?['text'];
      if (heard is String && heard.isNotEmpty) {
        onUserSpeech?.call(heard, newTurn: !_userTurnOpen);
        _userTurnOpen = true;
        _modelTurnOpen = false;
      }
      final turn = content['modelTurn'] as Map?;
      if (turn != null) {
        _turnComplete = false;
        _userTurnOpen = false;
        if (!_dropRestOfTurn) {
          for (final part in (turn['parts'] as List? ?? const [])) {
            final data = (part as Map)['inlineData'] as Map?;
            if (data != null &&
                (data['mimeType']?.toString() ?? '').startsWith('audio/')) {
              await _play(
                base64Decode(data['data'].toString()),
                data['mimeType'].toString(),
              );
            }
          }
        }
      }
      final said = (content['outputTranscription'] as Map?)?['text'];
      if (said is String && said.isNotEmpty && !_dropRestOfTurn) {
        onModelSpeech?.call(said, newTurn: !_modelTurnOpen);
        _modelTurnOpen = true;
        _userTurnOpen = false;
      }
      if (content['turnComplete'] == true) {
        _turnComplete = true;
        _dropRestOfTurn = false;
        _modelTurnOpen = false;
        _endVoice();
      }
      return;
    }

    final toolCall = message['toolCall'] as Map?;
    if (toolCall != null) {
      await _runTools(toolCall['functionCalls'] as List? ?? const []);
      return;
    }

    if (message.containsKey('goAway')) {
      debugPrint('Gemini Live: the server will close the session soon.');
    }
  }

  Future<void> _runTools(List calls) async {
    state.value = GeminiLiveState.thinking;
    final responses = <Map<String, dynamic>>[];
    for (final raw in calls) {
      final call = Map<String, dynamic>.from(raw as Map);
      final name = call['name']?.toString() ?? '';
      final (result, step) = await agent.callTool(
        name,
        Map<String, dynamic>.from(call['args'] as Map? ?? {}),
        permissions: permissions,
        language: language,
        confirm: confirm,
      );
      if (_closed) return;
      onStep?.call(step);
      responses.add({'id': call['id'], 'name': name, 'response': result});
    }
    _send({
      'toolResponse': {'functionResponses': responses},
    });
    final screen = agent.navigateTo;
    if (screen != null) {
      await stop();
      onNavigate?.call(screen);
    }
  }

  Future<void> _play(Uint8List pcm, String mimeType) async {
    final rate =
        int.tryParse(RegExp(r'rate=(\d+)').firstMatch(mimeType)?.group(1) ?? '') ??
        24000;
    try {
      if (_voice == null) {
        final voice = SoLoud.instance.setBufferStream(
          bufferingType: BufferingType.released,
          bufferingTimeNeeds: 0.15,
          sampleRate: rate,
          channels: Channels.mono,
          format: BufferType.s16le,
        );
        _voice = voice;
        SoLoud.instance.addAudioDataStream(voice, pcm);
        _voiceHandle = await SoLoud.instance.play(voice);
        _voiceEndsAt = DateTime.now().add(const Duration(milliseconds: 150));
      } else {
        SoLoud.instance.addAudioDataStream(_voice!, pcm);
      }
    } catch (error) {
      debugPrint('Gemini Live playback failed: $error');
      return;
    }
    final now = DateTime.now();
    final start = _voiceEndsAt.isAfter(now) ? _voiceEndsAt : now;
    _voiceEndsAt = start.add(
      Duration(microseconds: pcm.length * 1000000 ~/ (rate * 2)),
    );
    state.value = GeminiLiveState.speaking;
    _watchSpeaking();
  }

  /// Back to listening once the queued voice has been played.
  void _watchSpeaking() {
    _speakingTimer?.cancel();
    final wait = _voiceEndsAt.difference(DateTime.now()) +
        const Duration(milliseconds: 250);
    _speakingTimer = Timer(wait.isNegative ? Duration.zero : wait, () {
      if (_closed || !_turnComplete) return;
      if (state.value == GeminiLiveState.speaking) {
        state.value = GeminiLiveState.listening;
      }
    });
  }

  void _endVoice() {
    final voice = _voice;
    _voice = null;
    _voiceHandle = null;
    if (voice != null) {
      try {
        SoLoud.instance.setDataIsEnded(voice);
      } catch (_) {}
    }
    if (DateTime.now().isAfter(_voiceEndsAt)) {
      if (state.value != GeminiLiveState.closed) {
        state.value = GeminiLiveState.listening;
      }
    } else {
      _watchSpeaking();
    }
  }

  void _stopVoice() {
    final voice = _voice;
    final handle = _voiceHandle;
    _voice = null;
    _voiceHandle = null;
    _voiceEndsAt = DateTime.now();
    _speakingTimer?.cancel();
    if (handle != null) SoLoud.instance.stop(handle).ignore();
    if (voice != null) SoLoud.instance.disposeSource(voice).ignore();
  }

  void _fail(String message) {
    if (_closed) return;
    debugPrint('Gemini Live: $message');
    if (!(_setupDone?.isCompleted ?? true)) {
      _setupDone!.completeError(StateError(message));
    }
    onError?.call(message);
    stop();
  }

  Future<void> stop() async {
    if (_closed) return;
    _closed = true;
    state.value = GeminiLiveState.closed;
    level.value = 0;
    _stopVoice();
    await _micSub?.cancel();
    try {
      await _recorder.stop();
    } catch (_) {}
    _recorder.dispose().ignore();
    await _socketSub?.cancel();
    await _channel?.sink.close();
  }
}
