import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../Screen/tempered_glass_work_screen.dart';
import '../arabic_reshaper/arabic_reshaper.dart';
import '../services/pdf_font_cache.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../Commande/devis_builder.dart';

class GlassFabricationPdfService {
  static const PdfColor _primaryColor = PdfColor.fromInt(0xFF00695C); // Deep Teal / Cyan shade 800
  static const PdfColor _accentColor = PdfColor.fromInt(0xFFE65100);  // Deep Orange
  static const PdfColor _lightBg = PdfColor.fromInt(0xFFF1F5F9);      // Slate 100
  static const PdfColor _darkText = PdfColor.fromInt(0xFF1E293B);     // Slate 800

  static String _shapeText(String text) {
    if (!RegExp(r'[\u0600-\u06FF]').hasMatch(text)) return text;
    final reshaped = ArabicReshaper.instance.reshape(text);
    final tokens = reshaped.split(' ');
    final processed = tokens.map((token) {
      if (RegExp(r'[\u0600-\u06FF]').hasMatch(token)) {
        return String.fromCharCodes(token.runes.toList().reversed);
      }
      return token;
    }).toList();
    return processed.reversed.join(' ');
  }

  static pw.Text _pText(
    String text, {
    pw.TextStyle? style,
    pw.TextAlign? align,
  }) {
    return pw.Text(
      _shapeText(text),
      style: style,
      textDirection: pw.TextDirection.ltr,
      textAlign: align ?? pw.TextAlign.left,
    );
  }

