import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'zpl_encoder.dart';

/// How labels reach the printer on this device.
enum LabelPrinterMode {
  /// The system print dialog (any Windows/Android printer, or a PDF).
  system,

  /// ZPL sent straight to a network thermal label printer (raw port 9100).
  zplNetwork,
}

/// Label printer of this device. The printer is local hardware, so the
/// setting is stored on the device, not synced with the workshop.
class LabelPrinterSettings {
  const LabelPrinterSettings({
    this.mode = LabelPrinterMode.system,
    this.host = '',
    this.port = 9100,
    this.dpi = 203,
  });

  final LabelPrinterMode mode;
  final String host;
  final int port;

  /// Print-head resolution: 203, 300 or 600 dots per inch.
  final int dpi;

  bool get usesZpl => mode == LabelPrinterMode.zplNetwork && host.isNotEmpty;

  static const _modeKey = 'label_printer_mode';
  static const _hostKey = 'label_printer_host';
  static const _portKey = 'label_printer_port';
  static const _dpiKey = 'label_printer_dpi';

  static Future<LabelPrinterSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return LabelPrinterSettings(
      mode: prefs.getString(_modeKey) == 'zpl'
          ? LabelPrinterMode.zplNetwork
          : LabelPrinterMode.system,
      host: prefs.getString(_hostKey) ?? '',
      port: prefs.getInt(_portKey) ?? 9100,
      dpi: prefs.getInt(_dpiKey) ?? 203,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _modeKey,
      mode == LabelPrinterMode.zplNetwork ? 'zpl' : 'system',
    );
    await prefs.setString(_hostKey, host.trim());
    await prefs.setInt(_portKey, port);
    await prefs.setInt(_dpiKey, dpi);
  }

  LabelPrinterSettings copyWith({
    LabelPrinterMode? mode,
    String? host,
    int? port,
    int? dpi,
  }) => LabelPrinterSettings(
    mode: mode ?? this.mode,
    host: host ?? this.host,
    port: port ?? this.port,
    dpi: dpi ?? this.dpi,
  );
}

/// Prints label documents (one PDF page per label) with the device's label
/// printer: the system dialog, or ZPL straight to a thermal printer.
class LabelPrintService {
  /// Prints [document] (one page per label).
  static Future<void> printLabels(
    pw.Document document, {
    required PdfPageFormat format,
    required String name,
    LabelPrinterSettings? settings,
  }) async {
    final printer = settings ?? await LabelPrinterSettings.load();
    final bytes = await document.save();
    if (!printer.usesZpl || kIsWeb) {
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: name,
        format: format,
        dynamicLayout: false,
        usePrinterSettings: true,
      );
      return;
    }
    final zpl = await zplFromPdf(bytes, dpi: printer.dpi);
    await sendToNetworkPrinter(printer.host, printer.port, zpl);
  }

  /// ZPL for every page of a label PDF, rendered at the printer resolution.
  static Future<String> zplFromPdf(Uint8List pdf, {required int dpi}) async {
    final out = StringBuffer();
    await for (final page in Printing.raster(pdf, dpi: dpi.toDouble())) {
      final dots = monochromeFromRgba(page.pixels, page.width, page.height);
      out.write(
        zplLabelFromDots(width: page.width, height: page.height, dots: dots),
      );
    }
    return out.toString();
  }

  /// Sends raw printer data to [host]:[port] (port 9100 on most label
  /// printers).
  static Future<void> sendToNetworkPrinter(
    String host,
    int port,
    String data,
  ) async {
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 5),
    );
    try {
      socket.add(Uint8List.fromList(data.codeUnits));
      await socket.flush();
    } finally {
      await socket.close();
    }
  }
}
