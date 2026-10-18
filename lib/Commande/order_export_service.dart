import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../sql_database.dart';

class OrderExportService {
  static const String magicHeader = 'ERP_ALUM_ORDER_EXPORT';
  static const int currentVersion = 1;

  /// Exports an order with its client and window items to an `.alum` file.
  static Future<File> exportOrderToFile(SqlDatabase db, int orderId) async {
    final order = await db.readCommandeWithClientById(orderId);
    if (order == null) {
      throw StateError('Order #$orderId not found');
    }

    final clientId = (order['client_id'] as num?)?.toInt() ?? 0;
    final clients = await db.readClient();
    final client = clients.firstWhere(
      (c) => (c['id'] as num?)?.toInt() == clientId,
      orElse: () => <String, dynamic>{},
    );

    final details = await db.readCommandeDetails(orderId);

    final prefs = await SharedPreferences.getInstance();
    final workshopName = prefs.getString('workshop_name')?.trim() ?? '';

    final payload = <String, dynamic>{
      'magic': magicHeader,
      'version': currentVersion,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'source_workshop': workshopName,
      'client': {
        'firstname': client['firstname'] ?? order['firstname'] ?? '',
        'lastname': client['lastname'] ?? order['lastname'] ?? '',
        'phone1': client['phone1'] ?? order['phone'] ?? '',
        'phone2': client['phone2'] ?? '',
        'email': client['email'] ?? '',
        'address': client['address'] ?? order['client_address'] ?? '',
      },
      'order': {
        'description': order['description'] ?? '',
        'remise': (order['remise'] as num?)?.toDouble() ?? 0.0,
        'tva': (order['tva'] as num?)?.toDouble() ?? 0.0,
        'total': (order['total'] as num?)?.toDouble() ?? 0.0,
        'net_payable': (order['net_payable'] as num?)?.toDouble() ?? 0.0,
        'status': order['status'] ?? 'Nouveau',
      },
      'items': details.map((item) {
        return <String, dynamic>{
          'largeur': (item['largeur'] as num?)?.toInt() ?? 0,
          'hauteur': (item['hauteur'] as num?)?.toInt() ?? 0,
          'game': item['game'] ?? '',
          'quantity': (item['quantity'] as num?)?.toInt() ?? 1,
          'glass': item['glass'] ?? '',
          'color': item['color'] ?? '',
          'volet': item['volet'] ?? '',
          'accessories': item['accessories'] ?? '',
          'description': item['description'] ?? '',
          'price': (item['price'] as num?)?.toDouble() ?? 0.0,
          'window_type': item['window_type'] ?? '',
          'partitions_json': item['partitions_json'] ?? '{}',
          'drawing_image_base64': item['drawing_image_base64'],
          'instances_json': item['instances_json'],
          'sort_order': (item['sort_order'] as num?)?.toInt() ?? 0,
        };
      }).toList(),
    };

    final tempDir = await getTemporaryDirectory();
    final displayCode = order['order_code'] ?? orderId;
    final clientName = (payload['client']['lastname'] ?? 'client')
        .toString()
        .replaceAll(RegExp(r'[^\w\d_\-]'), '_');
    final filename = 'commande_${displayCode}_$clientName.alum';
    final file = File(p.join(tempDir.path, filename));
    await file.writeAsString(jsonEncode(payload), flush: true);
    return file;
  }

