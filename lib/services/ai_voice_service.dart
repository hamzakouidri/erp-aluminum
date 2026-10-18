import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:database_data/sql_database.dart';

class AiVoiceService {
  final String apiKey;
  final SqlDatabase db = SqlDatabase();

  AiVoiceService({required this.apiKey});

  Future<String> processVoiceCommand(String text) async {
    if (apiKey.isEmpty) {
      return 'يرجى وضع مفتاح Gemini API في الإعدادات أولاً.';
    }

    final prompt =
        '''
أنت مساعد ذكي لورشة ألمنيوم. مهمتك استخراج البيانات من كلام المستخدم وتنسيقها بصيغة JSON فقط.
إذا طلب المستخدم إنشاء زبون وإضافة نافذة، استخرج:
- client_name: اسم الزبون
- width: العرض بالمليمتر (إذا قال متر ونصف يعني 1500)
- height: الارتفاع بالمليمتر
- system: "french" إذا كان مفصلي/فراب، "sliding" إذا كان منزلق/كوليس
- glass: نوع الزجاج (مثلا "double", "simple", "stop_sol")
- color: لون الألمنيوم (مثلا "أبيض", "أسود")
 
النص: "$text"

أعد JSON بهذا الشكل فقط بدون أي نص إضافي:
{
  "action": "create",
  "client_name": "...",
  "width": 1500,
  "height": 1200,
  "system": "french",
  "glass": "double",
  "color": "أبيض"
}
''';

    try {
      // استخدام Gemini REST API مباشرة (يدعم المفاتيح الجديدة)
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent',
      );

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt},
              ],
            },
          ],
          'generationConfig': {'temperature': 0.1},
        }),
      );

      if (response.statusCode != 200) {
        return 'خطأ في الاتصال بـ Gemini (${response.statusCode}): ${response.body}';
      }

      final data = jsonDecode(response.body);
      final resultText =
          data['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '';

      if (resultText.isEmpty) return 'لم أتمكن من فهم الطلب.';

      String cleanResult = resultText.trim();
      if (cleanResult.startsWith('```json')) {
        cleanResult = cleanResult.substring(7);
      }
      if (cleanResult.startsWith('```')) {
        cleanResult = cleanResult.substring(3);
      }
      if (cleanResult.endsWith('```')) {
        cleanResult = cleanResult.substring(0, cleanResult.length - 3);
      }

      final Map<String, dynamic> parsedData = jsonDecode(cleanResult.trim());

      if (parsedData['action'] == 'create') {
        return await _executeCreateCommand(parsedData);
      }

      return 'تم تحليل الطلب بنجاح، ولكن الإجراء غير معروف.';
    } catch (e) {
      return 'حدث خطأ أثناء معالجة الطلب: $e';
    }
  }

  Future<String> _executeCreateCommand(Map<String, dynamic> data) async {
    String clientName = data['client_name'] ?? 'زبون جديد';
    double width = ((data['width'] ?? 1000) as num).toDouble();
    double height = ((data['height'] ?? 1000) as num).toDouble();
    String system = data['system'] ?? 'french';
    String glass = data['glass'] ?? 'Simple';

    try {
      // 1. إنشاء الزبون
      int clientId = await db.insertClient(clientName, '', '', '', '', '');

      // 2. إنشاء فاتورة (Commande)
      int commandId = await db.insertCommande(
        clientId,
        'Pending',
        'تم الإنشاء بالصوت',
        0,
        0,
        0,
      );

      // 3. إنشاء تفاصيل النافذة
      await db.insertCommandeDetail(
        idCommande: commandId,
        largeur: width,
        hauteur: height,
        windowType: system,
        partitionsJson: '[]',
        glass: glass,
        price: 0.0,
      );

      return 'تم بنجاح إنشاء الزبون "$clientName" وإضافة نافذة بمقاس $width × $height';
    } catch (e) {
      return 'خطأ في قاعدة البيانات: $e';
    }
  }
}
