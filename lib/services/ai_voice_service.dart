import 'package:database_data/sql_database.dart';
import 'package:database_data/services/ai_controller_service.dart';
import 'package:database_data/settings/app_settings.dart';

class AiVoiceService {
  final SqlDatabase db = SqlDatabase();

  /// Kept as a compatibility wrapper for older callers.  Gemini credentials
  /// are now held only by the server-side gateway.
  AiVoiceService();

  Future<String> processVoiceCommand(String text) async {
    try {
      final action = await AiControllerService().processQuery(
        query: text,
        language: AppLanguage.arabic,
      );
      if (action.actionType == 'create_order') {
        return _executeCreateCommand(action.parameters);
      }
      return action.speechResponse;
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