  /// Shares the exported order file via the system share sheet (WhatsApp, email, drive, etc.).
  static Future<void> shareOrder(
    BuildContext context,
    SqlDatabase db,
    int orderId,
    AppLanguage lang,
  ) async {
    try {
      final file = await exportOrderToFile(db, orderId);
      final displayCode = orderId;
      final text = lang == AppLanguage.arabic
          ? 'ملف طلبية ألمنيوم #$displayCode لتطبيق الورشة'
          : (lang == AppLanguage.french
              ? 'Fichier commande aluminium #$displayCode'
              : 'Aluminum order file #$displayCode');

      await Share.shareXFiles(
        [XFile(file.path)],
        text: text,
        subject: text,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${Localization.translate('Erreur', lang)}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Prompts the user to pick an `.alum` or `.json` file and returns the parsed payload.
  static Future<Map<String, dynamic>?> pickOrderFile() async {
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final result = await FilePicker.pickFiles(
      type: isMobile ? FileType.any : FileType.custom,
      allowedExtensions: isMobile ? null : ['alum', 'json'],
    );

    if (result == null || result.files.isEmpty || result.files.single.path == null) {
      return null;
    }

    final filePath = result.files.single.path!;
    final ext = p.extension(filePath).toLowerCase();
    if (ext != '.alum' && ext != '.json') {
      throw const FormatException('يجب اختيار ملف بصيغة .alum أو .json');
    }

    final file = File(filePath);
    final content = await file.readAsString();
    final decoded = jsonDecode(content);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid order file structure');
    }

    // Verify minimum expected fields
    if (decoded['magic'] != magicHeader &&
        (!decoded.containsKey('order') || !decoded.containsKey('items'))) {
      throw const FormatException('Unrecognized order file format');
    }

    return decoded;
  }

  /// Finds an existing client matching phone or full name.
  static Future<Map<String, dynamic>?> findMatchingClient(
    SqlDatabase db,
    Map<String, dynamic> clientData,
  ) async {
    final clients = await db.readClient();
    final phone1 = (clientData['phone1'] ?? '').toString().trim();
    final phone2 = (clientData['phone2'] ?? '').toString().trim();
    final fn = (clientData['firstname'] ?? '').toString().trim().toLowerCase();
    final ln = (clientData['lastname'] ?? '').toString().trim().toLowerCase();

    for (final c in clients) {
      final cp1 = (c['phone1'] ?? '').toString().trim();
      final cp2 = (c['phone2'] ?? '').toString().trim();
      if (phone1.isNotEmpty && (cp1 == phone1 || cp2 == phone1)) {
        return c;
      }
      if (phone2.isNotEmpty && (cp1 == phone2 || cp2 == phone2)) {
        return c;
      }
      final cfn = (c['firstname'] ?? '').toString().trim().toLowerCase();
      final cln = (c['lastname'] ?? '').toString().trim().toLowerCase();
      if (fn.isNotEmpty && ln.isNotEmpty && cfn == fn && cln == ln) {
        return c;
      }
    }
    return null;
  }

  /// Imports the parsed payload into the SQLite database as an active order.
  static Future<int> importOrder(
    SqlDatabase db,
    Map<String, dynamic> data, {
    int? selectedClientId,
  }) async {
    final clientData = Map<String, dynamic>.from(data['client'] ?? {});
    final orderData = Map<String, dynamic>.from(data['order'] ?? {});
    final rawItems = List<dynamic>.from(data['items'] ?? []);

    if (rawItems.isEmpty) {
      throw StateError('Cannot import an empty order without items.');
    }

    int clientId;
    if (selectedClientId != null && selectedClientId > 0) {
      clientId = selectedClientId;
    } else {
      final matching = await findMatchingClient(db, clientData);
      if (matching != null && matching['id'] != null) {
        clientId = (matching['id'] as num).toInt();
      } else {
        // Create client record
        final fn = clientData['firstname']?.toString().trim() ?? '';
        final ln = clientData['lastname']?.toString().trim() ?? '';
        final p1 = clientData['phone1']?.toString().trim() ?? '';
        final p2 = clientData['phone2']?.toString().trim() ?? '';
        final em = clientData['email']?.toString().trim() ?? '';
        final ad = clientData['address']?.toString().trim() ?? '';
        clientId = await db.insertClient(
          fn.isEmpty ? 'Client' : fn,
          ln.isEmpty ? 'Imported' : ln,
          p1,
          p2,
          em,
          ad,
        );
      }
    }

    final total = (orderData['total'] as num?)?.toDouble() ?? 0.0;
    final remise = (orderData['remise'] as num?)?.toDouble() ?? 0.0;
    final tva = (orderData['tva'] as num?)?.toDouble() ?? 0.0;
    final netPayable = (orderData['net_payable'] as num?)?.toDouble() ??
        (total - remise + (((total - remise) * tva) / 100));

    final details = rawItems.map((raw) {
      final item = Map<String, dynamic>.from(raw as Map);
      return <String, dynamic>{
        'largeur': (item['largeur'] as num?)?.toInt() ?? 0,
        'hauteur': (item['hauteur'] as num?)?.toInt() ?? 0,
        'game': item['game']?.toString() ?? '',
        'quantity': (item['quantity'] as num?)?.toInt() ?? 1,
        'glass': item['glass']?.toString() ?? '',
        'color': item['color']?.toString() ?? '',
        'volet': item['volet']?.toString() ?? '',
        'accessories': item['accessories']?.toString() ?? '',
        'description': item['description']?.toString() ?? '',
        'price': (item['price'] as num?)?.toDouble() ?? 0.0,
        'window_type': item['window_type']?.toString() ?? '',
        'partitions_json': item['partitions_json']?.toString() ?? '{}',
        'drawing_image_path': '',
        if (item['drawing_image_base64'] != null)
          'drawing_image_base64': item['drawing_image_base64'],
        if (item['instances_json'] != null)
          'instances_json': item['instances_json'],
        'sort_order': (item['sort_order'] as num?)?.toInt() ?? 0,
      };
    }).toList();

    final newOrderId = await db.saveCommandeWithDetails(
      clientId: clientId,
      status: orderData['status']?.toString() ?? 'Nouveau',
      description: orderData['description']?.toString() ?? '',
      remise: remise,
      tva: tva,
      total: total,
      netPayable: netPayable,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      details: details,
    );

    return newOrderId;
  }
}
