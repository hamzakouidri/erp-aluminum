import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:database_data/sql_database.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Representation of an executable action returned by the AI controller
class AiAction {
  final String actionType;
  // 'navigate', 'create_order', 'check_stock', 'caisse_summary', 'engineering_warning', 'info', 'error'
  final Map<String, dynamic> parameters;
  final String speechResponse;
  final String? transcribedQuery;
  final String? detectedLanguage;

  AiAction({
    required this.actionType,
    required this.parameters,
    required this.speechResponse,
    this.transcribedQuery,
    this.detectedLanguage,
  });

  factory AiAction.fromMap(Map<String, dynamic> map, String defaultSpeech) {
    return AiAction(
      actionType: map['action_type']?.toString() ?? 'info',
      parameters: Map<String, dynamic>.from(map['parameters'] ?? {}),
      speechResponse: map['speech_response']?.toString() ?? defaultSpeech,
      transcribedQuery:
          map['transcribed_text']?.toString() ??
          map['transcribed_query']?.toString(),
      detectedLanguage: map['detected_language']?.toString(),
    );
  }
}

class _GeminiGatewayResponse {
  const _GeminiGatewayResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

class AiControllerService {
  final SqlDatabase db = SqlDatabase();

  /// Gemini requests are sent through the authenticated Supabase Edge
  /// Function.  The Google key and production model therefore never reach a
  /// phone or desktop installation.
  AiControllerService();

  static String getSystemInstruction(AppLanguage language) {
    final defaultLang = switch (language) {
      AppLanguage.french => 'fr',
      AppLanguage.english => 'en',
      _ => 'ar',
    };

    return '''
You are the advanced voice and AI assistant for the ERP Aluminum & Glass software (specifically built for aluminum joinery workshops, architectural/tempered glass processing, and material retail stores).

CRITICAL DIRECTIVE - NATURAL MULTILINGUAL CHAT & MIRRORING:
- Answer the user in the EXACT SAME LANGUAGE they speak or write to you:
  * If the user addresses you in French -> Reply in French and set "detected_language": "fr".
  * If the user addresses you in Arabic or North African / Algerian Darija -> Reply in clear, polite Arabic and set "detected_language": "ar".
  * If the user addresses you in English -> Reply in English and set "detected_language": "en".
  * If the query is ambiguous, default to "$defaultLang".
- You fully understand all technical aluminum and glass workshop vocabulary in all dialects (e.g. caisse/trésorerie, profilés, tube 40, équerres d'assemblage, vitrage simple/double/sécurit trempé, ouvrant frappe/battant, coulissant, rideau, métrage).

CORE CAPABILITIES & ACTIONS:
1. Voice Transcription ("transcribed_text"):
   - Accurately transcribe what the user uttered.
2. Precision Action Execution ("action_type"):
   - 'navigate': Screens: 'orders' (commandes), 'caisse' (caisse/trésorerie), 'stock' (stock), 'clients' (clients), 'cutting_optimizer' (optimiseur de coupe), 'tempered_glass' (verre trempé), 'settings' (paramètres), 'purchases' (achats matières), 'material_sales' (vente profilés), 'projects' (projets), 'reports' (rapports), 'worker_tasks' (tâches ouvriers), 'suppliers' (fournisseurs).
   - 'create_order': Fast order creation with {'client_name', 'width', 'height', 'system', 'glass', 'color'}.
   - 'check_stock': Check stock availability with {'item_name'}.
   - 'caisse_summary': Cashbox summary with {'target_caisse': 'workshop' | 'store' | 'all'}.
   - 'create_client', 'search_client'.
   - 'info': Clear interactive guidance and feature explanations.
   - 'engineering_warning': Alert on unsafe dimensions (e.g. height > 2600mm with single 4mm glass).

QUALITY RULES:
- For normal questions, use action_type "info" and give a complete, useful answer; do not reduce the answer to a one-line command acknowledgement.
- Never claim that you inspected live application data unless the selected action actually reads it.
- Ask a concise clarification question when a requested operation is ambiguous or missing required information.

Return strict JSON:
```json
{
  "transcribed_text": "...",
  "action_type": "navigate" | "create_order" | "check_stock" | "caisse_summary" | "create_client" | "search_client" | "info" | "engineering_warning",
  "detected_language": "fr" | "ar" | "en",
  "speech_response": "Your natural, helpful, professional response in the user's language.",
  "parameters": { ... }
}
```
''';
  }

  static String get systemInstruction =>
      getSystemInstruction(AppLanguage.arabic);

