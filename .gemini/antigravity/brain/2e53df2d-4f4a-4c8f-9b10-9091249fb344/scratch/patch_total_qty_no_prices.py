import re

path_pdf = r'c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\Commande\pdf_invoice_api.dart'
path_preview = r'c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\Commande\devis_preview_screen.dart'

# ────────────────────────────────────────────────────
# 1. Update devis_preview_screen.dart
# ────────────────────────────────────────────────────
with open(path_preview, 'r', encoding='utf-8') as f:
    code_preview = f.read()

# Update scrollview build list to include _buildTotalQuantityPreview
OLD_PREVIEW_BUILD = """                        if (!data.hidePrices) ...[
                          _buildAmountInWords(),
                          const SizedBox(height: 12),
                          _buildTotals(),
                        ],"""

NEW_PREVIEW_BUILD = """                        if (!data.hidePrices) ...[
                          _buildAmountInWords(),
                          const SizedBox(height: 12),
                          _buildTotals(),
                        ] else ...[
                          const SizedBox(height: 12),
                          _buildTotalQuantityPreview(),
                        ],"""

assert OLD_PREVIEW_BUILD in code_preview, "Scroll view build list target not found in devis_preview_screen"
code_preview = code_preview.replace(OLD_PREVIEW_BUILD, NEW_PREVIEW_BUILD, 1)

# Add _buildTotalQuantityPreview method right before _buildAmountInWords
OLD_METHOD_ANCHOR = """  Widget _buildAmountInWords() {"""
NEW_METHOD = """  Widget _buildTotalQuantityPreview() {
    final int totalQty = data.items
        .where((i) => !i.isReplaced)
        .fold(0, (s, i) => s + i.quantity);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            t('Quantité Totale / مجموع الكميات'),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          Text(
            '$totalQty',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _blue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountInWords() {"""

assert OLD_METHOD_ANCHOR in code_preview, "_buildAmountInWords method not found in devis_preview_screen"
code_preview = code_preview.replace(OLD_METHOD_ANCHOR, NEW_METHOD, 1)

with open(path_preview, 'w', encoding='utf-8') as f:
    f.write(code_preview)
print("devis_preview_screen.dart updated with total quantity preview block.")

# ────────────────────────────────────────────────────
# 2. Update pdf_invoice_api.dart
# ────────────────────────────────────────────────────
with open(path_pdf, 'r', encoding='utf-8') as f:
    code_pdf = f.read()

# Update build list to show _buildTotalQtyBlock
OLD_PDF_BUILD = """          if (!data.hidePrices) ...[
            pw.SizedBox(height: 16),
            pw.Text(
              'Arrêtée la présente facture à la somme de: ${data.amountInWords}.',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 10),
            _buildTotals(data),
          ],"""

NEW_PDF_BUILD = """          if (!data.hidePrices) ...[
            pw.SizedBox(height: 16),
            pw.Text(
              'Arrêtée la présente facture à la somme de: ${data.amountInWords}.',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 10),
            _buildTotals(data),
          ] else ...[
            pw.SizedBox(height: 16),
            _buildTotalQtyBlock(data),
          ],"""

assert OLD_PDF_BUILD in code_pdf, "build list target not found in pdf_invoice_api"
code_pdf = code_pdf.replace(OLD_PDF_BUILD, NEW_PDF_BUILD, 1)

# Add _buildTotalQtyBlock method right before _buildTotals
OLD_TOTALS_ANCHOR = """  static pw.Widget _buildTotals(DevisData data) {"""
NEW_TOTALS = """  static pw.Widget _buildTotalQtyBlock(DevisData data) {
    final int totalQty = data.items
        .where((i) => !i.isReplaced)
        .fold(0, (s, i) => s + i.quantity);

    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 220,
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: pw.BoxDecoration(
          color: _blue,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              _ar(t('Quantité Totale')),
              textDirection: _dir(t('Quantité Totale')),
              style: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
              ),
            ),
            pw.Text(
              '$totalQty',
              style: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildTotals(DevisData data) {"""

assert OLD_TOTALS_ANCHOR in code_pdf, "_buildTotals method not found in pdf_invoice_api"
code_pdf = code_pdf.replace(OLD_TOTALS_ANCHOR, NEW_TOTALS, 1)

with open(path_pdf, 'w', encoding='utf-8') as f:
    f.write(code_pdf)
print("pdf_invoice_api.dart updated with total quantity PDF block.")
