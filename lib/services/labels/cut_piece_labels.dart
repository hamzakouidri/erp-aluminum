import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../settings/app_settings.dart';
import '../../settings/localization.dart';
import '../cutting_optimizer_engine.dart';

/// What one cut-piece label shows. Labels follow the cutting order (profile,
/// then bar, then the cuts along the bar), so the operator sticks them on
/// the pieces as they come off the saw.
class CutPieceLabel {
  const CutPieceLabel({
    required this.barcode,
    required this.orderName,
    required this.windowName,
    required this.profileName,
    required this.profileCode,
    required this.color,
    required this.lengthMm,
    required this.angleLeft,
    required this.angleRight,
    required this.barNumber,
    required this.cutNumber,
    required this.cutsOnBar,
  });

  /// ASCII only (Code128): `CP-<order>-<profile>.<bar>.<cut>`.
  final String barcode;
  final String orderName;
  final String windowName;
  final String profileName;
  final String profileCode;
  final String color;
  final int lengthMm;
  final int angleLeft;
  final int angleRight;
  final int barNumber;
  final int cutNumber;
  final int cutsOnBar;
}

/// One label per cut of [report], in cutting order.
List<CutPieceLabel> cutPieceLabelsFor(CuttingOptimizationReport report) {
  final labels = <CutPieceLabel>[];
  for (var g = 0; g < report.groups.length; g++) {
    final group = report.groups[g];
    for (final bar in group.bars) {
      for (var c = 0; c < bar.cuts.length; c++) {
        final piece = bar.cuts[c].piece;
        final order = piece.orderId.abs().toRadixString(36).toUpperCase();
        labels.add(
          CutPieceLabel(
            barcode: 'CP-$order-${g + 1}.${bar.barNumber}.${c + 1}',
            orderName: piece.orderName,
            windowName: piece.windowName,
            profileName: piece.profileName,
            profileCode: piece.profileCode,
            color: piece.color,
            lengthMm: piece.lengthMm.round(),
            angleLeft: piece.angleLeft,
            angleRight: piece.angleRight,
            barNumber: bar.barNumber,
            cutNumber: c + 1,
            cutsOnBar: bar.cuts.length,
          ),
        );
      }
    }
  }
  return labels;
}

/// Label pages (one per cut) for the system printer or a ZPL printer.
pw.Document cutPieceLabelsDocument(
  List<CutPieceLabel> labels, {
  required PdfPageFormat format,
  required pw.Font regular,
  required pw.Font bold,
  required AppLanguage lang,
}) {
  String t(String key) => Localization.translate(key, lang);
  final document = pw.Document();
  final direction = lang == AppLanguage.arabic
      ? pw.TextDirection.rtl
      : pw.TextDirection.ltr;
  for (final label in labels) {
    document.addPage(
      pw.Page(
        pageFormat: format,
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        textDirection: direction,
        build: (_) => pw.Container(
          padding: const pw.EdgeInsets.all(2),
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.6)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '${label.lengthMm} ${t('مم')}',
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    '${label.angleLeft}° / ${label.angleRight}°',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.Text(
                [
                  if (label.profileCode.isNotEmpty) '[${label.profileCode}]',
                  Localization.translate(label.profileName, lang),
                ].join(' '),
                maxLines: 1,
                style: pw.TextStyle(
                  fontSize: 7,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                '${label.orderName} • ${label.windowName}',
                maxLines: 1,
                style: const pw.TextStyle(fontSize: 6),
              ),
              pw.Text(
                [
                  if (label.color.isNotEmpty)
                    Localization.colorName(label.color, lang),
                  '${t('بار')} ${label.barNumber} • '
                      '${label.cutNumber}/${label.cutsOnBar}',
                ].join(' • '),
                maxLines: 1,
                style: const pw.TextStyle(fontSize: 6),
              ),
              pw.SizedBox(
                height: 9,
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.code128(),
                  data: label.barcode,
                  drawText: true,
                  textStyle: const pw.TextStyle(fontSize: 4.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  return document;
}
