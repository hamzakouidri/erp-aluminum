import 'dart:io';
import 'dart:async';
import 'package:database_data/widgets/app_material.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import '../settings/app_settings.dart';
import '../services/ai_controller_service.dart';
import '../services/tts_service.dart';

class ChatMessage {
  String text;
  final bool isUser;
  final String? actionType;
  final bool isWarning;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.actionType,
    this.isWarning = false,
  });
}

class AiGuideChatDialog extends StatefulWidget {
  final Function(String targetRoute)? onNavigateRequested;

  const AiGuideChatDialog({super.key, this.onNavigateRequested});

  static Future<void> show(
    BuildContext context, {
    Function(String)? onNavigate,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AiGuideChatDialog(onNavigateRequested: onNavigate),
    );
  }

  @override
  State<AiGuideChatDialog> createState() => _AiGuideChatDialogState();
}

class _AiGuideChatDialogState extends State<AiGuideChatDialog> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  final TtsService _ttsService = TtsService();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final stt.SpeechToText _speechToText = stt.SpeechToText();

  bool _isSttEngineAvailable = false;
  bool _isListening = false;
  bool _isUsingStt = false;
  bool _isLoading = false;
  bool _isVoiceMuted = false;
  String? _recordingPath;

  StreamSubscription<Amplitude>? _amplitudeSub;
  double _currentAmplitudeDb = -160.0;

  String _t({required String ar, required String fr, required String en}) {
    final lang = context.read<AppSettingsProvider>().language;
    return switch (lang) {
      AppLanguage.french => fr,
      AppLanguage.english => en,
      _ => ar,
    };
  }

  String get _currentLangCode {
    final lang = context.read<AppSettingsProvider>().language;
    return switch (lang) {
      AppLanguage.french => 'fr',
      AppLanguage.english => 'en',
      _ => 'ar',
    };
  }

  List<String> get _quickPrompts {
    final lang = context.read<AppSettingsProvider>().language;
    return switch (lang) {
      AppLanguage.french => [
        'Résumé des caisses d\'aujourd\'hui',
        'Caisse atelier aujourd\'hui',
        'Caisse magasin aujourd\'hui',
        'Disponibilité profilé tube 40 en stock ?',
        'Comment utiliser l\'optimisation de coupe ?',
        'Ouvrir les commandes',
      ],
      AppLanguage.english => [
        'Today\'s cashbox summary',
        'Today\'s workshop cashbox',
        'Today\'s store cashbox',
        'Check profile tube 40 availability',
        'How to use cutting optimizer?',
        'Open orders screen',
      ],
      _ => [
        'ملخص الصناديق لليوم (الورشة والمحل)',
        'لخص لي صندوق الورشة لليوم',
        'لخص لي صندوق المحل لليوم',
        'هل بروفيل تيوب 40 متوفر في المخزون؟',
        'كيف أستخدم تحسين قص الألمنيوم؟',
        'افتح شاشة الطلبيات',
      ],
    };
  }

  @override
  void initState() {
    super.initState();
    _ttsService.init();

    // Check if native streaming STT is available (Android, iOS, Web)
    _speechToText
        .initialize(
          onError: (val) => debugPrint('STT onError: $val'),
          onStatus: (val) {
            debugPrint('STT status: $val');
            if ((val == 'done' || val == 'notListening') &&
                _isListening &&
                _isUsingStt) {
              _stopListeningAndProcess();
            }
          },
        )
        .then((available) {
          if (mounted) {
            setState(() => _isSttEngineAvailable = available);
          }
        })
        .catchError((e) {
          debugPrint('STT init exception: $e');
        });

    // Welcome message with localized speech and text
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final welcome = _t(
        ar: 'مرحباً بك! أنا مساعدك الذكي لتطبيق الألمنيوم والزجاج. يمكنك التحدث بالميكروفون وسأكتب ما تقوله لحظياً وأنفذ أوامرك بدقة متناهية، أو الاستفسار عن الصناديق والمخزون.',
        fr: 'Bienvenue ! Je suis votre assistant IA pour l’atelier d’aluminium et verre. Parlez dans le microphone pour dicter vos ordres en temps réel ou interroger les caisses et le stock.',
        en: 'Welcome! I am your AI assistant for the aluminum & glass workshop. Speak into the microphone to dictate commands in real time or inquire about cashboxes and inventory.',
      );
      if (_messages.isEmpty) {
        setState(() {
          _messages.add(ChatMessage(text: welcome, isUser: false));
        });
      }
      if (!_isVoiceMuted) {
        _ttsService.speak(welcome, languageCode: _currentLangCode);
      }
    });
  }

  @override
  void dispose() {
    _amplitudeSub?.cancel();
    _ttsService.stop();
    _audioRecorder.dispose();
    _speechToText.stop();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Voice Listener handler: starts/stops listening with live real-time typing
  Future<void> _toggleVoiceRecording() async {
    await _ttsService.stop();

    if (_isListening) {
      await _stopListeningAndProcess();
    } else {
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    _textController.clear();

    // Mode 1: Native Streaming STT (Android/iOS/Web) -> Real-time word-by-word typing
    if (_isSttEngineAvailable) {
      try {
        _isUsingStt = true;
        setState(() => _isListening = true);

        final currentLang = context.read<AppSettingsProvider>().language;
        final sttLocale = switch (currentLang) {
          AppLanguage.french => 'fr_FR',
          AppLanguage.english => 'en_US',
          _ => 'ar_DZ',
        };

        await _speechToText.listen(
          listenOptions: stt.SpeechListenOptions(
            localeId: sttLocale,
            partialResults: true,
            listenMode: stt.ListenMode.dictation,
            cancelOnError: false,
            pauseFor: const Duration(seconds: 6),
            listenFor: const Duration(minutes: 2),
          ),
          onResult: (val) {
            if (!mounted) return;
            setState(() {
              _textController.text = val.recognizedWords;
              _textController.selection = TextSelection.fromPosition(
                TextPosition(offset: _textController.text.length),
              );
            });
            if (val.finalResult && val.recognizedWords.trim().isNotEmpty) {
              _stopListeningAndProcess(presetQuery: val.recognizedWords);
            }
          },
        );
        return;
      } catch (e) {
        debugPrint('Native STT failed, switching to AudioRecorder: $e');
      }
    }

    // Mode 2: AudioRecorder + Gemini Multimodal Audio (Windows Desktop & High-Accuracy Fallback)
    try {
      if (!await _audioRecorder.hasPermission()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _t(
                  ar: 'يرجى منح إذن استخدام الميكروفون',
                  fr: 'Veuillez accorder l\'autorisation du microphone',
                  en: 'Please grant microphone permission',
                ),
              ),
            ),
          );
        }
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final filePath = p.join(
        tempDir.path,
        'voice_query_${DateTime.now().millisecondsSinceEpoch}.m4a',
      );

      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: filePath,
      );

      _amplitudeSub = _audioRecorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((amp) {
            if (mounted) {
              setState(() => _currentAmplitudeDb = amp.current);
            }
          });

      _isUsingStt = false;
      setState(() {
        _isListening = true;
        _recordingPath = filePath;
      });
    } catch (e) {
      debugPrint('Failed to start recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                ar: 'تعذر تشغيل الميكروفون: $e',
                fr: 'Impossible de démarrer le microphone : $e',
                en: 'Could not start microphone: $e',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _stopListeningAndProcess({String? presetQuery}) async {
    _amplitudeSub?.cancel();

    if (_isUsingStt) {
      await _speechToText.stop();
      setState(() => _isListening = false);
      final text = presetQuery ?? _textController.text.trim();
      if (text.isNotEmpty) {
        _handleSend(text);
      }
      return;
    }

    // Process audio file on Windows
    try {
      final path = await _audioRecorder.stop();
      setState(() => _isListening = false);

      final audioPath = path ?? _recordingPath;
      if (audioPath == null || !File(audioPath).existsSync()) return;

      final lang = context.read<AppSettingsProvider>().language;
      final userBubble = ChatMessage(
        text: _t(
          ar: '🎤 [جاري تفريغ الصوت وكتابته بدقة...]',
          fr: '🎤 [Transcription vocale en cours...]',
          en: '🎤 [Transcribing voice input...]',
        ),
        isUser: true,
      );

      setState(() {
        _messages.add(userBubble);
        _isLoading = true;
      });
      _scrollToBottom();

      final aiService = AiControllerService();

      final history = _messages
          .take(_messages.length - 1)
          .where((m) => !m.text.startsWith('🎤 ['))
          .map((m) => {'role': m.isUser ? 'user' : 'model', 'content': m.text})
          .toList();

      final response = await aiService.processVoiceAudio(
        File(audioPath),
        chatHistory: history,
        language: lang,
      );

      if (!mounted) return;

      // Populate text field with what the user said (Real-time live synchronization)
      final transcribed = response.transcribedQuery?.trim() ?? '';
      if (transcribed.isNotEmpty) {
        userBubble.text = '🗣️ $transcribed';
        _textController.text = transcribed;
      } else {
        userBubble.text = _t(
          ar: '🗣️ أمر صوتي',
          fr: '🗣️ Commande vocale',
          en: '🗣️ Voice command',
        );
      }

      await _processAiResponse(aiService, response);
    } catch (e) {
      debugPrint('Voice listener error: $e');
      if (mounted) {
        setState(() {
          _isListening = false;
          _isLoading = false;
        });
      }
    }
  }

  /// Vision Sketch-to-Order handler
  Future<void> _pickAndAnalyzeSketch() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result == null || result.files.single.path == null) return;

    final lang = context.read<AppSettingsProvider>().language;
    final file = File(result.files.single.path!);
    setState(() {
      _isLoading = true;
      _messages.add(
        ChatMessage(
          text: _t(
            ar: '📷 تم إرسال صورة المخطط للتحليل الهندسي بالذكاء الاصطناعي...',
            fr: '📷 Image du croquis envoyée pour analyse par l\'IA...',
            en: '📷 Sketch image sent for AI engineering analysis...',
          ),
          isUser: true,
        ),
      );
    });
    _scrollToBottom();

    final aiService = AiControllerService();

    final action = await aiService.processSketchImage(file, language: lang);

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _messages.add(
        ChatMessage(
          text: action.speechResponse,
          isUser: false,
          actionType: action.actionType,
        ),
      );
    });
    _scrollToBottom();

    if (!_isVoiceMuted) {
      final ttsLang = action.detectedLanguage ?? _currentLangCode;
      await _ttsService.speak(action.speechResponse, languageCode: ttsLang);
    }

    if (action.actionType == 'create_order') {
      final res = await aiService.executeCreateOrder(
        action.parameters,
        language: lang,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res), backgroundColor: Colors.teal),
        );
      }
    }
  }

  Future<void> _handleSend([String? presetText]) async {
    final text = (presetText ?? _textController.text).trim();
    if (text.isEmpty || _isLoading) return;

    _textController.clear();
    await _ttsService.stop();

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _isLoading = true;
    });
    _scrollToBottom();

    final lang = context.read<AppSettingsProvider>().language;
    final aiService = AiControllerService();

    final history = _messages
        .take(_messages.length - 1)
        .where((m) => !m.text.startsWith('🎤 ['))
        .map((m) => {'role': m.isUser ? 'user' : 'model', 'content': m.text})
        .toList();

    final response = await aiService.processQuery(
      query: text,
      chatHistory: history,
      language: lang,
    );

    if (!mounted) return;
    await _processAiResponse(aiService, response);
  }

  Future<void> _processAiResponse(
    AiControllerService aiService,
    AiAction response,
  ) async {
    final lang = context.read<AppSettingsProvider>().language;
    String finalVoiceText = response.speechResponse;
    bool isWarning = false;

    // Handle Specialized Precision Actions with strict language localization
    if (response.actionType == 'caisse_summary') {
      final target = response.parameters['target_caisse']?.toString();
      final summary = await aiService.getDailyCaisseSummary(
        targetCaisse: target,
        language: lang,
      );
      finalVoiceText = '$finalVoiceText\n\n$summary';
    } else if (response.actionType == 'check_stock') {
      final item = response.parameters['item_name']?.toString() ?? '';
      final stockResult = await aiService.checkItemStock(item, language: lang);
      finalVoiceText = '$finalVoiceText\n\n$stockResult';
    } else if (response.actionType == 'create_order') {
      final res = await aiService.executeCreateOrder(
        response.parameters,
        language: lang,
      );
      finalVoiceText = '$finalVoiceText\n\n$res';
      if (res.contains('تنبيه هندسي') ||
          res.contains('Alerte') ||
          res.contains('Warning')) {
        isWarning = true;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res),
            backgroundColor: isWarning ? Colors.orange : Colors.teal,
          ),
        );
      }
    } else if (response.actionType == 'create_client') {
      final res = await aiService.executeCreateClient(
        response.parameters,
        language: lang,
      );
      finalVoiceText = '$finalVoiceText\n\n$res';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res), backgroundColor: Colors.teal),
        );
      }
    } else if (response.actionType == 'search_client') {
      final res = await aiService.executeSearchClient(
        response.parameters,
        language: lang,
      );
      finalVoiceText = '$finalVoiceText\n\n$res';
    } else if (response.actionType == 'navigate') {
      final target = response.parameters['target']?.toString();
      if (target != null && widget.onNavigateRequested != null) {
        widget.onNavigateRequested!(target);
      }
    }

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _messages.add(
        ChatMessage(
          text: finalVoiceText,
          isUser: false,
          actionType: response.actionType,
          isWarning: isWarning,
        ),
      );
    });
    _scrollToBottom();

    if (!_isVoiceMuted) {
      final ttsLang = response.detectedLanguage ?? _currentLangCode;
      await _ttsService.speak(finalVoiceText, languageCode: ttsLang);
    }
  }

  /// Builds a responsive visual sound wave based on microphone amplitude
  Widget _buildLiveSoundWave() {
    // db ranges typically from -60 (silent) to 0 (loud)
    final normalized = ((_currentAmplitudeDb + 60) / 60).clamp(0.05, 1.0);
    final bars = [0.4, 0.7, 1.0, 0.8, 0.5, 0.9, 0.6];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: bars.map((b) {
        final height = (18 * b * normalized).clamp(4.0, 22.0);
        return Container(
          width: 3.5,
          height: height,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(
            color: Colors.redAccent,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? const Color(0xFF1E222B) : Colors.white,
      child: Container(
        width: 640,
        height: 720,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0072FF), Color(0xFF00C6FF)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.psychology,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t(
                          ar: 'المساعد الذكي الصوتي للورشة والتطبيق',
                          fr: 'Assistant IA Vocal pour Atelier & Magasin',
                          en: 'AI Voice Assistant for Workshop & Store',
                        ),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        _t(
                          ar: 'كتابة صوتية لحظية • تنفيذ دقيق للأوامر • ناطق فصيح',
                          fr: 'Transcription en direct • Exécution précise • Synthèse vocale',
                          en: 'Real-time dictation • Precision execution • Voice speech',
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                // Speaker Mute/Unmute
                IconButton(
                  tooltip: _isVoiceMuted
                      ? _t(
                          ar: 'تفعيل مكبر الصوت',
                          fr: 'Activer le haut-parleur',
                          en: 'Unmute speaker',
                        )
                      : _t(
                          ar: 'كتم مكبر الصوت',
                          fr: 'Couper le son',
                          en: 'Mute speaker',
                        ),
                  icon: Icon(
                    _isVoiceMuted ? Icons.volume_off : Icons.volume_up,
                    color: _isVoiceMuted ? Colors.grey : Colors.blueAccent,
                  ),
                  onPressed: () {
                    setState(() {
                      _isVoiceMuted = !_isVoiceMuted;
                      if (_isVoiceMuted) _ttsService.stop();
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(),

            // Chat Messages List
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  final isWarning = msg.isWarning;

                  return Align(
                    alignment: msg.isUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75,
                      ),
                      decoration: BoxDecoration(
                        color: msg.isUser
                            ? Theme.of(context).primaryColor
                            : (isWarning
                                  ? Colors.amber.shade900.withValues(
                                      alpha: 0.15,
                                    )
                                  : (isDark
                                        ? const Color(0xFF2A2E3D)
                                        : const Color(0xFFF0F4F8))),
                        border: isWarning
                            ? Border.all(color: Colors.amber, width: 1.5)
                            : null,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isWarning)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.amber,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _t(
                                      ar: 'تنبيه الجودة والسلامة الهندسية',
                                      fr: 'Alerte Qualité et Sécurité Ingénierie',
                                      en: 'Engineering Quality & Safety Alert',
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Colors.amber,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Text(
                            msg.text,
                            style: TextStyle(
                              color: msg.isUser
                                  ? Colors.white
                                  : (isDark ? Colors.white : Colors.black87),
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                          if (!msg.isUser)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  InkWell(
                                    onTap: () => _ttsService.speak(
                                      msg.text,
                                      languageCode: _currentLangCode,
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.volume_up_rounded,
                                          size: 16,
                                          color: Colors.blueAccent,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _t(
                                            ar: 'قراءة صوتية',
                                            fr: 'Lecture vocale',
                                            en: 'Read aloud',
                                          ),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.blueAccent.withValues(
                                              alpha: 0.9,
                                            ),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            if (_isLoading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _t(
                        ar: 'الذكاء الاصطناعي يعالج الطلب وينفذ الإجراء بدقة...',
                        fr: 'L\'IA traite votre demande avec précision...',
                        en: 'AI is processing the command accurately...',
                      ),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),

            // Live Real-Time Dictation / Sound Wave Banner
            if (_isListening)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.redAccent, width: 1.5),
                ),
                child: Row(
                  children: [
                    _buildLiveSoundWave(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isUsingStt
                                ? _t(
                                    ar: '🎙️ جاري الكتابة اللحظية لما تقوله الآن...',
                                    fr: '🎙️ Transcription en direct...',
                                    en: '🎙️ Live real-time transcription...',
                                  )
                                : _t(
                                    ar: '🔴 جاري التقاط صوتك بدقة... اضغط للإرسال فور الانتهاء',
                                    fr: '🔴 Écoute de votre voix... Cliquez pour envoyer',
                                    en: '🔴 Capturing audio... Click to send when finished',
                                  ),
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          if (_textController.text.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                _textController.text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        minimumSize: const Size(60, 32),
                      ),
                      onPressed: () => _stopListeningAndProcess(),
                      child: Text(
                        _t(
                          ar: 'إرسال وتنفيذ',
                          fr: 'Envoyer & Exécuter',
                          en: 'Send & Execute',
                        ),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),

            // Quick Prompts Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _quickPrompts.map((p) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6, bottom: 8),
                    child: ActionChip(
                      label: Text(p, style: const TextStyle(fontSize: 11)),
                      onPressed: () => _handleSend(p),
                    ),
                  );
                }).toList(),
              ),
            ),

            // Input Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF262A36)
                    : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  // Camera / Image picker button for sketch vision
                  IconButton(
                    icon: const Icon(
                      Icons.document_scanner_rounded,
                      color: Colors.blueAccent,
                    ),
                    tooltip: _t(
                      ar: 'قراءة مخطط يدوي بالكاميرا (Sketch-to-Order)',
                      fr: 'Scanner un croquis manuel (Sketch-to-Order)',
                      en: 'Scan hand sketch with camera (Sketch-to-Order)',
                    ),
                    onPressed: _pickAndAnalyzeSketch,
                  ),
                  // Microphone button for live STT
                  IconButton(
                    icon: Icon(
                      _isListening
                          ? Icons.stop_circle_rounded
                          : Icons.mic_rounded,
                      color: _isListening ? Colors.red : Colors.blueAccent,
                      size: 26,
                    ),
                    onPressed: _toggleVoiceRecording,
                    tooltip: _isListening
                        ? _t(
                            ar: 'إيقاف التسجيل وإرسال الأمر',
                            fr: 'Arrêter et envoyer la commande',
                            en: 'Stop and send command',
                          )
                        : _t(
                            ar: 'تحدث صوتياً بالميكروفون',
                            fr: 'Parler au microphone',
                            en: 'Speak with microphone',
                          ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: _isListening
                            ? _t(
                                ar: 'جاري الاستماع لصوتك وكتابته هنا...',
                                fr: 'Écoute de votre voix en cours...',
                                en: 'Listening to your voice...',
                              )
                            : _t(
                                ar: 'اكتب سؤالك أو تحدث عبر الميكروفون...',
                                fr: 'Tapez votre question ou parlez au micro...',
                                en: 'Type your query or speak into mic...',
                              ),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onSubmitted: (v) => _handleSend(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.send_rounded,
                      color: Colors.blueAccent,
                    ),
                    onPressed: () => _handleSend(),
                    tooltip: _t(ar: 'إرسال', fr: 'Envoyer', en: 'Send'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