  /// Keeps enough recent context for a coherent conversation without sending
  /// an ever-growing transcript. Gemini histories should begin with a user
  /// turn and consecutive bubbles from the same role are merged.
  static List<Map<String, dynamic>> _normalizedHistory(
    List<Map<String, String>> history,
  ) {
    final normalized = <Map<String, dynamic>>[];
    for (final turn in history.reversed.take(16).toList().reversed) {
      final text = turn['content']?.trim() ?? '';
      if (text.isEmpty) continue;
      final role = turn['role'] == 'user' ? 'user' : 'model';
      if (normalized.isEmpty && role != 'user') continue;
      if (normalized.isNotEmpty && normalized.last['role'] == role) {
        final parts = normalized.last['parts'] as List<dynamic>;
        final previous = parts.first['text']?.toString() ?? '';
        parts.first['text'] = '$previous\n$text';
      } else {
        normalized.add({
          'role': role,
          'parts': [
            {'text': text},
          ],
        });
      }
    }
    return normalized;
  }

  /// Calls the server-side Gemini gateway. The gateway owns the API key,
  /// model selection and per-user quota checks.
  Future<_GeminiGatewayResponse> _postThroughGateway(
    Map<String, dynamic> requestBody,
  ) async {
    try {
      final result = await Supabase.instance.client.functions.invoke(
        'gemini-gateway',
        body: {'request_body': requestBody},
      );
      final raw = result.data;
      if (raw is! Map) {
        return const _GeminiGatewayResponse(
          statusCode: 599,
          body: '{"error":"invalid_gateway_response"}',
        );
      }
      final data = Map<String, dynamic>.from(raw);
      final status = (data['status'] as num?)?.toInt() ?? 599;
      final responseBody = data['body'];
      return _GeminiGatewayResponse(
        statusCode: status,
        body: responseBody is String ? responseBody : jsonEncode(responseBody),
      );
    } catch (error) {
      debugPrint('Gemini gateway request failed: $error');
      return _GeminiGatewayResponse(
        statusCode: 599,
        body: jsonEncode({'error': 'gateway_unreachable'}),
      );
    }
  }

  /// Sends text query to Gemini and parses structured action and speech readout
  Future<AiAction> processQuery({
    required String query,
    List<Map<String, String>> chatHistory = const [],
    AppLanguage language = AppLanguage.arabic,
  }) async {
    try {
      final contents = _normalizedHistory(chatHistory);

      // Mandatory language mirroring directive
      final languageDirective = switch (language) {
        AppLanguage.french =>
          '[Instruction: Répondez naturellement dans la même langue que celle de la question (Français, Arabe/Darija ou Anglais) et définissez "detected_language".]\n\n',
        AppLanguage.english =>
          '[Instruction: Reply naturally in the same language as the query (English, Arabic/Darija, or French) and set "detected_language".]\n\n',
        _ =>
          '[توجيه: أجب بشكل طبيعي بنفس لغة المتحدث (عربية/دارجة أو فرنسية أو إنجليزية) مع تحديد "detected_language".]\n\n',
      };

      // Latest query
      contents.add({
        'role': 'user',
        'parts': [
          {'text': '$languageDirective$query'},
        ],
      });

      final response = await _postThroughGateway({
        'system_instruction': {
          'parts': [
            {'text': getSystemInstruction(language)},
          ],
        },
        'contents': contents,
        'generationConfig': {
          'temperature': 0.1,
          'responseMimeType': 'application/json',
        },
      });

      if (response.statusCode != 200) {
        debugPrint(
          'Gemini API Error: ${response.statusCode} - ${response.body}',
        );
        final isConfigurationError = response.statusCode == 503;
        final isQuota = response.statusCode == 429;
        final isNetworkFailure = response.statusCode == 599;
        final isProviderFailure =
            response.statusCode >= 500 && response.statusCode != 599;

        final errMsg = isConfigurationError
            ? switch (language) {
                AppLanguage.french =>
                  'Le service IA doit être configuré par l’administrateur.',
                AppLanguage.english =>
                  'The AI service must be configured by an administrator.',
                _ => 'يلزم أن يهيئ المدير خدمة الذكاء الاصطناعي على الخادم.',
              }
            : isQuota
            ? switch (language) {
                AppLanguage.french =>
                  'Limite de requêtes atteinte. Veuillez patienter une minute.',
                AppLanguage.english =>
                  'Rate limit exceeded. Please wait a minute and retry.',
                _ =>
                  'تم تجاوز حد الطلبات المؤقت. يرجى الانتظار دقيقة والمحاولة مجدداً.',
              }
            : isNetworkFailure
            ? switch (language) {
                AppLanguage.french =>
                  'Impossible de joindre le service IA. Vérifiez la connexion puis réessayez.',
                AppLanguage.english =>
                  'Could not reach the AI service. Check the connection and retry.',
                _ =>
                  'تعذر الوصول إلى خدمة الذكاء الاصطناعي. تحقق من الاتصال ثم أعد المحاولة.',
              }
            : isProviderFailure
            ? switch (language) {
                AppLanguage.french =>
                  'Le service IA rencontre un problème temporaire. Réessayez dans quelques instants.',
                AppLanguage.english =>
                  'The AI service is temporarily unavailable. Please retry shortly.',
                _ =>
                  'خدمة الذكاء الاصطناعي تواجه خللاً مؤقتاً. أعد المحاولة بعد قليل.',
              }
            : switch (language) {
                AppLanguage.french =>
                  'La requête IA a été refusée (${response.statusCode}). Vérifiez la configuration du modèle.',
                AppLanguage.english =>
                  'The AI request was rejected (${response.statusCode}). Check the model configuration.',
                _ =>
                  'رفضت خدمة الذكاء الاصطناعي الطلب (${response.statusCode}). تحقق من إعدادات الموديل.',
              };

        return AiAction(
          actionType: 'error',
          parameters: {},
          speechResponse: errMsg,
        );
      }

      final jsonBody = jsonDecode(response.body);
      final rawText =
          jsonBody['candidates']?[0]?['content']?[0]?['parts']?[0]?['text'] ??
          jsonBody['candidates']?[0]?['content']?['parts']?[0]?['text'] ??
          '';

      if (rawText.isEmpty) {
        return AiAction(
          actionType: 'info',
          parameters: {},
          speechResponse: switch (language) {
            AppLanguage.french =>
              'Désolé, je n\'ai pas pu traiter cette demande. Veuillez réessayer.',
            AppLanguage.english =>
              'Sorry, I could not process this request. Please try again.',
            _ => 'عذراً، لم أستطع معالجة هذا الطلب، يرجى المحاولة مرة أخرى.',
          },
        );
      }

      return _parseJsonResponse(rawText, language: language);
    } catch (e) {
      debugPrint('AiControllerService error: $e');
      return AiAction(
        actionType: 'error',
        parameters: {},
        speechResponse: switch (language) {
          AppLanguage.french => 'Erreur lors du traitement: $e',
          AppLanguage.english => 'Error processing command: $e',
          _ => 'حدث خطأ أثناء معالجة الأمر: $e',
        },
      );
    }
  }