  static Future<Uint8List> buildPdfBytes({
    required List<Map<String, dynamic>> payloads,
    String clientName = '',
    String clientPhone = '',
    String orderNumber = '',
    AppLanguage lang = AppLanguage.arabic,
  }) async {
    final fonts = await PdfFontCache.load();
    final workshop = await DevisBuilder.loadWorkshopInfo();
    final pdf = pw.Document();

    final baseStyle = pw.TextStyle(font: fonts.regular, fontSize: 8.5, color: _darkText);
    final boldStyle = pw.TextStyle(font: fonts.bold, fontSize: 8.5, color: _darkText);
    final smallStyle = pw.TextStyle(font: fonts.regular, fontSize: 7.5, color: PdfColors.blueGrey700);

    for (var i = 0; i < payloads.length; i++) {
      final payload = payloads[i];
      final pieceNum = i + 1;
      final totalPieces = payloads.length;

      Uint8List? drawingPng;
      try {
        drawingPng = await TemperedGlassWorkScreen.renderToPng(
          payload,
          maxSide: 2600,
          showHandles: false, // لا تظهر المقابض في الفيش دو فابريكاسيون
          fabricationOnly: true,
        );
      } catch (e) {
        debugPrint('Error rendering glass drawing for PDF: $e');
      }

      final pw.MemoryImage? drawingImage =
          (drawingPng != null && drawingPng.isNotEmpty) ? pw.MemoryImage(drawingPng) : null;

      final overallW = (payload['overallWidthMm'] as num?)?.toDouble() ??
          (payload['widthMm'] as num?)?.toDouble() ??
          0.0;
      final overallH = (payload['overallHeightMm'] as num?)?.toDouble() ??
          (payload['heightMm'] as num?)?.toDouble() ??
          0.0;

      final glassType = payload['glassTypeLabel']?.toString() ??
          payload['glassType']?.toString() ??
          (lang == AppLanguage.arabic ? 'شفاف' : 'Clair');
      // A missing value is printed as missing: a default thickness on a
      // factory sheet looks like real data and gets manufactured.
      final thickness = ((payload['glassThicknessMm'] ?? payload['thicknessMm']) as num?)?.toDouble();
      final isTempered = payload['glassTempered'] != false;
      final edgeFinish = payload['edgeFinishLabel']?.toString() ??
          payload['edgeFinish']?.toString() ??
          (lang == AppLanguage.arabic ? 'ناعم (بولي)' : 'Poli');
      final workType = payload['workTypeLabel']?.toString() ??
          payload['itemTitle']?.toString() ??
          (lang == AppLanguage.arabic ? 'زجاج مقسى' : 'Verre trempé');

      final sablageMode = payload['sablageMode']?.toString() ?? 'none';
      final sablageRegions = (payload['sablageRegions'] as List?) ?? const [];
      final sablageBands = (payload['sablageBands'] as List?) ?? const [];
      String sablageDesc;
      if (sablageMode == 'none') {
        sablageDesc = lang == AppLanguage.arabic ? 'بدون تعتيم' : 'Sans sablage';
      } else if (sablageMode == 'full') {
        sablageDesc = lang == AppLanguage.arabic ? 'تعتيم كامل (سابلانج كامل)' : 'Sablage complet';
      } else {
        final count = sablageRegions.isNotEmpty ? sablageRegions.length : sablageBands.length;
        sablageDesc = lang == AppLanguage.arabic
            ? 'سابلانج أشرطة ($count مناطق)'
            : 'Sablage décoratif ($count bandes)';
      }

      // Extract and sort panels left-to-right
      final rawPanels = (payload['drawingPanels'] ?? payload['items']) as List?;
      final panelsList = <Map<String, dynamic>>[];
      if (rawPanels != null) {
        for (final p in rawPanels) {
          if (p is Map) panelsList.add(Map<String, dynamic>.from(p));
        }
      }
      panelsList.sort((a, b) {
        final aLeft = (a['left'] as num?)?.toDouble() ?? 0.0;
        final bLeft = (b['left'] as num?)?.toDouble() ?? 0.0;
        return aLeft.compareTo(bLeft);
      });

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // ── HEADER ──
                _buildHeader(
                  workshop: workshop,
                  clientName: clientName,
                  clientPhone: clientPhone,
                  orderNumber: orderNumber,
                  workType: workType,
                  pieceNum: pieceNum,
                  totalPieces: totalPieces,
                  lang: lang,
                  fonts: fonts,
                ),
                pw.SizedBox(height: 5),

                // ── SPECIFICATIONS BAR ──
                _buildSpecsBar(
                  glassType: glassType,
                  thickness: thickness,
                  isTempered: isTempered,
                  edgeFinish: edgeFinish,
                  overallW: overallW,
                  overallH: overallH,
                  sablageDesc: sablageDesc,
                  holeReference: payload['holeDimensionMode'] == 'center'
                      ? switch (lang) {
                          AppLanguage.arabic => 'من مركز الثقب',
                          AppLanguage.french => "À l'axe du trou",
                          _ => 'To the hole centre',
                        }
                      : switch (lang) {
                          AppLanguage.arabic => 'من حافة الثقب',
                          AppLanguage.french => 'Au bord du trou',
                          _ => 'To the hole edge',
                        },
                  lang: lang,
                  fonts: fonts,
                ),
                pw.SizedBox(height: 6),

                // ── MAIN DRAWING + LATERAL PANEL SPECIFICATIONS ──
                pw.Expanded(
                  child: _buildMainBody(
                    drawingImage: drawingImage,
                    panels: panelsList,
                    lang: lang,
                    fonts: fonts,
                    baseStyle: baseStyle,
                    boldStyle: boldStyle,
                    smallStyle: smallStyle,
                  ),
                ),
                pw.SizedBox(height: 4),

                // ── FOOTER ──
                _buildFooter(
                  notes: payload['notes']?.toString() ?? '',
                  pieceNum: pieceNum,
                  totalPieces: totalPieces,
                  lang: lang,
                  fonts: fonts,
                ),
              ],
            );
          },
        ),
      );
    }

    return pdf.save();
  }

  static pw.Widget _buildHeader({
    required dynamic workshop,
    required String clientName,
    required String clientPhone,
    required String orderNumber,
    required String workType,
    required int pieceNum,
    required int totalPieces,
    required AppLanguage lang,
    required PdfFontBundle fonts,
  }) {
    final title = lang == AppLanguage.arabic
        ? 'ورقة تصنيع الزجاج المقسى'
        : 'FICHE DE FABRICATION - VERRE TREMPÉ';

    final orderLabel = orderNumber.isNotEmpty
        ? (lang == AppLanguage.arabic ? 'طلب رقم: #$orderNumber' : 'Commande: #$orderNumber')
        : '';
    final clientLabel = clientName.isNotEmpty
        ? (lang == AppLanguage.arabic ? 'العميل: $clientName' : 'Client: $clientName')
        : '';
    final pieceLabel = totalPieces > 1
        ? (lang == AppLanguage.arabic ? 'القطعة $pieceNum من $totalPieces' : 'Pièce $pieceNum / $totalPieces')
        : '';

    final workshopName = workshop.name.toString().trim();
    final workshopPhone = workshop.phone.toString().trim();

    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _primaryColor, width: 1.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Left: Workshop
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (workshopName.isNotEmpty)
                _pText(
                  workshopName,
                  style: pw.TextStyle(font: fonts.bold, fontSize: 11, color: _primaryColor),
                ),
              if (workshopPhone.isNotEmpty)
                _pText(
                  workshopPhone,
                  style: pw.TextStyle(font: fonts.regular, fontSize: 8, color: PdfColors.grey700),
                ),
            ],
          ),

          // Center: Title + Piece Badge
          pw.Column(
            children: [
              _pText(
                title,
                style: pw.TextStyle(font: fonts.bold, fontSize: 13, color: _primaryColor),
              ),
              pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  _pText(
                    workType,
                    style: pw.TextStyle(font: fonts.bold, fontSize: 10, color: _accentColor),
                  ),
                  if (pieceLabel.isNotEmpty) ...[
                    pw.SizedBox(width: 8),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: pw.BoxDecoration(
                        color: _primaryColor,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                      ),
                      child: _pText(
                        pieceLabel,
                        style: pw.TextStyle(font: fonts.bold, fontSize: 8, color: PdfColors.white),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),

          // Right: Client & Order
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              if (orderLabel.isNotEmpty)
                _pText(
                  orderLabel,
                  style: pw.TextStyle(font: fonts.bold, fontSize: 9.5, color: _primaryColor),
                ),
              if (clientLabel.isNotEmpty)
                _pText(
                  clientLabel,
                  style: pw.TextStyle(font: fonts.bold, fontSize: 9, color: _darkText),
                ),
              if (clientPhone.isNotEmpty)
                _pText(
                  clientPhone,
                  style: pw.TextStyle(font: fonts.regular, fontSize: 8, color: PdfColors.grey700),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSpecsBar({
    required String glassType,
    required double? thickness,
    required bool isTempered,
    required String edgeFinish,
    required double overallW,
    required double overallH,
    required String sablageDesc,
    required String holeReference,
    required AppLanguage lang,
    required PdfFontBundle fonts,
  }) {
    final isAr = lang == AppLanguage.arabic;
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: pw.BoxDecoration(
        color: _lightBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
        border: pw.Border.all(color: PdfColors.blueGrey200, width: 0.6),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _specItem(isAr ? 'نوع الزجاج' : 'Type', glassType, fonts),
          _specDivider(),
          _specItem(isAr ? 'السمك' : 'Épaisseur', thickness == null ? '?' : '${thickness.toStringAsFixed(0)} mm', fonts),
          _specDivider(),
          _specItem(isAr ? 'مقسّى' : 'Trempé', isTempered ? (isAr ? 'نعم' : 'Oui') : (isAr ? 'لا' : 'Non'), fonts),
          _specDivider(),
          _specItem(isAr ? 'الحواف' : 'Chants', edgeFinish, fonts),
          _specDivider(),
          _specItem(
            isAr ? 'القياس الإجمالي' : 'Dimensions',
            '${overallW.toStringAsFixed(0)} × ${overallH.toStringAsFixed(0)} mm',
            fonts,
            isHighlight: true,
          ),
          _specDivider(),
          _specItem(isAr ? 'السابلانج' : 'Sablage', sablageDesc, fonts),
          _specDivider(),
          // Every hole distance is measured to this point of the hole.
          _specItem(
            isAr ? 'أبعاد الثقوب' : (lang == AppLanguage.french ? 'Cotes des trous' : 'Hole distances'),
            holeReference,
            fonts,
            isHighlight: true,
          ),
        ],
      ),
    );
  }

  static pw.Widget _specItem(String label, String value, PdfFontBundle fonts, {bool isHighlight = false}) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        _pText(
          label,
          style: pw.TextStyle(font: fonts.regular, fontSize: 7, color: PdfColors.blueGrey600),
        ),
        _pText(
          value,
          style: pw.TextStyle(
            font: fonts.bold,
            fontSize: isHighlight ? 9 : 8,
            color: isHighlight ? _primaryColor : _darkText,
          ),
        ),
      ],
    );
  }

  static pw.Widget _specDivider() {
    return pw.Container(
      width: 0.6,
      height: 16,
      color: PdfColors.blueGrey300,
      margin: const pw.EdgeInsets.symmetric(horizontal: 4),
    );
  }

  static pw.Widget _buildMainBody({
    required pw.MemoryImage? drawingImage,
    required List<Map<String, dynamic>> panels,
    required AppLanguage lang,
    required PdfFontBundle fonts,
    required pw.TextStyle baseStyle,
    required pw.TextStyle boldStyle,
    required pw.TextStyle smallStyle,
  }) {
    // If we have exactly 2 panels (e.g. Left Panel & Right Panel):
    // Put Left Panel details on the left, Drawing in the center, Right Panel details on the right!
    if (panels.length == 2) {
      final leftPanel = panels[0];
      final rightPanel = panels[1];

      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // Left Lateral Column: Left Panel Holes
          pw.Container(
            width: 145,
            margin: const pw.EdgeInsets.only(right: 6),
            child: _buildPanelCard(leftPanel, 0, lang, fonts, isLeftSide: true),
          ),

          // Center: HUGE GLASS DRAWING
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.all(4),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.blueGrey200, width: 0.8),
              ),
              child: drawingImage != null
                  ? pw.Center(child: pw.Image(drawingImage, fit: pw.BoxFit.contain))
                  : pw.Center(child: _pText('رسم الزجاج', style: boldStyle)),
            ),
          ),

          // Right Lateral Column: Right Panel Holes
          pw.Container(
            width: 145,
            margin: const pw.EdgeInsets.only(left: 6),
            child: _buildPanelCard(rightPanel, 1, lang, fonts, isLeftSide: false),
          ),
        ],
      );
    }

    // If 1 panel:
    if (panels.length <= 1) {
      final panel = panels.isNotEmpty ? panels[0] : null;
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          if (panel != null && (panel['holes'] as List?)?.isNotEmpty == true)
            pw.Container(
              width: 160,
              margin: const pw.EdgeInsets.only(right: 8),
              child: _buildPanelCard(panel, 0, lang, fonts, isLeftSide: true),
            ),
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.all(4),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.blueGrey200, width: 0.8),
              ),
              child: drawingImage != null
                  ? pw.Center(child: pw.Image(drawingImage, fit: pw.BoxFit.contain))
                  : pw.Center(child: _pText('رسم الزجاج', style: boldStyle)),
            ),
          ),
        ],
      );
    }

    // If 3+ panels: Drawing on top, panels cards below
    return pw.Column(
      children: [
        pw.Expanded(
          flex: 7,
          child: pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(4),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              border: pw.Border.all(color: PdfColors.blueGrey200, width: 0.8),
            ),
            child: drawingImage != null
                ? pw.Center(child: pw.Image(drawingImage, fit: pw.BoxFit.contain))
                : pw.Center(child: _pText('رسم الزجاج', style: boldStyle)),
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Expanded(
          flex: 4,
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              for (var idx = 0; idx < panels.length; idx++) ...[
                if (idx > 0) pw.SizedBox(width: 6),
                pw.Expanded(
                  child: _buildPanelCard(panels[idx], idx, lang, fonts),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildPanelCard(
    Map<String, dynamic> panel,
    int index,
    AppLanguage lang,
    PdfFontBundle fonts, {
    bool? isLeftSide,
  }) {
    final role = panel['role']?.toString() ?? 'panel';
    final isAr = lang == AppLanguage.arabic;
    String roleLabel;
    if (role == 'door') {
      roleLabel = isAr ? 'باب (Porte)' : 'Porte (Door)';
    } else if (role == 'fixed') {
      roleLabel = isAr ? 'ثابت (Fixe)' : 'Fixe (Fixed)';
    } else {
      roleLabel = isAr ? 'لوح زجاج' : 'Panneau';
    }

    String sideHint = '';
    if (isLeftSide == true) {
      sideHint = isAr ? ' [الجهة اليسرى]' : ' [Côté gauche]';
    } else if (isLeftSide == false) {
      sideHint = isAr ? ' [الجهة اليمنى]' : ' [Côté droit]';
    }

    final pW = (panel['widthMm'] as num?)?.toDouble() ?? 0.0;
    final pH = (panel['heightMm'] as num?)?.toDouble() ?? 0.0;

    final holesList = <Map<String, dynamic>>[];
    final rawHoles = panel['holes'] as List?;
    if (rawHoles != null) {
      for (final h in rawHoles) {
        if (h is Map) holesList.add(Map<String, dynamic>.from(h));
      }
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
        border: pw.Border.all(color: PdfColors.blueGrey300, width: 0.7),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // Panel Title
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            decoration: pw.BoxDecoration(
              color: _primaryColor,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _pText(
                  '${index + 1}. $roleLabel$sideHint',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 8, color: PdfColors.white),
                ),
                _pText(
                  '${pW.toStringAsFixed(0)} × ${pH.toStringAsFixed(0)}',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 7.5, color: PdfColors.white),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 4),

          // Holes Header
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _pText(
                isAr ? 'جدول الثقوب:' : 'Perçages:',
                style: pw.TextStyle(font: fonts.bold, fontSize: 7.5, color: _accentColor),
              ),
              _pText(
                holesList.isEmpty
                    ? (isAr ? 'بدون ثقوب' : 'Sans trou')
                    : '${holesList.length} ${isAr ? "ثقوب" : "trous"}',
                style: pw.TextStyle(
                  font: fonts.regular,
                  fontSize: 7,
                  color: holesList.isEmpty ? PdfColors.grey600 : _accentColor,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 2),

          // Table of Holes
          if (holesList.isNotEmpty) ...[
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
              color: _lightBg,
              child: pw.Row(
                children: [
                  pw.SizedBox(width: 18, child: _pText('#', style: pw.TextStyle(font: fonts.bold, fontSize: 6.5))),
                  pw.SizedBox(width: 32, child: _pText('Ø mm', style: pw.TextStyle(font: fonts.bold, fontSize: 6.5))),
                  pw.Expanded(child: _pText('X mm', style: pw.TextStyle(font: fonts.bold, fontSize: 6.5))),
                  pw.Expanded(child: _pText('Y mm', style: pw.TextStyle(font: fonts.bold, fontSize: 6.5))),
                ],
              ),
            ),
            pw.Expanded(
              child: pw.ListView.builder(
                itemCount: holesList.length,
                itemBuilder: (context, hIdx) {
                  final h = holesList[hIdx];
                  final dia = (h['diameterMm'] as num?)?.toDouble();
                  final x = (h['xMm'] as num?)?.toDouble();
                  final y = (h['yMm'] as num?)?.toDouble();
                  String mm(double? value) => value == null ? '?' : value.toStringAsFixed(0);
                  final isEven = hIdx % 2 == 0;

                  return pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1.8),
                    color: isEven ? PdfColors.white : PdfColors.grey50,
                    child: pw.Row(
                      children: [
                        pw.SizedBox(
                          width: 18,
                          child: _pText(
                            '#${hIdx + 1}',
                            style: pw.TextStyle(font: fonts.bold, fontSize: 6.5, color: _accentColor),
                          ),
                        ),
                        pw.SizedBox(
                          width: 32,
                          child: _pText(
                            'Ø${mm(dia)}',
                            style: pw.TextStyle(font: fonts.bold, fontSize: 6.5, color: _darkText),
                          ),
                        ),
                        pw.Expanded(
                          child: _pText(
                            mm(x),
                            style: pw.TextStyle(font: fonts.regular, fontSize: 6.5, color: _darkText),
                          ),
                        ),
                        pw.Expanded(
                          child: _pText(
                            mm(y),
                            style: pw.TextStyle(font: fonts.regular, fontSize: 6.5, color: _darkText),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ] else ...[
            pw.Expanded(
              child: pw.Center(
                child: _pText(
                  isAr ? 'لوح زجاجي مصمت بدون أي ثقوب' : 'Panneau sans aucun perçage',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 7, color: PdfColors.grey500),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _buildFooter({
    required String notes,
    required int pieceNum,
    required int totalPieces,
    required AppLanguage lang,
    required PdfFontBundle fonts,
  }) {
    final isAr = lang == AppLanguage.arabic;
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 3),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.blueGrey300, width: 0.6)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _pText(
            isAr
                ? 'ملاحظة: المقابض غير مرسومة لأن الثقوب هي الأساس في التصنيع والقص.'
                : 'Note: Poignées masquées pour laisser les perçages dégagés pour la fabrication.',
            style: pw.TextStyle(font: fonts.regular, fontSize: 7, color: PdfColors.grey600),
          ),
          _pText(
            'Page $pieceNum / $totalPieces',
            style: pw.TextStyle(font: fonts.bold, fontSize: 7.5, color: _primaryColor),
          ),
        ],
      ),
    );
  }

  static Future<void> printPdf(Uint8List bytes, String filename) async {
    await Printing.layoutPdf(name: filename, onLayout: (_) async => bytes);
  }

  static Future<void> sharePdf(Uint8List bytes, String filename) async {
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }

  static Future<String?> savePdf(Uint8List bytes, String filename) async {
    if (Platform.isWindows) {
      final picked = await FilePicker.saveFile(
        dialogTitle: filename,
        fileName: filename,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (picked == null) return null;
      await File(picked).writeAsBytes(bytes);
      return picked;
    }

    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}${Platform.pathSeparator}$filename');
    await tempFile.writeAsBytes(bytes);
    return FlutterFileDialog.saveFile(
      params: SaveFileDialogParams(sourceFilePath: tempFile.path),
    );
  }
}

/// Screen with scrolling pages for previewing, saving, printing, and sharing
/// glass fabrication sheets.
class GlassFabricationPreviewScreen extends StatefulWidget {
  const GlassFabricationPreviewScreen({
    super.key,
    required this.payloads,
    this.clientName = '',
    this.clientPhone = '',
    this.orderNumber = '',
  });

  final List<Map<String, dynamic>> payloads;
  final String clientName;
  final String clientPhone;
  final String orderNumber;

  @override
  State<GlassFabricationPreviewScreen> createState() => _GlassFabricationPreviewScreenState();
}

class _GlassFabricationPreviewScreenState extends State<GlassFabricationPreviewScreen> {
  Uint8List? _pdfBytes;
  bool _isBusy = false;

  String _filename(AppLanguage lang) {
    final order = widget.orderNumber.isNotEmpty ? 'cmd_${widget.orderNumber}' : 'verre';
    final client = widget.clientName.trim().replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
    return 'fiche_fabrication_verre_${order}_$client.pdf';
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final isMultiple = widget.payloads.length > 1;

    final title = isMultiple
        ? Localization.translate(
            'ورقة تصنيع زجاج الطلبية (${widget.payloads.length} قطع)',
            lang,
          )
        : Localization.translate('ورقة تصنيع الزجاج (PDF)', lang);

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF00695C),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: Localization.translate('حفظ PDF', lang),
            icon: _isBusy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_alt_rounded),
            onPressed: _isBusy ? null : () => _handleSave(lang),
          ),
          IconButton(
            tooltip: Localization.translate('مشاركة PDF', lang),
            icon: const Icon(Icons.share_rounded),
            onPressed: _isBusy ? null : () => _handleShare(lang),
          ),
          IconButton(
            tooltip: Localization.translate('طباعة PDF', lang),
            icon: const Icon(Icons.print_rounded),
            onPressed: _isBusy ? null : () => _handlePrint(lang),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: PdfPreview(
        build: (format) async {
          final bytes = await GlassFabricationPdfService.buildPdfBytes(
            payloads: widget.payloads,
            clientName: widget.clientName,
            clientPhone: widget.clientPhone,
            orderNumber: widget.orderNumber,
            lang: lang,
          );
          _pdfBytes = bytes;
          return bytes;
        },
        canChangePageFormat: false,
        canChangeOrientation: false,
        allowPrinting: true,
        allowSharing: true,
        initialPageFormat: PdfPageFormat.a4.landscape,
        pdfFileName: _filename(lang),
        loadingWidget: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFF00695C)),
              const SizedBox(height: 16),
              Text(
                Localization.translate('جاري إعداد ورقة تصنيع الزجاج...', lang),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Uint8List> _ensurePdfBytes(AppLanguage lang) async {
    if (_pdfBytes != null) return _pdfBytes!;
    final bytes = await GlassFabricationPdfService.buildPdfBytes(
      payloads: widget.payloads,
      clientName: widget.clientName,
      clientPhone: widget.clientPhone,
      orderNumber: widget.orderNumber,
      lang: lang,
    );
    _pdfBytes = bytes;
    return bytes;
  }

  Future<void> _handleSave(AppLanguage lang) async {
    setState(() => _isBusy = true);
    try {
      final bytes = await _ensurePdfBytes(lang);
      final path = await GlassFabricationPdfService.savePdf(bytes, _filename(lang));
      if (!mounted) return;
      if (path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(Localization.translate('تم حفظ ملف التصنيع بنجاح', lang)),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _handleShare(AppLanguage lang) async {
    setState(() => _isBusy = true);
    try {
      final bytes = await _ensurePdfBytes(lang);
      await GlassFabricationPdfService.sharePdf(bytes, _filename(lang));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _handlePrint(AppLanguage lang) async {
    setState(() => _isBusy = true);
    try {
      final bytes = await _ensurePdfBytes(lang);
      await GlassFabricationPdfService.printPdf(bytes, _filename(lang));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }
}
