import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/Commande/devis_builder.dart';
import 'package:database_data/Commande/pdf_invoice_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

DevisData _quote(List<DevisLineItem> items) => DevisData(
  orderId: 900,
  orderDate: '2026-10-21',
  validUntil: '2026-11-04',
  workshop: const DevisWorkshopInfo(
    name: 'ورشة',
    phone: '0550000000',
    address: 'الجزائر',
  ),
  clientName: 'عميل',
  clientPhone: '0550000000',
  items: items,
  totalBrut: 1,
  remise: 0,
  totalHT: 1,
  tvaPercent: 0,
  tvaAmount: 0,
  totalTTC: 1,
  amountPaid: 0,
  totalBeforeTax: 1,
  amountInWords: 'un dinar',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final image = File('assets/images/wood_texture.png').path;

  // MultiPage cannot break a single row, so a window with many details used
  // to abort the whole quote with "Widget won't fit into the page".
  for (final mode in [0, 1, 2]) {
    test('a line taller than a page still builds (image mode $mode)', () async {
      final data = _quote([
        DevisLineItem(
          imagePath: image,
          title: 'نافذة كبيرة',
          details: List.generate(90, (j) => 'تفصيل ${j + 1}'),
          unitPrice: 1000,
          quantity: 1,
        ),
      ]);
      final bytes = await PdfInvoiceApi.buildPdfBytes(data, imageMode: mode);
      expect(bytes, isNotEmpty);
    });
  }

  test('long wrapping detail lines still fit', () async {
    final data = _quote([
      DevisLineItem(
        imagePath: image,
        title: 'واجهة',
        details: List.generate(60, (j) => 'تفصيل طويل جداً ${j + 1} ' * 8),
        unitPrice: 1000,
        quantity: 2,
      ),
    ]);
    final bytes = await PdfInvoiceApi.buildPdfBytes(data, imageMode: 2);
    expect(bytes, isNotEmpty);
  });
}