  /// Voice Listener: Sends recorded audio to Gemini multimodal input.
  /// Automatically transcribes speech and extracts structured action.
  Future<AiAction> processVoiceAudio(
    File audioFile, {
    List<Map<String, String>> chatHistory = const [],
    AppLanguage language = AppLanguage.arabic,
  }) async {
    try {
      final bytes = await audioFile.readAsBytes();
      final base64Audio = base64Encode(bytes);
      final ext = p.extension(audioFile.path).toLowerCase();

      String mimeType = 'audio/mp4';
      if (ext == '.mp3') mimeType = 'audio/mp3';
      if (ext == '.wav') mimeType = 'audio/wav';
      if (ext == '.aac') mimeType = 'audio/aac';
      if (ext == '.m4a') mimeType = 'audio/mp4';

      final directive = switch (language) {
        AppLanguage.french =>
          'RÈGLE ABSOLUE: Vous devez répondre EXCLUSIVEMENT EN FRANÇAIS dans "speech_response".\n'
              'Analysez l\'enregistrement audio ci-joint.\n'
              '1. Transcrivez avec exactitude ce que l\'utilisateur a dit dans "transcribed_text".\n'
              '2. Formulez votre réponse "speech_response" OBLIGATOIREMENT EN FRANÇAIS.\n'
              '3. Renvoyez uniquement du JSON strict.',
        AppLanguage.english =>
          'ABSOLUTE DIRECTIVE: You must reply EXCLUSIVELY IN ENGLISH in "speech_response".\n'
              'Analyze the attached audio recording.\n'
              '1. Accurately transcribe what the user uttered into "transcribed_text".\n'
              '2. Formulate your response "speech_response" MANDATORILY IN ENGLISH.\n'
              '3. Return only strict JSON.',
        _ =>
          'قاعدة أساسية: يجب عليك الرد باللغة العربية الفصحى حصراً في "speech_response".\n'
              'حلل التسجيل الصوتي المرفق.\n'
              '1. فرغ كلام المستخدم بدقة تامة في "transcribed_text".\n'
              '2. صغ ردك في "speech_response" باللغة العربية الفصحى حصراً.\n'
              '3. أرجع كائن JSON حصراً.',
      };

      final response = await _postThroughGateway({
        'system_instruction': {
          'parts': [
            {'text': getSystemInstruction(language)},
          ],
        },
        'contents': [
          ..._normalizedHistory(chatHistory),
          {
            'role': 'user',
            'parts': [
              {'text': directive},
              {
                'inlineData': {'mimeType': mimeType, 'data': base64Audio},
              },
            ],
          },
        ],
        'generationConfig': {
          'temperature': 0.1,
          'responseMimeType': 'application/json',
        },
      });

      if (response.statusCode != 200) {
        debugPrint(
          'Gemini Voice Error: ${response.statusCode} - ${response.body}',
        );
        return AiAction(
          actionType: 'error',
          parameters: {},
          speechResponse: switch (language) {
            AppLanguage.french =>
              'Impossible de traiter la voix par le serveur. Veuillez parler clairement et réessayer.',
            AppLanguage.english =>
              'Server could not understand audio. Please speak clearly and retry.',
            _ =>
              'تعذر فهم الصوت من الخادم. يرجى المحاولة مرة أخرى أو التحدث بوضوح.',
          },
        );
      }

      final jsonBody = jsonDecode(response.body);
      final rawText =
          jsonBody['candidates']?[0]?['content']?[0]?['parts']?[0]?['text'] ??
          jsonBody['candidates']?[0]?['content']?['parts']?[0]?['text'] ??
          '';

      if (rawText.isEmpty) {
        return AiAction(
          actionType: 'info',
          parameters: {},
          speechResponse: switch (language) {
            AppLanguage.french => 'Parole non reconnue. Veuillez répéter.',
            AppLanguage.english => 'Speech not recognized. Please speak again.',
            _ => 'لم أتمكن من تمييز الكلام، يرجى إعادة التحدث.',
          },
        );
      }

      return _parseJsonResponse(rawText, language: language);
    } catch (e) {
      debugPrint('Voice processing error: $e');
      return AiAction(
        actionType: 'error',
        parameters: {},
        speechResponse: switch (language) {
          AppLanguage.french => 'Erreur lors du traitement vocal: $e',
          AppLanguage.english => 'Error during voice processing: $e',
          _ => 'حدث خطأ أثناء معالجة الصوت: $e',
        },
      );
    }
  }

