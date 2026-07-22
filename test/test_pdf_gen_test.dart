import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/Commande/devis_builder.dart';
import 'package:database_data/Commande/pdf_invoice_api.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  test('PDF generation test with 10 items and real asset images', () async {
    print(
      "Starting PDF generation test with 10 items and real asset images...",
    );
    final workshop = DevisWorkshopInfo(
      name: "ورشة التجربة",
      phone: "0123456789",
      address: "الجزائر",
    );

    // Use an existing real image from assets
    final assetImageFile = File("assets/images/wood_texture.png");
    expect(
      assetImageFile.existsSync(),
      isTrue,
      reason: "wood_texture.png should exist in assets",
    );

    final items = List.generate(10, (i) {
      final isReplaced = i % 3 == 0; // 0, 3, 6, 9 are replaced
      return DevisLineItem(
        imagePath: assetImageFile.path,
        title: "العنصر رقم ${i + 1}",
        details: List.generate(
          6,
          (j) =>
              "التفصيل رقم ${j + 1} للمنتج رقم ${i + 1} - مع تفاصيل لتكبير الارتفاع",
        ),
        unitPrice: 1000.0 * (i + 1),
        quantity: 1,
        isReplaced: isReplaced,
        replacementReason: isReplaced ? "سبب التعديل للعنصر ${i + 1}" : "",
      );
    });

    final data = DevisData(
      orderId: 123,
      orderDate: "2026-06-25",
      validUntil: "2026-07-09",
      workshop: workshop,
      clientName: "أحمد بن علي",
      clientPhone: "0770123456",
      items: items,
      totalBrut: 55000.0,
      remise: 2000.0,
      totalHT: 53000.0,
      tvaPercent: 19.0,
      tvaAmount: 10070.0,
      totalTTC: 63070.0,
      amountPaid: 20000.0,
      totalBeforeTax: 20000,
      amountInWords: "soixante-trois mille soixante-dix dinars algériens",
    );

    try {
      print("Calling buildPdfBytes first time...");
      final bytes1 = await PdfInvoiceApi.buildPdfBytes(data);
      expect(bytes1.length, greaterThan(0));
      
      print("Calling buildPdfBytes second time...");
      final bytes2 = await PdfInvoiceApi.buildPdfBytes(data);
      expect(bytes2.length, greaterThan(0));

      final file = File("test_invoice_images.pdf");
      await file.writeAsBytes(bytes2);
      print(
        "PDF with real images generated successfully! Saved to ${file.absolute.path}",
      );
    } catch (e, stack) {
      print("Error generating PDF with real images: $e");
      print(stack);
      fail(e.toString());
    }
  });
}
