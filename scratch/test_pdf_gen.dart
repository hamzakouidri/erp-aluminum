import 'dart:io';
import '../lib/Commande/devis_builder.dart';
import '../lib/Commande/pdf_invoice_api.dart';

void main() async {
  print("Starting PDF generation test...");
  final workshop = DevisWorkshopInfo(
    name: "ورشة التجربة",
    phone: "0123456789",
    address: "الجزائر",
  );
  final items = [
    DevisLineItem(
      imagePath: null,
      title: "نافذة منزلقة غرفتين",
      details: [
        "نظام منزلق (Coulissant)",
        "Série 140",
        "Largeur: 1200 mm",
        "Hauteur: 1200 mm",
        "اللون: Blanc",
      ],
      unitPrice: 15000.0,
      quantity: 2,
      isReplaced: true,
      replacementReason: "تغيير المقاس بطلب من الزبون",
    ),
    DevisLineItem(
      imagePath: null,
      title: "نافذة مفصلية باب واحد",
      details: [
        "نظام مفصلي (Battant)",
        "Épaisseur: 1.5 mm",
        "Largeur: 800 mm",
        "Hauteur: 2100 mm",
        "اللون: Noir",
      ],
      unitPrice: 18000.0,
      quantity: 1,
      isReplaced: false,
    ),
    DevisLineItem(
      imagePath: null,
      title: "باب المنيوم خارجي",
      details: [
        "نظام مفصلي (Battant)",
        "Largeur: 900 mm",
        "Hauteur: 2200 mm",
        "اللون: Gris",
      ],
      unitPrice: 25000.0,
      quantity: 1,
      isReplaced: true,
      replacementReason: "تعديل الموديل والشكل الخارجي",
    ),
    DevisLineItem(
      imagePath: null,
      title: "شباك حماية حديدي",
      details: ["حديد حماية", "Largeur: 1200 mm", "Hauteur: 1200 mm"],
      unitPrice: 5000.0,
      quantity: 2,
      isReplaced: false,
    ),
  ];

  final data = DevisData(
    orderId: 123,
    orderDate: "2026-06-25",
    validUntil: "2026-07-09",
    workshop: workshop,
    clientName: "أحمد بن علي",
    clientPhone: "0770123456",
    items: items,
    totalBrut: 58000.0,
    remise: 2000.0,
    totalHT: 56000.0,
    tvaPercent: 19.0,
    tvaAmount: 10640.0,
    totalTTC: 66640.0,
    amountPaid: 20000.0,
    totalBeforeTax: 20000.0,
    amountInWords: "soixante-six mille six cent quarante dinars algériens",
  );

  try {
    final bytes = await PdfInvoiceApi.buildPdfBytes(data);
    final file = File("test_invoice.pdf");
    await file.writeAsBytes(bytes);
    print("PDF generated successfully! Saved to ${file.absolute.path}");
  } catch (e, stack) {
    print("Error generating PDF: $e");
    print(stack);
  }
}