  /// Vision API: Analyze a photo of a hand-drawn sketch or architectural drawing
  Future<AiAction> processSketchImage(
    File imageFile, {
    AppLanguage language = AppLanguage.arabic,
  }) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      final directive = switch (language) {
        AppLanguage.french =>
          'RÈGLE ABSOLUE: Vous devez répondre EXCLUSIVEMENT EN FRANÇAIS dans "speech_response".\n'
              '${_sketchExtractionInstruction('fr')}',
        AppLanguage.english =>
          'ABSOLUTE DIRECTIVE: You must reply EXCLUSIVELY IN ENGLISH in "speech_response".\n'
              '${_sketchExtractionInstruction('en')}',
        _ =>
          'قاعدة أساسية: يجب عليك الرد باللغة العربية الفصحى حصراً في "speech_response".\n'
              '${_sketchExtractionInstruction('ar')}',
      };

      final response = await _postThroughGateway({
        'system_instruction': {
          'parts': [
            {'text': getSystemInstruction(language)},
          ],
        },
        'contents': [
          {
            'parts': [
              {'text': directive},
              {
                'inlineData': {
                  'mimeType': _imageMimeType(imageFile.path),
                  'data': base64Image,
                },
              },
            ],
          },
        ],
        'generationConfig': {
          'temperature': 0.1,
          'responseMimeType': 'application/json',
        },
      });

      if (response.statusCode != 200) {
        return AiAction(
          actionType: 'error',
          parameters: {},
          speechResponse: switch (language) {
            AppLanguage.french =>
              'Échec de l\'analyse de l\'image du croquis par le serveur.',
            AppLanguage.english => 'Server failed to analyze the sketch image.',
            _ => 'فشل تحليل صورة المخطط من الخادم.',
          },
        );
      }

      final jsonBody = jsonDecode(response.body);
      final rawText =
          jsonBody['candidates']?[0]?['content']?[0]?['parts']?[0]?['text'] ??
          jsonBody['candidates']?[0]?['content']?['parts']?[0]?['text'] ??
          '';

