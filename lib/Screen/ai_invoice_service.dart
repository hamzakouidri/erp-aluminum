import 'dart:convert';
import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';

class ExtractedInvoiceItem {
  final String itemCode;
  final String itemName;
  final double quantity;
  final double price;
  final String color;
  final String unit;
  final String rawDescription;
  final double confidence;

  ExtractedInvoiceItem({
    required this.itemCode,
    required this.itemName,
    required this.quantity,
    required this.price,
    this.color = '',
    this.unit = '',
    this.rawDescription = '',
    this.confidence = 0.0,
  });

  factory ExtractedInvoiceItem.fromJson(Map<String, dynamic> json) {
    return ExtractedInvoiceItem(
      itemCode: (json['item_code'] ?? '').toString(),
      itemName: (json['item_name'] ?? '').toString(),
      quantity: _number(json['quantity']),
      price: _number(json['price']),
      color: (json['color'] ?? '').toString().trim(),
      unit: (json['unit'] ?? '').toString().trim(),
      rawDescription: (json['raw_description'] ?? '').toString().trim(),
      confidence: _number(json['confidence']).clamp(0.0, 1.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'item_code': itemCode,
    'item_name': itemName,
    'quantity': quantity,
    'price': price,
    'color': color,
    'unit': unit,
    'raw_description': rawDescription,
    'confidence': confidence,
  };

  static double _number(dynamic value) {
    if (value is num) return value.toDouble();
    final normalized = value
        ?.toString()
        .replaceAll(RegExp(r'[^0-9,.-]'), '')
        .replaceAll(',', '.') ??
        '';
    return double.tryParse(normalized) ?? 0.0;
  }
}

class ExtractedInvoice {
  final String invoiceNumber;
  final String supplierName;
  final String date;
  final double total;
  final List<ExtractedInvoiceItem> items;

  ExtractedInvoice({
    required this.invoiceNumber,
    required this.supplierName,
    required this.date,
    required this.total,
    required this.items,
  });

  factory ExtractedInvoice.fromJson(Map<String, dynamic> json) {
    var list = json['items'] as List? ?? [];
    List<ExtractedInvoiceItem> parsedItems = list
        .map((i) => ExtractedInvoiceItem.fromJson(i))
        .toList();

    return ExtractedInvoice(
      invoiceNumber: (json['invoice_number'] ?? '').toString(),
      supplierName: (json['supplier_name'] ?? '').toString(),
      date: (json['date'] ?? '').toString(),
      total: ExtractedInvoiceItem._number(json['total']),
      items: parsedItems,
    );
  }

  Map<String, dynamic> toJson() => {
    'invoice_number': invoiceNumber,
    'supplier_name': supplierName,
    'date': date,
    'total': total,
    'items': items.map((i) => i.toJson()).toList(),
  };
}

class AiInvoiceService {
  /// تحليل صورة الفاتورة واستخراج البيانات.
  /// Requires a configured API key; failures must never be replaced with
  /// fabricated invoice data that looks like a successful scan.
  static Future<ExtractedInvoice> analyzeInvoice(
    Uint8List imageBytes, {
    String? apiKey,
    String mimeType = 'image/jpeg',
    List<Map<String, String>> catalogHints = const [],
  }) async {
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw StateError('مفتاح Gemini غير مضبوط في الإعدادات.');
    }

    try {
      final model = GenerativeModel(
        model: 'gemini-3.8-flash',
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
        ),
      );

      final catalogText = catalogHints.take(350).map((entry) {
        return '${entry['code'] ?? ''} | ${entry['name'] ?? ''} | ${entry['color'] ?? ''}';
      }).join('\n');

      final prompt = '''
أنت خبير OCR لفواتير الألمنيوم والزجاج والأكسسوارات. اقرأ الصورة سطراً سطراً، بما في ذلك الجداول الصغيرة أو الباهتة.
لا تختصر قائمة السلع ولا تحذف سطراً لأنه غير واضح. أخرج كل سطر سلعة ظاهر في الصورة مرة واحدة وبنفس ترتيب الفاتورة.
افصل كود السلعة عن اسمها وعن اللون والكمية والوحدة والسعر. لا تخلط الإجمالي بسعر الوحدة.
قد تختلف تسمية المورد عن الكتالوج. استعمل الكتالوج أدناه فقط لفهم الأخطاء الإملائية المحتملة، ولا تستبدل النص الأصلي ولا تخترع تطابقاً.
قواعد اللون مهمة:
- FBM يعني لوناً خشبياً (Faux bois / bois). اكتب color = "خشبي FBM".
- استخرج Blanc/White/أبيض، Noir/أسود، Gris، Bronze، Marron، Beige وأي كود لون كما هو.
- إن لم يظهر اللون صراحة اكتب "غير مذكور"، ولا تستنتج لون البروفيل من سلعة أخرى.
- احتفظ بالنص الكامل المقروء في raw_description حتى لا تضيع أي معلومة.

الكتالوج المحلي المساعد:
$catalogText

أريدك أن تستخرج تفاصيل الفاتورة كـ JSON كالتالي تماماً:
{
  "invoice_number": "رقم الفاتورة هنا",
  "supplier_name": "اسم المورد أو الشركة البائعة",
  "date": "تاريخ الفاتورة بصيغة YYYY-MM-DD",
  "total": إجمالي الفاتورة كـ number,
  "items": [
    {
      "item_code": "كود المقطع أو السلعة التجاري مثل P400 أو S450 أو غير ذلك، اتركه فارغاً إن لم يكن مكتوباً",
      "item_name": "اسم المقطع الهندسي أو السلعة مثل حلق أو ضلفة أو زجاج أو إكسسوار",
      "quantity": الكمية كـ number,
      "price": سعر الوحدة كـ number,
      "color": "اللون أو كوده، ودائماً غير مذكور إن لم يظهر",
      "unit": "الوحدة مثل barre أو pièce أو kg أو m",
      "raw_description": "النص الكامل لسطر الفاتورة كما قرأته",
      "confidence": رقم من 0 إلى 1 يمثل وضوح القراءة
    }
  ]
}

ركز جداً على الأكواد التجارية (مثل P400، P405، TPR)، وعلى جميع الأسطر واللون. إذا كان السطر ضعيفاً أبقه مع confidence منخفض بدلاً من حذفه.
''';

      final content = [
        Content.multi([DataPart(mimeType, imageBytes), TextPart(prompt)]),
      ];

      final response = await model.generateContent(content);
      final responseText = response.text;

      if (responseText == null || responseText.isEmpty) {
        throw Exception('الرد المستلم من الذكاء الاصطناعي فارغ.');
      }

      final cleaned = responseText
          .replaceFirst(RegExp(r'^\s*```(?:json)?\s*'), '')
          .replaceFirst(RegExp(r'\s*```\s*$'), '')
          .trim();
      final Map<String, dynamic> jsonMap = jsonDecode(cleaned);
      final invoice = ExtractedInvoice.fromJson(jsonMap);
      if (invoice.items.isEmpty) {
        throw const FormatException(
          'لم يتم استخراج أي سطر سلعة. أعد التصوير مع إظهار كامل الجدول وإضاءة أوضح.',
        );
      }
      return invoice;
    } catch (_) {
      rethrow;
    }
  }
}
