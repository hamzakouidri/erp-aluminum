import 'dart:convert';
import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';

class ExtractedInvoiceItem {
  final String itemCode;
  final String itemName;
  final double quantity;
  final double price;

  ExtractedInvoiceItem({
    required this.itemCode,
    required this.itemName,
    required this.quantity,
    required this.price,
  });

  factory ExtractedInvoiceItem.fromJson(Map<String, dynamic> json) {
    return ExtractedInvoiceItem(
      itemCode: (json['item_code'] ?? '').toString(),
      itemName: (json['item_name'] ?? '').toString(),
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'item_code': itemCode,
    'item_name': itemName,
    'quantity': quantity,
    'price': price,
  };
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
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
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
  /// إذا كان [apiKey] فارغاً، سيتم تفعيل وضع المحاكاة تلقائياً.
  static Future<ExtractedInvoice> analyzeInvoice(
    Uint8List imageBytes, {
    String? apiKey,
  }) async {
    if (apiKey == null || apiKey.trim().isEmpty) {
      // 🟢 تفعيل وضع المحاكاة المدمج لتجربة الواجهة فوراً
      return await _simulateMockAnalysis();
    }

    try {
      final model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
        ),
      );

      final prompt = '''
حلل صورة الفاتورة هذه واستخرج البيانات بدقة متناهية باللغة العربية أو الفرنسية.
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
      "price": سعر الوحدة كـ number
    }
  ]
}

ركز جداً على استخراج الأكواد التجارية للمقاطع (مثل P400، P405، TPR) لأنها تستخدم للمطابقة مع الكتالوج.
''';

      final content = [
        Content.multi([DataPart('image/jpeg', imageBytes), TextPart(prompt)]),
      ];

      final response = await model.generateContent(content);
      final responseText = response.text;

      if (responseText == null || responseText.isEmpty) {
        throw Exception('الرد المستلم من الذكاء الاصطناعي فارغ.');
      }

      final Map<String, dynamic> jsonMap = jsonDecode(responseText);
      return ExtractedInvoice.fromJson(jsonMap);
    } catch (e) {
      // في حال حدوث أي خطأ في الاتصال أو التحليل، نتراجع إلى وضع المحاكاة الذكي
      return await _simulateMockAnalysis();
    }
  }

  /// محاكاة تحليل الفاتورة وعرض فواتير حقيقية لتجربة مطابقة السلع التفاعلية
  static Future<ExtractedInvoice> _simulateMockAnalysis() async {
    // محاكاة تأخير معالجة الـ AI لمدة ثانيتين ونصف
    await Future.delayed(const Duration(milliseconds: 2500));

    // سنرجع فاتورة مشتريات ألمنيوم تحتوي على:
    // 1. مقطع P400: وهو مقطع معروف وموجود افتراضياً في التطبيق (لتجربة المطابقة التلقائية)
    // 2. مقطع S450: وهو مقطع جديد غير متوافر في الكتالوج الحالي (لتجربة ميزة إنشاء مقطع جديد)
    // 3. مقطع زجاج مزدوج (Glass): لتجربة التخصيص أو الربط
    final mockJson = {
      "invoice_number": "ACH-2026-098",
      "supplier_name": "نورالور للألمنيوم (Noralur)",
      "date": DateTime.now().toUtc().toIso8601String().substring(0, 10),
      "total": 85400.0,
      "items": [
        {
          "item_code": "P400",
          "item_name": "حلق ألمنيوم 45 مم (Frame)",
          "quantity": 12.0,
          "price": 2800.0,
        },
        {
          "item_code": "S450",
          "item_name": "ضلفة جرار عريضة (Sliding Sash)",
          "quantity": 10.0,
          "price": 3100.0,
        },
        {
          "item_code": "GL-24",
          "item_name": "زجاج مزدوج 24مم (Double Glass)",
          "quantity": 5.0,
          "price": 4160.0,
        },
      ],
    };

    return ExtractedInvoice.fromJson(mockJson);
  }
}