      return _parseJsonResponse(rawText, language: language);
    } catch (e) {
      return AiAction(
        actionType: 'error',
        parameters: {},
        speechResponse: switch (language) {
          AppLanguage.french => 'Erreur lors de la lecture du croquis : $e',
          AppLanguage.english => 'Error reading sketch image: $e',
          _ => 'حدث خطأ أثناء قراءة صورة المخطط: $e',
        },
      );
    }
  }

  static String _imageMimeType(String filePath) {
    return switch (p.extension(filePath).toLowerCase()) {
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      '.heic' => 'image/heic',
      '.heif' => 'image/heif',
      _ => 'image/jpeg',
    };
  }

  static String _sketchExtractionInstruction(String language) =>
      '''
Read the complete handwritten measurement sheet and the drawn window/door diagram. Recognize Arabic, French, Latin letters and Algerian workshop abbreviations.
Inspect dimension arrows, outer width/height, internal divisions, quantities, series/system name, glass, colour, shutter, fixed zones, opening/sliding leaves and opening directions.
Never invent a value. If a field is unreadable, keep it empty and list it in uncertain_fields. Convert centimetres to millimetres; preserve values already written in millimetres.
Return JSON only with this exact shape:
{
  "action_type": "create_order",
  "detected_language": "$language",
  "speech_response": "A concise summary plus every uncertain field that needs confirmation",
  "parameters": {
    "client_name": "",
    "width": 0,
    "height": 0,
    "quantity": 1,
    "system": "",
    "glass": "",
    "color": "",
    "window_type": "",
    "shutter": false,
    "opening_directions": [],
    "partitions": [],
    "handwritten_notes": "",
    "confidence": 0.0,
    "uncertain_fields": []
  }
}
The drawing geometry and written dimensions have priority over visual proportions. If several windows exist, describe all of them in handwritten_notes and use the first complete one in the main fields so the user can review before saving.
''';

  AiAction _parseJsonResponse(
    String rawText, {
    AppLanguage language = AppLanguage.arabic,
  }) {
    String cleaned = rawText.trim();
    if (cleaned.startsWith('```json')) {
      cleaned = cleaned.substring(7);
    }
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.substring(3);
    }
    if (cleaned.endsWith('```')) {
      cleaned = cleaned.substring(0, cleaned.length - 3);
    }

    final defaultSpeech = switch (language) {
      AppLanguage.french => 'Votre demande a été traitée avec succès.',
      AppLanguage.english => 'Your request was processed successfully.',
      _ => 'تم تنفيذ طلبك بنجاح.',
    };

    try {
      final parsed = jsonDecode(cleaned.trim());
      if (parsed is Map<String, dynamic>) {
        return AiAction.fromMap(
          parsed,
          parsed['speech_response']?.toString() ?? defaultSpeech,
        );
      }
    } catch (e) {
      debugPrint('JSON parse error: $e for raw: $rawText');
    }

    // Secondary fallback: extract speech_response and detected_language via RegExp
    final speechMatch = RegExp(
      r'"speech_response"\s*:\s*"([^"\\]*(?:\\.[^"\\]*)*)"',
    ).firstMatch(cleaned);
    if (speechMatch != null) {
      final extracted = speechMatch
          .group(1)
          ?.replaceAll(r'\"', '"')
          .replaceAll(r'\n', '\n');
      if (extracted != null && extracted.trim().isNotEmpty) {
        final langMatch = RegExp(
          r'"detected_language"\s*:\s*"([^"]+)"',
        ).firstMatch(cleaned);
        final actionMatch = RegExp(
          r'"action_type"\s*:\s*"([^"]+)"',
        ).firstMatch(cleaned);
        return AiAction(
          actionType: actionMatch?.group(1) ?? 'info',
          parameters: {},
          speechResponse: extracted.trim(),
          detectedLanguage: langMatch?.group(1),
        );
      }
    }

    // Final safety: never return raw JSON code as speech text
    String safeSpeech = rawText.replaceAll(RegExp(r'[{}"\\]'), ' ').trim();
    if (safeSpeech.isEmpty || safeSpeech.contains('speech_response')) {
      safeSpeech = defaultSpeech;
    }

    return AiAction(
      actionType: 'info',
      parameters: {},
      speechResponse: safeSpeech,
    );
  }

  /// Performs database creation for a new order with automated engineering guard checks
  Future<String> executeCreateOrder(
    Map<String, dynamic> params, {
    AppLanguage language = AppLanguage.arabic,
  }) async {
    final clientName =
        params['client_name']?.toString() ??
        (switch (language) {
          AppLanguage.french => 'Nouveau client',
          AppLanguage.english => 'New client',
          _ => 'زبون جديد',
        });
    final width = ((params['width'] ?? 1000) as num).toDouble();
    final height = ((params['height'] ?? 1000) as num).toDouble();
    final system = params['system']?.toString() ?? 'french';
    final glass = params['glass']?.toString() ?? 'Simple';

    // ── Engineering Safety Guard Check ──
    String warningNote = '';
    if (height > 2600 && glass.toLowerCase().contains('simple')) {
      warningNote = switch (language) {
        AppLanguage.french =>
          ' (Alerte technique : Hauteur > 2,6m, verre trempé securit ou double vitrage fortement recommandé pour la sécurité).',
        AppLanguage.english =>
          ' (Engineering alert: Height exceeds 2.6m, tempered safety or double glass strongly recommended).',
        _ =>
          ' (تنبيه هندسي: الارتفاع يتجاوز 2.6م، يُنصح بزجاج سيكوريت أو مدبل للسلامة).',
      };
    } else if (width > 2000 && system == 'french') {
      warningNote = switch (language) {
        AppLanguage.french =>
          ' (Alerte technique : Vantail très large pour système ouvrant battant, vérifiez les charnières).',
        AppLanguage.english =>
          ' (Engineering alert: Sash is very wide for hinged casement system, check hinges capacity).',
        _ =>
          ' (تنبيه هندسي: عرض الدرفة عريض جداً لنظام فراب مفصلي، تأكد من عدد وجودة المفصلات).',
      };
    }

    try {
      final clientId = await db.insertClient(clientName, '', '', '', '', '');
      final commandId = await db.insertCommande(
        clientId,
        'Pending',
        switch (language) {
          AppLanguage.french => 'Créé par l\'Assistant IA$warningNote',
          AppLanguage.english => 'Created by AI Assistant$warningNote',
          _ => 'تم الإنشاء بواسطة المساعد الذكي$warningNote',
        },
        0,
        0,
        0,
      );
      await db.insertCommandeDetail(
        idCommande: commandId,
        largeur: width,
        hauteur: height,
        windowType: system,
        partitionsJson: '[]',
        glass: glass,
        price: 0.0,
      );
      return switch (language) {
        AppLanguage.french =>
          'Nouvelle commande créée avec succès pour le client $clientName ($width × $height mm).$warningNote',
        AppLanguage.english =>
          'New order successfully created for client $clientName ($width × $height mm).$warningNote',
        _ =>
          'تم إنشاء طلبية جديدة للزبون $clientName بمقاس $width × $height ملم بنجاح.$warningNote',
      };
    } catch (e) {
      return switch (language) {
        AppLanguage.french =>
          'Erreur lors de l\'enregistrement de la commande : $e',
        AppLanguage.english => 'Error saving order to database: $e',
        _ => 'حدث خطأ أثناء حفظ الطلبية في قاعدة البيانات: $e',
      };
    }
  }

  /// Calculates Daily Caisse Summary from the local database,
  /// strictly separating Workshop Caisse from Store (Magasin) Caisse.
  Future<String> getDailyCaisseSummary({
    String? targetCaisse,
    AppLanguage language = AppLanguage.arabic,
  }) async {
    try {
      final now = DateTime.now();
      final todayStr =
          "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final entries = await db.readTreasury();

      double workshopIncome = 0.0;
      double workshopExpense = 0.0;

      double storeIncome = 0.0;
      double storeExpense = 0.0;

      for (final row in entries) {
        final date = (row['created_at'] ?? row['date'] ?? '').toString();
        if (!date.startsWith(todayStr)) continue;

        final rawType = (row['transaction_type'] ?? row['type'] ?? '')
            .toString()
            .toLowerCase();
        final amount = ((row['amount'] ?? 0) as num).toDouble();
        final caisse = (row['caisse_name'] ?? '').toString().toLowerCase();
        final desc = (row['description'] ?? '').toString().toLowerCase();

        final isIncome =
            rawType.contains('encaissement') ||
            rawType == 'income' ||
            rawType == 'in';

        // Check whether transaction belongs to Store (Magasin) or Workshop (Atelier)
        final isStore =
            caisse.contains('محل') ||
            caisse.contains('magasin') ||
            caisse.contains('store') ||
            desc.contains('بيع المواد') ||
            desc.contains('شراء المواد');

        if (isStore) {
          if (isIncome) {
            storeIncome += amount;
          } else {
            storeExpense += amount;
          }
        } else {
          // Defaults to Workshop Caisse
          if (isIncome) {
            workshopIncome += amount;
          } else {
            workshopExpense += amount;
          }
        }
      }

      final workshopNet = workshopIncome - workshopExpense;
      final storeNet = storeIncome - storeExpense;
      final totalNet = workshopNet + storeNet;

      final isWorkshopTarget =
          targetCaisse == 'workshop' ||
          targetCaisse == 'الورشة' ||
          targetCaisse == 'atelier';
      final isStoreTarget =
          targetCaisse == 'store' ||
          targetCaisse == 'المحل' ||
          targetCaisse == 'magasin';

      if (isWorkshopTarget) {
        return switch (language) {
          AppLanguage.french =>
            'Résumé de la caisse Atelier pour aujourd\'hui :\n'
                '• Recettes atelier : ${workshopIncome.toStringAsFixed(2)} DA\n'
                '• Dépenses atelier : ${workshopExpense.toStringAsFixed(2)} DA\n'
                '• Solde net atelier : ${workshopNet.toStringAsFixed(2)} DA.',
          AppLanguage.english =>
            'Workshop Cashbox summary for today:\n'
                '• Workshop Income: ${workshopIncome.toStringAsFixed(2)} DA\n'
                '• Workshop Expenses: ${workshopExpense.toStringAsFixed(2)} DA\n'
                '• Workshop Net: ${workshopNet.toStringAsFixed(2)} DA.',
          _ =>
            'ملخص صندوق الورشة لليوم:\n'
                '• مداخيل الورشة: ${workshopIncome.toStringAsFixed(2)} دج\n'
                '• مصاريف الورشة: ${workshopExpense.toStringAsFixed(2)} دج\n'
                '• صافي صندوق الورشة: ${workshopNet.toStringAsFixed(2)} دج.',
        };
      } else if (isStoreTarget) {
        return switch (language) {
          AppLanguage.french =>
            'Résumé de la caisse Magasin pour aujourd\'hui :\n'
                '• Recettes vente matières : ${storeIncome.toStringAsFixed(2)} DA\n'
                '• Dépenses achat matières : ${storeExpense.toStringAsFixed(2)} DA\n'
                '• Solde net magasin : ${storeNet.toStringAsFixed(2)} DA.',
          AppLanguage.english =>
            'Store Cashbox summary for today:\n'
                '• Material Sales Income: ${storeIncome.toStringAsFixed(2)} DA\n'
                '• Material Purchases: ${storeExpense.toStringAsFixed(2)} DA\n'
                '• Store Net: ${storeNet.toStringAsFixed(2)} DA.',
          _ =>
            'ملخص صندوق المحل لليوم:\n'
                '• مداخيل بيع المواد: ${storeIncome.toStringAsFixed(2)} دج\n'
                '• مصاريف شراء المواد: ${storeExpense.toStringAsFixed(2)} دج\n'
                '• صافي صندوق المحل: ${storeNet.toStringAsFixed(2)} دج.',
        };
      }

      return switch (language) {
        AppLanguage.french =>
          'Résumé des caisses pour aujourd\'hui (séparées) :\n\n'
              '🔹 **Caisse Atelier** :\n'
              '• Recettes : ${workshopIncome.toStringAsFixed(2)} DA\n'
              '• Dépenses : ${workshopExpense.toStringAsFixed(2)} DA\n'
              '• Solde net : ${workshopNet.toStringAsFixed(2)} DA\n\n'
              '🔸 **Caisse Magasin (Profilés & Accessoires)** :\n'
              '• Recettes : ${storeIncome.toStringAsFixed(2)} DA\n'
              '• Dépenses : ${storeExpense.toStringAsFixed(2)} DA\n'
              '• Solde net : ${storeNet.toStringAsFixed(2)} DA\n\n'
              '💰 **Solde Net Global** : ${totalNet.toStringAsFixed(2)} DA.',
        AppLanguage.english =>
          'Cashbox summary for today (separated):\n\n'
              '🔹 **Workshop Cashbox**:\n'
              '• Income: ${workshopIncome.toStringAsFixed(2)} DA\n'
              '• Expenses: ${workshopExpense.toStringAsFixed(2)} DA\n'
              '• Net: ${workshopNet.toStringAsFixed(2)} DA\n\n'
              '🔸 **Store Cashbox (Materials & Profiles)**:\n'
              '• Income: ${storeIncome.toStringAsFixed(2)} DA\n'
              '• Expenses: ${storeExpense.toStringAsFixed(2)} DA\n'
              '• Net: ${storeNet.toStringAsFixed(2)} DA\n\n'
              '💰 **Total Net Balance** : ${totalNet.toStringAsFixed(2)} DA.',
        _ =>
          'ملخص الصناديق لليوم (منفصلة):\n\n'
              '🔹 **صندوق الورشة**:\n'
              '• المداخيل: ${workshopIncome.toStringAsFixed(2)} دج\n'
              '• المصاريف: ${workshopExpense.toStringAsFixed(2)} دج\n'
              '• الصافي: ${workshopNet.toStringAsFixed(2)} دج\n\n'
              '🔸 **صندوق المحل (المواد)**:\n'
              '• المداخيل: ${storeIncome.toStringAsFixed(2)} دج\n'
              '• المصاريف: ${storeExpense.toStringAsFixed(2)} دج\n'
              '• الصافي: ${storeNet.toStringAsFixed(2)} دج\n\n'
              '💰 **الصافي الإجمالي للصندوقين**: ${totalNet.toStringAsFixed(2)} دج.',
      };
    } catch (e) {
      return switch (language) {
        AppLanguage.french => 'Impossible de calculer le résumé de caisse : $e',
        AppLanguage.english => 'Could not calculate cashbox summary: $e',
        _ => 'تعذر حساب ملخص الصندوق حالياً: $e',
      };
    }
  }

  /// Checks stock availability for specific item from CurrentStock
  Future<String> checkItemStock(
    String itemName, {
    AppLanguage language = AppLanguage.arabic,
  }) async {
    if (itemName.trim().isEmpty) {
      return switch (language) {
        AppLanguage.french =>
          'Veuillez spécifier le nom de l\'article à rechercher dans le stock.',
        AppLanguage.english =>
          'Please specify the item name to check in stock.',
        _ => 'يرجى تحديد اسم المادة للبحث في المخزون.',
      };
    }
    try {
      final myDb = await db.db;
      if (myDb == null) {
        return switch (language) {
          AppLanguage.french => 'La base de données n\'est pas disponible.',
          AppLanguage.english => 'Database is currently unavailable.',
          _ => 'قاعدة البيانات غير متاحة حالياً.',
        };
      }
      final stockItems = await myDb.query('CurrentStock');
      final query = itemName.trim().toLowerCase();
      final matched = stockItems.where((item) {
        final name = (item['item_name'] ?? item['name'] ?? '')
            .toString()
            .toLowerCase();
        return name.contains(query);
      }).toList();

      if (matched.isEmpty) {
        return switch (language) {
          AppLanguage.french =>
            'L\'article "$itemName" n\'est pas disponible en stock ou non enregistré.',
          AppLanguage.english =>
            'Item "$itemName" is not available in stock or not registered yet.',
          _ =>
            'المادة "$itemName" غير متوفرة في المخزون أو لم يتم تسجيلها بعد.',
        };
      }

      final first = matched.first;
      final qty = first['quantity'] ?? first['quantite'] ?? 0;
      final name = first['item_name'] ?? first['name'] ?? itemName;
      return switch (language) {
        AppLanguage.french =>
          'L\'article "$name" est disponible en stock. Quantité actuelle : $qty.',
        AppLanguage.english =>
          'Item "$name" is in stock. Current quantity: $qty.',
        _ => 'المادة "$name" متوفرة في المخزون، الكمية الحالية: $qty.',
      };
    } catch (e) {
      return switch (language) {
        AppLanguage.french => 'Erreur lors de la vérification du stock : $e',
        AppLanguage.english => 'Error checking stock: $e',
        _ => 'خطأ أثناء استعلام المخزون: $e',
      };
    }
  }

  /// Registers a new customer into the database via voice command
  Future<String> executeCreateClient(
    Map<String, dynamic> params, {
    AppLanguage language = AppLanguage.arabic,
  }) async {
    final defaultName = switch (language) {
      AppLanguage.french => 'Nouveau client',
      AppLanguage.english => 'New client',
      _ => 'زبون جديد',
    };
    final name = (params['name'] ?? params['client_name'] ?? defaultName)
        .toString()
        .trim();
    final phone = (params['phone'] ?? params['phone1'] ?? '').toString().trim();
    final address = (params['address'] ?? '').toString().trim();
    try {
      await db.insertClient(name, '', phone, '', '', address);
      return switch (language) {
        AppLanguage.french =>
          'Client "$name"${phone.isNotEmpty ? " (Tél: $phone)" : ""} enregistré avec succès dans la base de données.',
        AppLanguage.english =>
          'Client "$name"${phone.isNotEmpty ? " (Phone: $phone)" : ""} successfully registered in database.',
        _ =>
          'تم تسجيل الزبون "$name" ${phone.isNotEmpty ? "برقم هاتف $phone " : ""}في قاعدة البيانات بنجاح.',
      };
    } catch (e) {
      return switch (language) {
        AppLanguage.french => 'Échec de l\'enregistrement du client : $e',
        AppLanguage.english => 'Failed to register client: $e',
        _ => 'تعذر تسجيل الزبون: $e',
      };
    }
  }

  /// Searches customer information and ledger balances via voice command
  Future<String> executeSearchClient(
    Map<String, dynamic> params, {
    AppLanguage language = AppLanguage.arabic,
  }) async {
    final query =
        (params['query'] ?? params['name'] ?? params['client_name'] ?? '')
            .toString()
            .toLowerCase()
            .trim();
    if (query.isEmpty) {
      return switch (language) {
        AppLanguage.french =>
          'Veuillez spécifier le nom du client à rechercher.',
        AppLanguage.english => 'Please specify customer name to search.',
        _ => 'يرجى تحديد اسم الزبون للبحث عنه.',
      };
    }
    try {
      final clients = await db.readClient();
      final matched = clients.where((c) {
        final f = (c['firstname'] ?? '').toString().toLowerCase();
        final l = (c['lastname'] ?? '').toString().toLowerCase();
        final p = (c['phone1'] ?? '').toString().toLowerCase();
        return f.contains(query) || l.contains(query) || p.contains(query);
      }).toList();

      if (matched.isEmpty) {
        return switch (language) {
          AppLanguage.french => 'Aucun client trouvé avec le nom "$query".',
          AppLanguage.english => 'No customer found with name "$query".',
          _ => 'لم يتم العثور على أي زبون مسجل باسم "$query".',
        };
      }

      final first = matched.first;
      final fullName = '${first['firstname'] ?? ''} ${first['lastname'] ?? ''}'
          .trim();
      final notReg = switch (language) {
        AppLanguage.french => 'Non enregistré',
        AppLanguage.english => 'Not registered',
        _ => 'غير مسجل',
      };
      final phone = first['phone1'] ?? notReg;
      final debt = first['debt'] ?? 0;
      return switch (language) {
        AppLanguage.french =>
          'Données du client "$fullName" :\n• Téléphone : $phone\n• Dettes antérieures : $debt DA.',
        AppLanguage.english =>
          'Customer details for "$fullName":\n• Phone: $phone\n• Outstanding debt: $debt DA.',
        _ =>
          'بيانات الزبون "$fullName":\n• الهاتف: $phone\n• الديون السابقة: $debt دج.',
      };
    } catch (e) {
      return switch (language) {
        AppLanguage.french => 'Erreur lors de la recherche du client : $e',
        AppLanguage.english => 'Error searching customer: $e',
        _ => 'خطأ أثناء البحث عن الزبون: $e',
      };
    }
  }
}
