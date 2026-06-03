import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:firebase_auth/firebase_auth.dart';

import '../services/ai_voice_service.dart';
import '../settings/app_settings.dart';

class VoiceAssistantOverlay extends StatefulWidget {
  final Widget child;

  const VoiceAssistantOverlay({super.key, required this.child});

  @override
  State<VoiceAssistantOverlay> createState() => _VoiceAssistantOverlayState();
}

class _VoiceAssistantOverlayState extends State<VoiceAssistantOverlay>
    with TickerProviderStateMixin {
  late stt.SpeechToText _speech;
  bool _isListening = false;
  bool _isProcessing = false;
  String _voiceCommand = '';

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _waveAnimation;

  // Custom Toast state
  String _toastMessage = '';
  Color _toastColor = Colors.green;
  bool _showToast = false;

  // Position variables
  double _x = 20.0;
  double _y = 20.0;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();

    // Pulse animation (دائري يتمدد ويتقلص)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Wave rings animation
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _waveAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _waveController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  void _startAnimations() {
    _pulseController.repeat(reverse: true);
    _waveController.repeat();
  }

  void _stopAnimations() {
    _pulseController.stop();
    _pulseController.reset();
    _waveController.stop();
    _waveController.reset();
  }

  Future<bool> _requestMicPermission() async {
    // نترك speech_to_text يطلب الإذن بنفسه
    return true;
  }

  void _listenToCommand() async {
    if (!_isListening) {
      if (!mounted) return;

      // إشعار فوري
      setState(() {
        _toastMessage = '⏳ جاري تهيئة الميكروفون...';
        _toastColor = Colors.blue;
        _showToast = true;
      });
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showToast = false);
      });

      final hasPermission = await _requestMicPermission();
      if (!hasPermission || !mounted) return;

      bool available = await _speech.initialize(
        onStatus: (val) {
          debugPrint('Speech status: $val');
          if (!mounted) return;
          if (val == 'done' || val == 'notListening') {
            setState(() => _isListening = false);
            _stopAnimations();
            _processVoiceCommand();
          }
        },
        onError: (val) {
          debugPrint('Speech error: ${val.errorMsg}');
          if (!mounted) return;
          setState(() => _isListening = false);
          _stopAnimations();
          _showCustomToast('خطأ: ${val.errorMsg}', Colors.orange);
        },
      );

      debugPrint('Speech available: $available');
      if (!mounted) return;

      if (available) {
        setState(() => _isListening = true);
        _startAnimations();
        _showCustomToast('🎙️ تحدث الآن...', Colors.green);
        _speech.listen(
          onResult: (val) {
            debugPrint('Result: ${val.recognizedWords}');
            if (!mounted) return;
            setState(() => _voiceCommand = val.recognizedWords);
          },
          listenOptions: stt.SpeechListenOptions(
            localeId: 'ar_SA',
            cancelOnError: true,
            partialResults: true,
          ),
        );
      } else {
        _showCustomToast('❌ التعرف على الصوت غير متاح على هذا الجهاز.', Colors.red);
      }
    } else {
      if (!mounted) return;
      setState(() => _isListening = false);
      _stopAnimations();
      _speech.stop();
    }
  }

  void _showCustomToast(String message, Color color) {
    if (!mounted) return;
    setState(() {
      _toastMessage = message;
      _toastColor = color;
      _showToast = true;
    });

    int durationSeconds = color == Colors.red ? 10 : 4;
    Future.delayed(Duration(seconds: durationSeconds), () {
      if (mounted) setState(() => _showToast = false);
    });
  }

  void _processVoiceCommand() async {
    if (_voiceCommand.isEmpty) {
      _showCustomToast('عفواً، لم أسمع أي شيء. حاول التحدث بصوت أوضح.', Colors.orange);
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
    final aiService = AiVoiceService(apiKey: settings.geminiApiKey);

    final result = await aiService.processVoiceCommand(_voiceCommand);
    _voiceCommand = '';

    if (mounted) {
      setState(() {
        _isProcessing = false;
      });
      _showCustomToast(
        result,
        result.contains('خطأ') || result.contains('عذراً') ? Colors.red : Colors.green,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        return Stack(
          children: [
            widget.child,
            Positioned(
              bottom: _y,
              left: _x,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _x += details.delta.dx;
                      _y -= details.delta.dy;
                    });
                  },
                  child: Material(
                    color: Colors.transparent,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // نص الصوت المسجل
                        if (_isListening && _voiceCommand.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            constraints: const BoxConstraints(maxWidth: 280),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _voiceCommand,
                              style: const TextStyle(color: Colors.white, fontSize: 16),
                              textDirection: TextDirection.rtl,
                            ),
                          ),

                        // زر الميكروفون مع الحلقات المتموجة
                        SizedBox(
                          width: 130,
                          height: 130,
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              // حلقة الموجة الخارجية
                              if (_isListening)
                                AnimatedBuilder(
                                  animation: _waveAnimation,
                                  builder: (context, child) {
                                    final size = 56.0 + (_waveAnimation.value * 60);
                                    return Container(
                                      width: size,
                                      height: size,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.red.withValues(
                                            alpha: (1.0 - _waveAnimation.value) * 0.8,
                                          ),
                                          width: 3,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              // حلقة النبض الداخلية
                              if (_isListening)
                                AnimatedBuilder(
                                  animation: _pulseAnimation,
                                  builder: (context, child) {
                                    return Container(
                                      width: 56.0 * _pulseAnimation.value,
                                      height: 56.0 * _pulseAnimation.value,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.red.withValues(alpha: 0.25),
                                      ),
                                    );
                                  },
                                ),
                              // زر FAB
                              FloatingActionButton(
                                heroTag: 'global_voice_btn',
                                backgroundColor: _isListening ? Colors.red : Colors.purple,
                                onPressed: _listenToCommand,
                                child: Icon(
                                  _isListening ? Icons.mic : Icons.mic_none,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // نص "جاري التسجيل..."
                        if (_isListening)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            child: const Text(
                              'جاري التسجيل...',
                              style: TextStyle(
                                color: Colors.red,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

            // Loading Overlay
            if (_isProcessing)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.5),
                  child: Center(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            CircularProgressIndicator(),
                            SizedBox(width: 20),
                            Text('جاري تحليل الطلب والبيانات...', style: TextStyle(fontSize: 16)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Custom Toast
            if (_showToast)
              Positioned(
                bottom: 100,
                left: 20,
                right: 20,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: _toastColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _toastMessage,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
