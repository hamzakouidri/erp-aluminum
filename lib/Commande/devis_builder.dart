// Force compile sync trigger
import 'dart:convert';
import '../utils/shutter_selection.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../settings/localization.dart';
import '../settings/app_settings.dart';
import 'order_date_utils.dart';
import 'package:database_data/sql_database.dart';
import 'package:database_data/services/supabase_workshop_sync_service.dart';
import 'package:flutter/foundation.dart';

class DevisLineItem {
  final String? imagePath;
  final String? imageBase64;
  final String title;
  final List<String> details;
  final double unitPrice;
  final int quantity;
  final bool isReplaced;
  final String replacementReason;
  final int width;
  final int height;
  final String color;
  final int detailId;

  const DevisLineItem({
    required this.imagePath,
    this.imageBase64,
    required this.title,
    required this.details,
    required this.unitPrice,
    required this.quantity,
    this.isReplaced = false,
    this.replacementReason = '',
    this.width = 0,
    this.height = 0,
    this.color = '',
    this.detailId = 0,
  });
}

class DevisWorkshopInfo {
  final String name;
  final String phone;
  final String address;
  final String rc;
  final String nif;
  final String nis;
  final String ai;
  final String rib;
  final String logoBase64;

  const DevisWorkshopInfo({
    required this.name,
    required this.phone,
    required this.address,
    this.rc = '',
    this.nif = '',
    this.nis = '',
    this.ai = '',
    this.rib = '',
    this.logoBase64 = '',
  });

  static const empty = DevisWorkshopInfo(
    name: 'ورشتي',
    phone: '',
    address: '',
    rc: '',
    nif: '',
    nis: '',
    ai: '',
    rib: '',
    logoBase64: '',
  );
}

class DevisData {
  final int orderId;
  final String orderDate;
  final String validUntil;
  final DevisWorkshopInfo workshop;
  final String clientName;
  final String clientPhone;
  final List<DevisLineItem> items;
  final double totalBrut;
  final double remise;
  final double totalBeforeTax;
  final double totalHT;
  final double tvaPercent;
  final double tvaAmount;
  final double totalTTC;
  final double amountPaid;
  final String amountInWords;
  final String invoiceNote;
  final bool isPartial;
  final bool hidePrices;
  final bool isProForma;
  final String? documentTitleKey;

  // 🟢 حقول معلومات شركة الزبون الجديدة للفاتورة الرسمية
  final String clientNif;
  final String clientNis;
  final String clientRc;
  final String clientAi;
  final String chequeNumber;
  final int clientNumber;
  final int clientId;
  final int sequenceNumber;
  final int priorConfirmedWindowsCount;

  // Raw inputs for dynamic rebuilding
  final Map<String, dynamic>? rawOrder;
  final List<Map<String, dynamic>>? rawItems;

  const DevisData({
    required this.orderId,
    required this.orderDate,
    required this.validUntil,
    required this.workshop,
    required this.clientName,
    required this.clientPhone,
    required this.items,
    required this.totalBrut,
    required this.remise,
    required this.totalBeforeTax,
    required this.totalHT,
    required this.tvaPercent,
    required this.tvaAmount,
    required this.totalTTC,
    required this.amountPaid,
    required this.amountInWords,
    this.invoiceNote = '',
    this.isPartial = false,
    this.hidePrices = false,
    this.isProForma = false,
    this.documentTitleKey,
    this.clientNif = '',
    this.clientNis = '',
    this.clientRc = '',
    this.clientAi = '',
    this.chequeNumber = '',
    this.clientNumber = 0,
    this.clientId = 0,
    this.sequenceNumber = 0,
    this.priorConfirmedWindowsCount = 0,
    this.rawOrder,
    this.rawItems,
  });

  /// Human-facing reference. The database id can be a distributed timestamp
  /// and must never be printed as the client's document number.
  String get clientReference =>
      clientNumber > 0 ? clientNumber.toString().padLeft(3, '0') : '';
}

class DevisBuilder {
  static AppLanguage _currentLang = AppLanguage.arabic;

  static String t(String key) => Localization.translate(key, _currentLang);

  static double _toDouble(dynamic value) => (value as num?)?.toDouble() ?? 0.0;

  static bool _isUsableWorkshopName(String value, String code) {
    final name = value.trim();
    return name.isNotEmpty && name != code;
  }

  static Future<DevisWorkshopInfo> loadWorkshopInfo() async {
    // Workshop information is owned by Supabase. The sync service writes the
    // latest profile into these local preferences on every device, so PDFs
    // must never fall back to a duplicated Firestore profile document.
    final prefs = await SharedPreferences.getInstance();
    var workshopName = (prefs.getString('workshop_name') ?? '').trim();
    final workshopCode = (prefs.getString('workshop_code') ?? '').trim();
    if (!_isUsableWorkshopName(workshopName, workshopCode)) {
      try {
        final syncedName = await SupabaseWorkshopSyncService()
            .readWorkshopDisplayName();
        if (syncedName != null &&
            _isUsableWorkshopName(syncedName, workshopCode)) {
          workshopName = syncedName;
          await prefs.setString('workshop_name', syncedName);
        }
      } catch (_) {}
    }
    return DevisWorkshopInfo(
      // A workshop code is an internal identifier, never a printable name.
      name: _isUsableWorkshopName(workshopName, workshopCode)
          ? workshopName
          : 'ورشتي',
      phone: prefs.getString('phone') ?? '',
      address: prefs.getString('workshop_address') ?? '',
      rc: prefs.getString('workshop_rc') ?? '',
      nif: prefs.getString('workshop_nif') ?? '',
      nis: prefs.getString('workshop_nis') ?? '',
      ai: prefs.getString('workshop_ai') ?? '',
      rib: prefs.getString('workshop_rib') ?? '',
      logoBase64: prefs.getString('workshop_logo_base64') ?? '',
    );
  }

  static Future<DevisData> build({
    required Map<String, dynamic> order,
    required List<Map<String, dynamic>> items,
    DevisWorkshopInfo? workshop,
    bool isPartial = false,
    bool hidePrices = false,
    bool isProForma = false,
    String? documentTitleKey,
    AppLanguage? overrideLang,
    String chequeNumber = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    // French is the application default. Do not fall back to Arabic merely
    // because the language preference has not been written yet (for example
    // when a document is opened immediately after changing language).
    final langIndex = prefs.getInt('app_language') ?? AppLanguage.french.index;
    _currentLang = overrideLang ?? AppLanguage.values[langIndex];
    final candidate = workshop ?? await loadWorkshopInfo();
    final workshopCode = (prefs.getString('workshop_code') ?? '').trim();
    final supplier = _isUsableWorkshopName(candidate.name, workshopCode)
        ? candidate
        : await loadWorkshopInfo();
    final orderDate = _formatDisplayDate(order);
    final validUntil = _formatValidUntil(order);

    final bool isOfficialInvoice =
        isProForma ||
        documentTitleKey == 'FACTURE_VENTE' ||
        documentTitleKey == 'BON_ROUTE';
    final lineItems = items
        .map((it) => _buildLineItem(it, isOfficialInvoice: isOfficialInvoice))
        .toList();
    final totalBrut = lineItems.fold<double>(
      0.0,
      (acc, item) =>
          acc + (item.isReplaced ? 0.0 : item.unitPrice * item.quantity),
    );
    final remise = isOfficialInvoice
        ? (_toDouble(order['remise']) / 1.19)
        : _toDouble(order['remise']);
    final tvaPercent = isOfficialInvoice ? 19.0 : _toDouble(order['tva']);
    final totalBrutValue = totalBrut;
    final totalBeforeTax = totalBrutValue - remise;
    final tvaAmount = (totalBeforeTax * tvaPercent) / 100;
    final totalTTC = totalBeforeTax + tvaAmount;
    final amountPaid = _toDouble(order['advance_payment']);
    final invoiceNote = _readInvoiceNote(order);

    var firstName = order['firstname']?.toString() ?? '';
    var lastName = order['lastname']?.toString() ?? '';

    // 🟢 استعلام عن تفاصيل الزبون الجبائية عند بنائها
    String clientNif = '';
    String clientNis = '';
    String clientRc = '';
    String clientAi = '';
    int clientNumber = 0;

    final db = SqlDatabase();
    final rawClientId = order['client_id'];
    final clientId = rawClientId is num
        ? rawClientId.toInt()
        : int.tryParse(rawClientId?.toString() ?? '');
    if (clientId != null) {
      try {
        final clientRows = await db.getClientById(clientId);
        if (clientRows.isNotEmpty) {
          final clientMap = clientRows.first;
          clientNif = clientMap['nif']?.toString() ?? '';
          clientNis = clientMap['nis']?.toString() ?? '';
          clientRc = clientMap['rc']?.toString() ?? '';
          clientAi = clientMap['ai']?.toString() ?? '';
          if (firstName.isEmpty) {
            firstName = clientMap['firstname']?.toString() ?? '';
          }
          if (lastName.isEmpty) {
            lastName = clientMap['lastname']?.toString() ?? '';
          }
        }
      } catch (e) {
        debugPrint('Error getting client details in DevisBuilder: $e');
      }
      try {
        clientNumber = await db.getClientSequenceNumber(clientId);
      } catch (e) {
        debugPrint('Error getting client sequence number in DevisBuilder: $e');
      }
    }

    var clientNameVal = '$firstName $lastName'.trim();
    if (clientNameVal.isEmpty) {
      clientNameVal = order['client_name']?.toString() ?? '';
    }
    if (clientNameVal.isEmpty) {
      clientNameVal = order['client_display']?.toString() ?? '';
    }
    if (clientNameVal.isEmpty) {
      clientNameVal = _currentLang == AppLanguage.french ? 'Client' : 'الزبون';
    }

    int priorConfirmedWindowsCount = 0;
    int sequenceNumber = 0;
    final orderIdVal = order['id'] as int?;
    if (orderIdVal != null) {
      try {
        priorConfirmedWindowsCount = await db.getPriorConfirmedWindowsCount(
          orderIdVal,
        );
      } catch (e) {
        debugPrint('Error getting prior confirmed windows count: $e');
      }
      try {
        sequenceNumber = await db.getOrderSequenceNumber(orderIdVal);
      } catch (e) {
        debugPrint('Error getting order sequence number: $e');
      }
    }

    return DevisData(
      orderId: order['id'] as int,
      orderDate: orderDate,
      validUntil: validUntil,
      workshop: supplier,
      clientName: clientNameVal,
      clientPhone: order['phone']?.toString() ?? '',
      items: lineItems,
      totalBrut: totalBrutValue,
      remise: remise,
      totalBeforeTax: totalBeforeTax,
      totalHT: totalBeforeTax,
      tvaPercent: tvaPercent,
      tvaAmount: tvaAmount,
      totalTTC: totalTTC,
      amountPaid: amountPaid,
      amountInWords: amountToFrenchWords(totalTTC),
      invoiceNote: invoiceNote,
      isPartial: isPartial,
      hidePrices: hidePrices,
      isProForma: isProForma,
      documentTitleKey: documentTitleKey,
      clientNif: clientNif,
      clientNis: clientNis,
      clientRc: clientRc,
      clientAi: clientAi,
      chequeNumber: chequeNumber,
      clientNumber: clientNumber,
      clientId: clientId ?? 0,
      sequenceNumber: sequenceNumber,
      priorConfirmedWindowsCount: priorConfirmedWindowsCount,
      rawOrder: order,
      rawItems: items,
    );
  }

  static String _readInvoiceNote(Map<String, dynamic> order) {
    const keys = [
      'invoice_note',
      'invoiceNote',
      'note',
      'notes',
      'remark',
      'remarks',
      'observation',
      'description',
    ];
    for (final key in keys) {
      final value = order[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static DevisLineItem buildLineItemFromDetail(
    Map<String, dynamic> item, {
    AppLanguage? overrideLang,
    bool isOfficialInvoice = false,
    bool forceGeneratedDetails = false,
  }) {
    final previousLang = _currentLang;
    if (overrideLang != null) {
      _currentLang = overrideLang;
    }
    final prepared = forceGeneratedDetails
        ? _withoutInvoiceTableEdited(item)
        : item;
    final line = _buildLineItem(prepared, isOfficialInvoice: isOfficialInvoice);
    _currentLang = previousLang;
    return line;
  }

  static Map<String, dynamic> _withoutInvoiceTableEdited(
    Map<String, dynamic> item,
  ) {
    final copy = Map<String, dynamic>.from(item);
    final rawJson = copy['partitions_json'];
    Map<String, dynamic>? parsed;

    if (rawJson is Map<String, dynamic>) {
      parsed = Map<String, dynamic>.from(rawJson);
    } else if (rawJson is Map) {
      parsed = Map<String, dynamic>.from(rawJson);
    } else if (rawJson != null) {
      final text = rawJson.toString().trim();
      if (text.length >= 5) {
        try {
          parsed = jsonDecode(text) as Map<String, dynamic>;
        } catch (_) {}
      }
    }

    if (parsed != null) {
      parsed['invoiceTableEdited'] = false;
      copy['partitions_json'] = jsonEncode(parsed);
    }
    return copy;
  }

  static String _formatDisplayDate(Map<String, dynamic> order) {
    return formatOrderDate(
      order['created_at'],
      fallback: order['updated_at'],
      emptyLabel: DateFormat('yyyy-MM-dd').format(DateTime.now()),
    );
  }

  static String _formatValidUntil(Map<String, dynamic> order) {
    try {
      final raw = order['created_at'] ?? order['updated_at'];
      if (raw != null) {
        final base = DateTime.parse(raw.toString());
        return DateFormat(
          'yyyy-MM-dd',
        ).format(base.add(const Duration(days: 14)));
      }
    } catch (_) {}
    return DateFormat(
      'yyyy-MM-dd',
    ).format(DateTime.now().add(const Duration(days: 14)));
  }

  static String _formatFace(
    String finish,
    String color,
    String processing, {
    bool isTempered = false,
  }) {
    String res = '';
    final bool isTemp =
        processing == 'trempe' || processing == 'tempered' || isTempered;
    if (_currentLang == AppLanguage.french) {
      if (finish == 'stopSol')
        res += 'Stop Sol ';
      else if (finish == 'sable')
        res += 'Sablé ';
      else if (finish == 'martle')
        res += 'Martelé ';
      else
        res += 'Clair ';

      if (color != 'transparent' &&
          color != 'white' &&
          color != 'black' &&
          color != 'none' &&
          color.isNotEmpty &&
          color != 'null') {
        switch (color) {
          case 'blue':
            res += 'Bleu ';
            break;
          case 'blueAgc':
            res += 'Bleu Belge ';
            break;
          case 'green':
            res += 'Vert ';
            break;
          case 'brown':
            res += 'Marron ';
            break;
          case 'gray':
            res += 'Gris ';
            break;
          case 'grayAgc':
            res += 'Gris Belge ';
            break;
          default:
            res += '$color ';
            break;
        }
      }
      if (isTemp)
        res += 'Trempé ';
      else if (processing == 'lowE')
        res += 'Low-E ';
    } else if (_currentLang == AppLanguage.english) {
      if (finish == 'stopSol')
        res += 'Stop Sol ';
      else if (finish == 'sable')
        res += 'Sandblasted ';
      else if (finish == 'martle')
        res += 'Hammered ';
      else
        res += 'Clear ';

      if (color != 'transparent' &&
          color != 'white' &&
          color != 'black' &&
          color != 'none' &&
          color.isNotEmpty &&
          color != 'null') {
        switch (color) {
          case 'blue':
            res += 'Blue ';
            break;
          case 'blueAgc':
            res += 'Belgian Blue ';
            break;
          case 'green':
            res += 'Green ';
            break;
          case 'brown':
            res += 'Brown ';
            break;
          case 'gray':
            res += 'Grey ';
            break;
          case 'grayAgc':
            res += 'Belgian Grey ';
            break;
          default:
            res += '$color ';
            break;
        }
      }
      if (isTemp)
        res += 'Tempered ';
      else if (processing == 'lowE')
        res += 'Low-E ';
    } else {
      if (finish == 'stopSol')
        res += 'عاكس (Stop Sol) ';
      else if (finish == 'sable')
        res += 'رملي (Sablé) ';
      else if (finish == 'martle')
        res += 'مطرّق (Martelé) ';
      else
        res += 'شفاف ';

      if (color != 'transparent' &&
          color != 'white' &&
          color != 'black' &&
          color != 'none' &&
          color.isNotEmpty &&
          color != 'null') {
        switch (color) {
          case 'blue':
            res += 'أزرق ';
            break;
          case 'blueAgc':
            res += 'أزرق بلجيكي ';
            break;
          case 'green':
            res += 'أخضر ';
            break;
          case 'brown':
            res += 'بني ';
            break;
          case 'gray':
            res += 'رمادي ';
            break;
          case 'grayAgc':
            res += 'رمادي بلجيكي ';
            break;
          default:
            res += '$color ';
            break;
        }
      }
      if (isTemp)
        res += 'مقص ';
      else if (processing == 'lowE')
        res += 'Low-E ';
    }
    return res.trim();
  }

  static bool _isAutogeneratedLine(String line) {
    final trimmed = line.trim().toLowerCase();
    if (trimmed.isEmpty) return true;

    // Remove any bullet points, numbers, dashes, or spaces from start of string
    final cleanLine = trimmed.replaceFirst(
      RegExp(r'^[\s\-\*\•\d\.\:\)\(]+'),
      '',
    );

    final prefixes = [
      'système',
      'systeme',
      'system',
      'نظام',
      'gamme',
      'series',
      'القطاع',
      'السلسلة',
      'couleur',
      'color',
      'اللون',
      'largeur',
      'width',
      'العرض',
      'hauteur',
      'height',
      'الارتفاع',
      'الطول',
      'vitrage',
      'remplacement',
      'glass',
      'الزجاج',
      'intérieur',
      'interieur',
      'extérieur',
      'exterieur',
      'interior',
      'exterior',
      'الوجه الداخلي',
      'الوجه الخارجي',
      'cache latéral',
      'cache lateral',
      'side cover',
      'غطاء جانبي',
      'couvre-joint',
      'cover joint',
      'القطعة الجانبية',
      'كوفرو جوان',
      'de base',
      'base frame',
      'الإطار السفلي',
      'volet',
      'shutter',
      'الستار',
      'ستار',
      'lame',
      'lame volet',
      'shutter blade',
      'لام الستار',
      'اللام',
      'الشرائح',
      'coulisse',
      'كوليس',
      'fermeture',
      'fermuteure',
      'closure',
      'الإغلاق',
      'نوعية الغلق',
      'mécanisme volet',
      'mecanisme volet',
      'shutter mechanism',
      'ميكانيزم الستار',
      'hauteur poignée',
      'hauteur poignee',
      'handle height',
      'ارتفاع المقبض',
      'ouvrante central',
      'ouvrante laterale',
      'montant central',
      'montant latéral',
      'montant lateral',
      'central sash',
      'lateral sash',
      'مقطع الوسط',
      'مقطع الجانب',
    ];

    for (final p in prefixes) {
      if (cleanLine.startsWith(p)) {
        if (cleanLine.length == p.length) return true;
        // A translated/trimmed line can end exactly at the prefix boundary.
        // Never ask substring for a character past the actual string length.
        if (cleanLine.length <= p.length) continue;
        final nextChar = cleanLine.substring(p.length, p.length + 1);
        if (RegExp(r'^[\s\:\-\d\.\,\/\|]').hasMatch(nextChar)) {
          return true;
        }
      }
    }

    return false;
  }

  static DevisLineItem _buildLineItem(
    Map<String, dynamic> item, {
    bool isOfficialInvoice = false,
  }) {
    final type = item['window_type']?.toString();
    final details = <String>[];
    final double rawPrice = _toDouble(item['price']);
    final double unitPrice = isOfficialInvoice ? (rawPrice / 1.19) : rawPrice;

    // Parse JSON
    final jsonRaw = item['partitions_json'];
    Map<String, dynamic> map = {};
    if (jsonRaw != null) {
      if (jsonRaw is Map<String, dynamic>) {
        map = jsonRaw;
      } else if (jsonRaw is Map) {
        map = Map<String, dynamic>.from(jsonRaw);
      } else {
        final str = jsonRaw.toString().trim();
        if (str.length >= 5) {
          try {
            map = jsonDecode(str) as Map<String, dynamic>;
          } catch (_) {}
        }
      }
    }

    final itemColor = item['color']?.toString().trim() ?? '';
    final itemRawProfColor = itemColor.isNotEmpty
        ? _colorLabel(itemColor)
        : (map['selectedDbColor']?['name']?.toString() ?? '');
    final itemProfColor = _localizedColorLabel(itemRawProfColor);
    final detailId = item['id'] as int? ?? 0;

    final seriesName = map['seriesName'];
    final profileName = map['profileName'];
    // The model JSON is the primary source, while the detail column keeps
    // older/partially migrated orders readable.
    final jsonDescription = map['description']?.toString();
    final rowDescription = item['description']?.toString();
    final manualDesc =
        jsonDescription != null && jsonDescription.trim().isNotEmpty
        ? jsonDescription
        : rowDescription;
    final gameName = item['game']?.toString();
    final bool isShutterOnly =
        map['isShutterOnly'] == true ||
        type?.toLowerCase().contains('volet') == true ||
        type?.toLowerCase().contains('shutter') == true ||
        type?.contains('ستار') == true ||
        gameName?.toLowerCase().contains('volet') == true ||
        gameName?.toLowerCase().contains('shutter') == true ||
        gameName?.contains('ستار') == true;

    // Determine precise window type/title
    String systemType = _windowTitle(type);
    if (isShutterOnly) {
      systemType = 'Volet roulant';
    } else if (map['zones'] != null && (map['zones'] as List).isNotEmpty) {
      final zonesList = map['zones'] as List;
      final isDoor = zonesList.any(
        (z) =>
            z is Map &&
            (z['lockType']?.toString() == 'clef' ||
                z['lockType']?.toString() == 'condamnation' ||
                z['lockType']?.toString() == 'LockType.clef' ||
                z['lockType']?.toString() == 'LockType.condamnation'),
      );
      final hasDoubleSash = zonesList.any(
        (z) => z is Map && z['content']?.toString() == 'doubleSash',
      );
      if (hasDoubleSash) {
        if (isDoor) {
          if (_currentLang == AppLanguage.french) {
            systemType = 'Porte double sash';
          } else if (_currentLang == AppLanguage.english) {
            systemType = 'Double sash door';
          } else {
            systemType = 'باب بضلفتين';
          }
        } else {
          if (_currentLang == AppLanguage.french) {
            systemType = 'Fenêtre double ouvrant';
          } else if (_currentLang == AppLanguage.english) {
            systemType = 'Double sash window';
          } else {
            systemType = 'نافذة بضلفتين';
          }
        }
      } else {
        final hasSlidingSash = zonesList.any(
          (z) => z is Map && z['content']?.toString() == 'slidingSash',
        );
        if (hasSlidingSash) {
          if (_currentLang == AppLanguage.french) {
            systemType = 'Fenêtre coulissante';
          } else if (_currentLang == AppLanguage.english) {
            systemType = 'Sliding window';
          } else {
            systemType = 'نافذة منزلقة';
          }
        } else {
          final hasSingleSash = zonesList.any(
            (z) => z is Map && z['content']?.toString() == 'singleSash',
          );
          if (hasSingleSash) {
            if (isDoor) {
              if (_currentLang == AppLanguage.french) {
                systemType = 'Porte simple sash';
              } else if (_currentLang == AppLanguage.english) {
                systemType = 'Single sash door';
              } else {
                systemType = 'باب بضلفة واحدة';
              }
            } else {
              if (_currentLang == AppLanguage.french) {
                systemType = 'Fenêtre simple ouvrant';
              } else if (_currentLang == AppLanguage.english) {
                systemType = 'Single sash window';
              } else {
                systemType = 'نافذة بضلفة واحدة';
              }
            }
          }
        }
      }
    }

    final displaySeries = (gameName != null && gameName.trim().isNotEmpty)
        ? gameName.trim()
        : (seriesName ?? profileName ?? '');

    final bool isCaissonTunnel =
        map['isCaissonTunnel'] == true ||
        (item['game']?.toString().contains('Caisson Tunnel') == true) ||
        (displaySeries.toLowerCase().contains('caisson tunnel'));
    // `isCaissonTunnel` is also true for a complete designed window that has
    // a tunnel box. Only a standalone calculator result may use the special
    // tunnel-only invoice row; otherwise the ordinary window line must keep
    // its opening/sliding profiles and shutter details.
    final rawZones = map['zones'];
    final isDesignedWindow =
        map['isDesignDrawing'] == true ||
        (rawZones is List && rawZones.isNotEmpty) ||
        (map['showWall'] == true &&
            map['width'] != null &&
            map['height'] != null);
    final isStandaloneCaisson = isCaissonTunnel && !isDesignedWindow;

    final bool isMoustiquaire =
        map['isMoustiquaire'] == true ||
        (item['game']?.toString().contains('Moustiquaire') == true) ||
        (item['game']?.toString().contains('موستيكير') == true) ||
        (displaySeries.toLowerCase().contains('moustiquaire')) ||
        (displaySeries.contains('موستيكير')) ||
        (displaySeries.contains('ناموسية'));
    final bool isGlassWork =
        map['isGlassWork'] == true ||
        (item['game']?.toString().contains('Verre Trempé') == true) ||
        displaySeries.toLowerCase().contains('verre trempé') ||
        displaySeries.toLowerCase().contains('verre trempe') ||
        displaySeries.contains('عمل زجاجي');

    // Build DevisLineItem Title
    String title;
    if (isStandaloneCaisson) {
      title = 'Caisson Tunnel';
    } else if (isMoustiquaire) {
      title = 'Moustiquaire (موستيكير)';
    } else if (isGlassWork) {
      title = displaySeries.isEmpty ? 'Verre Trempé' : displaySeries;
    } else if (isShutterOnly) {
      title = 'Volet roulant';
    } else {
      if (displaySeries.isNotEmpty) {
        final cleanSeries = displaySeries.trim();
        if (_isGenericWindowLabel(cleanSeries)) {
          title = _localizeWindowTitle(cleanSeries, systemType);
        } else {
          title = '$cleanSeries - $systemType';
        }
      } else {
        title = systemType;
      }
    }

    if (map['invoiceTableEdited'] == true ||
        map['invoiceTableEdited']?.toString().toLowerCase() == 'true') {
      final editedTitle = map['manualNameOverride']?.toString().trim() ?? '';
      if (editedTitle.isNotEmpty) {
        title = _localizeWindowTitle(editedTitle, systemType);
      }
    }

    final width = map['width'] != null
        ? (double.tryParse(map['width'].toString())?.toInt() ?? 0)
        : (double.tryParse(item['largeur']?.toString() ?? '0')?.toInt() ?? 0);
    final height = map['height'] != null
        ? (double.tryParse(map['height'].toString())?.toInt() ?? 0)
        : (double.tryParse(item['hauteur']?.toString() ?? '0')?.toInt() ?? 0);

    final isReplaced =
        (map['isReplaced'] == true ||
        map['isReplaced']?.toString().toLowerCase() == 'true');
    final replacementReason = map['replacementReason']?.toString() ?? '';

    final invoiceTableEdited =
        map['invoiceTableEdited'] == true ||
        map['invoiceTableEdited']?.toString().toLowerCase() == 'true';
    // The editable table is the exact source of the Devis row. Once the user
    // edits the printed text, never rebuild those lines from the window model:
    // doing so silently reverted edits whenever the PDF was regenerated or
    // the invoice was opened again. The text is intentionally kept exactly as
    // entered, including its language.
    if (invoiceTableEdited &&
        manualDesc != null &&
        manualDesc.trim().isNotEmpty) {
      var exactDetails = manualDesc
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false);
      exactDetails = _removeRedundantGlassSummaryLines(exactDetails);
      if (_isFixedOnlyWindow(_zonesFromMap(map))) {
        exactDetails = exactDetails
            .where((line) => !_isOpeningDetailForFixedOnly(line))
            .toList(growable: false);
      }
      return DevisLineItem(
        imagePath: item['drawing_image_path']?.toString(),
        imageBase64: item['drawing_image_base64']?.toString(),
        title: title,
        details: exactDetails,
        unitPrice: unitPrice,
        quantity: (item['quantity'] as num?)?.toInt() ?? 1,
        isReplaced: isReplaced,
        replacementReason: replacementReason,
        width: width,
        height: height,
        color: itemProfColor,
        detailId: detailId,
      );
    }

    // ── Caisson Tunnel: build details from caissonPayload ──────────────────
    if (isStandaloneCaisson) {
      final payload = (map['caissonPayload'] is Map)
          ? (map['caissonPayload'] as Map<String, dynamic>)
          : map;
      final kitTypeStr =
          payload['kitType']?.toString() ?? map['kitType']?.toString() ?? '';
      final kitLabel = kitTypeStr.isNotEmpty ? kitTypeStr : 'Kit 11 (+11cm)';
      final rawItems = payload['items'] as List?;

      details.clear();
      details.add('Kit: $kitLabel');

      if (rawItems != null && rawItems.isNotEmpty) {
        for (int i = 0; i < rawItems.length; i++) {
          final it = rawItems[i];
          if (it is Map) {
            final double lenMm = (it['lengthMm'] as num? ?? 0.0).toDouble();
            final int szCm = (it['sizeCm'] as num? ?? 25).toInt();
            final int qty = (it['quantity'] as num? ?? 1).toInt();
            final String lenStr = (lenMm / 10.0).toStringAsFixed(0);
            details.add(
              'Caisson N°${i + 1}: Dimension: ${lenStr} cm | Diamètre Caisson: ${szCm} cm | Qty: $qty',
            );
          }
        }
      } else {
        final grandBars =
            payload['grandTotalCaissonBars'] ??
            map['grandTotalCaissonBars'] ??
            0;
        final grandBottom =
            payload['grandTotalBottomCoverBars'] ??
            map['grandTotalBottomCoverBars'] ??
            0;
        final grandPairs =
            payload['grandTotalPairs'] ?? map['grandTotalPairs'] ?? 0;
        details.add(
          'Barres Caisson: $grandBars | Fond: $grandBottom | Paires: $grandPairs',
        );
      }

      return DevisLineItem(
        // The drawing saved with the order is the source of truth.  The
        // official tunnel asset is used only by old rendering fallbacks when
        // no drawing path exists.
        imagePath: item['drawing_image_path']?.toString().trim(),
        imageBase64: item['drawing_image_base64']?.toString(),
        title: title,
        details: details,
        unitPrice: unitPrice,
        quantity: (item['quantity'] as num?)?.toInt() ?? 1,
        isReplaced: isReplaced,
        replacementReason: replacementReason,
        width: 0,
        height: 0,
        color: itemProfColor,
        detailId: detailId,
      );
    }

    // ── Moustiquaire: build details from moustiquairePayload ────────────────
    if (isMoustiquaire) {
      final payload = (map['moustiquairePayload'] is Map)
          ? (map['moustiquairePayload'] as Map<String, dynamic>)
          : map;
      final rawItems = payload['items'] as List?;

      details.clear();
      final subTypeStr = payload['subType']?.toString() ?? 'موستيكير';
      final itemColorStr =
          (payload['frameColor']?.toString() != null &&
              payload['frameColor']!.toString().isNotEmpty)
          ? payload['frameColor']!.toString()
          : itemProfColor;

      if (rawItems != null && rawItems.isNotEmpty) {
        for (int i = 0; i < rawItems.length; i++) {
          final it = rawItems[i];
          if (it is Map) {
            final double wMm = (it['widthMm'] as num? ?? 0.0).toDouble();
            final double hMm = (it['heightMm'] as num? ?? 0.0).toDouble();
            final int qty = (it['quantity'] as num? ?? 1).toInt();
            final double area =
                (it['totalAreaSqm'] as num? ?? (wMm * hMm / 1000000.0 * qty))
                    .toDouble();
            final String wStr = (wMm / 10.0).toStringAsFixed(0);
            final String hStr = (hMm / 10.0).toStringAsFixed(0);
            final String fColor = it['frameColor']?.toString() ?? itemColorStr;
            details.add(
              'Moustiquaire N°${i + 1}: القياس: $wStr × $hStr سم | المساحة: ${area.toStringAsFixed(2)} m² | اللون: $fColor | العدد: $qty',
            );
          }
        }
      } else {
        final totalArea = (payload['grandTotalAreaSqm'] as num? ?? 0.0)
            .toDouble();
        final totalQty = (payload['totalQuantity'] as num? ?? 1).toInt();
        details.add(
          'النوع: $subTypeStr | المساحة الكلية: ${totalArea.toStringAsFixed(2)} m² | اللون: $itemColorStr | العدد: $totalQty',
        );
      }

      return DevisLineItem(
        imagePath: 'assets/Icon/media.webp',
        imageBase64: item['drawing_image_base64']?.toString(),
        title: title,
        details: details,
        unitPrice: unitPrice,
        quantity: (item['quantity'] as num?)?.toInt() ?? 1,
        isReplaced: isReplaced,
        replacementReason: replacementReason,
        width: width,
        height: height,
        color: itemColorStr,
        detailId: detailId,
      );
    }

    // ── Verre trempé: every measurement is already an independent line ──
    if (isGlassWork) {
      final payload = (map['glassWorkPayload'] is Map)
          ? Map<String, dynamic>.from(map['glassWorkPayload'] as Map)
          : map;
      final workType =
          payload['workTypeLabel']?.toString() ??
          item['window_type']?.toString() ??
          'عمل زجاجي';
      final finish =
          payload['glassFinishLabel']?.toString() ??
          item['glass']?.toString() ??
          'شفاف';
      final thickness = (payload['thicknessMm'] as num?)?.toDouble() ?? 10;
      final sticker =
          payload['stickerLabel']?.toString() ??
          item['color']?.toString() ??
          'بدون ستيكر';
      final notes = payload['notes']?.toString() ?? '';

      details.clear();
      details.add('نوع العمل: $workType');
      details.add(
        'الزجاج: $finish ${thickness.toStringAsFixed(0)} mm | $sticker',
      );
      details.add('القياس: $width × $height mm');
      if (notes.trim().isNotEmpty) details.add(notes.trim());

      return DevisLineItem(
        imagePath: item['drawing_image_path']?.toString(),
        imageBase64: item['drawing_image_base64']?.toString(),
        title: title,
        details: details,
        unitPrice: unitPrice,
        quantity: (item['quantity'] as num?)?.toInt() ?? 1,
        isReplaced: isReplaced,
        replacementReason: replacementReason,
        width: width,
        height: height,
        color: sticker,
        detailId: detailId,
      );
    }

    final hasPartitions = map.isNotEmpty && map['zones'] != null;
    if (!hasPartitions && manualDesc != null && manualDesc.trim().isNotEmpty) {
      final overrideLines = _removeRedundantGlassSummaryLines(
        manualDesc
            .trim()
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList(growable: false),
      );
      for (final line in overrideLines) {
        details.add(line);
      }
      return DevisLineItem(
        imagePath: item['drawing_image_path']?.toString(),
        imageBase64: item['drawing_image_base64']?.toString(),
        title: title,
        details: _removeRedundantGlassSummaryLines(details),
        unitPrice: unitPrice,
        quantity: (item['quantity'] as num?)?.toInt() ?? 1,
        isReplaced: isReplaced,
        replacementReason: replacementReason,
        width: width,
        height: height,
        color: itemProfColor,
        detailId: detailId,
      );
    }

    final customLines = <String>[];
    if (manualDesc != null && manualDesc.trim().isNotEmpty) {
      final lines = manualDesc.trim().split('\n');
      for (var line in lines) {
        final cleanLine = line.trim();
        if (cleanLine.isEmpty) continue;
        final lower = cleanLine.toLowerCase();
        final isDefault =
            lower.startsWith('gamme:') ||
            lower.startsWith('series:') ||
            lower.startsWith('القطاع:') ||
            lower.startsWith('السلسلة:') ||
            lower.startsWith('couleur profil:') ||
            lower.startsWith('profile color:') ||
            lower.startsWith('لون المقطع:') ||
            lower.startsWith('لون البروفيل:') ||
            lower.startsWith('couleur accessoire:') ||
            lower.startsWith('accessory color:') ||
            lower.startsWith('لون الإكسسوار:') ||
            lower.startsWith('couleur volet:') ||
            lower.startsWith('shutter color:') ||
            lower.startsWith('لون الستار:') ||
            lower.startsWith('largeur:') ||
            lower.startsWith('width:') ||
            lower.startsWith('العرض:') ||
            lower.startsWith('hauteur:') ||
            lower.startsWith('height:') ||
            lower.startsWith('الارتفاع:') ||
            lower.startsWith('hauteur poignée:') ||
            lower.startsWith('handle height:') ||
            lower.startsWith('ارتفاع المقبض:') ||
            lower.startsWith('vitrage:') ||
            lower.startsWith('remplacement:') ||
            lower.startsWith('glass:') ||
            lower.startsWith('الزجاج:') ||
            lower.startsWith('intérieur:') ||
            lower.startsWith('interieur:') ||
            lower.startsWith('extérieur:') ||
            lower.startsWith('exterieur:') ||
            lower.startsWith('interior:') ||
            lower.startsWith('exterior:') ||
            lower.startsWith('décor vitrage:') ||
            lower.startsWith('glass decor:') ||
            lower.startsWith('ديكور الزجاج:') ||
            lower.startsWith('couvre-joint:') ||
            lower.startsWith('cover joint:') ||
            lower.startsWith('القطعة الجانبية:') ||
            lower.startsWith('de base:') ||
            lower.startsWith('base frame:') ||
            lower.startsWith('الإطار السفلي:') ||
            lower.startsWith('fermeture:') ||
            lower.startsWith('closure:') ||
            lower.startsWith('نوعية الغلق:') ||
            lower.startsWith('mécanisme volet:') ||
            lower.startsWith('mecanisme volet:') ||
            lower.startsWith('shutter mechanism:') ||
            lower.startsWith('ميكانيزم الستار:') ||
            lower.startsWith('lame volet:') ||
            lower.startsWith('shutter blade:') ||
            lower.startsWith('لام الستار:') ||
            lower.startsWith('coulisse:') ||
            lower.startsWith('كوليس:') ||
            lower.startsWith('montant:') ||
            lower.startsWith('montant central:') ||
            lower.startsWith('central montant:') ||
            lower.startsWith('مونتو مركزي:') ||
            lower.startsWith('المونتو:') ||
            lower.startsWith('moustiquaire:') ||
            lower.startsWith('mosquito net:') ||
            lower.startsWith('ناموسية:') ||
            lower.startsWith('système coulissant') ||
            lower.startsWith('sliding system') ||
            lower.startsWith('نظام منزلق') ||
            lower.startsWith('fenêtre coulissante') ||
            lower.startsWith('fenetre coulissante') ||
            lower.startsWith('sliding window') ||
            lower.startsWith('نافذة منزلقة') ||
            lower.startsWith('système battant') ||
            lower.startsWith('battant system') ||
            lower.startsWith('نظام مفصلي') ||
            lower.startsWith('volet roulant') ||
            lower.startsWith('rolling shutter') ||
            lower.startsWith('ستار رولان') ||
            lower.contains('face extérieure:') ||
            lower.contains('outer face:') ||
            lower.contains('الوجه الخارجي:') ||
            lower.contains('face intérieure:') ||
            lower.contains('inner face:') ||
            lower.contains('الوجه الداخلي:');

        if (!isDefault) {
          customLines.add(cleanLine);
        }
      }
    }

    // 1. System Type (fenêtre, volet, etc.) before Gamme and Dimensions
    if (isShutterOnly) {
      if (_currentLang == AppLanguage.french) {
        details.add('Volet roulant');
      } else if (_currentLang == AppLanguage.english) {
        details.add('Rolling shutter');
      } else {
        details.add('ستار رولان (Volet roulant)');
      }
    } else {
      details.add(systemType);
    }

    // 2. Gamme / Profile Name
    final translatedSeries = Localization.translate(
      displaySeries,
      _currentLang,
    );
    if (_currentLang == AppLanguage.french) {
      details.add('Gamme: $translatedSeries');
    } else if (_currentLang == AppLanguage.english) {
      details.add('Series: $translatedSeries');
    } else {
      details.add('السلسلة: $translatedSeries');
    }

    // 3. Dimensions (Width & Height)
    if (width > 0 || height > 0) {
      if (_currentLang == AppLanguage.french) {
        details.add('Largeur: $width mm | Hauteur: $height mm');
      } else if (_currentLang == AppLanguage.english) {
        details.add('Width: $width mm | Height: $height mm');
      } else {
        details.add('العرض: $width مم | الارتفاع: $height مم');
      }
    }

    // 4. Handle Height (Hauteur Poignée) - placed right under height (window only)
    if (!isShutterOnly &&
        map['zones'] != null &&
        (map['zones'] as List).isNotEmpty) {
      final allSashZones = (map['zones'] as List)
          .where(
            (z) =>
                (z['content']?.toString() ?? '').toLowerCase().contains('sash'),
          )
          .toList();
      if (allSashZones.isNotEmpty) {
        final z = allSashZones.first;
        final bool useOcto = z['useOctoHandle'] == true;
        final String openDir = (z['openDirection']?.toString() ?? '')
            .toLowerCase();
        final bool showHandleHeight =
            !useOcto && (openDir == 'left' || openDir == 'right');

        if (showHandleHeight) {
          final ratio =
              double.tryParse(z['handlePositionRatio']?.toString() ?? '0.5') ??
              0.5;
          final boundaryMap = z['boundary'];
          double boundaryTop = 0.0;
          double boundaryHeight = height.toDouble();
          if (boundaryMap != null) {
            boundaryTop =
                double.tryParse(boundaryMap['top']?.toString() ?? '0.0') ?? 0.0;
            boundaryHeight =
                double.tryParse(
                  boundaryMap['height']?.toString() ?? height.toString(),
                ) ??
                height.toDouble();
          }
          final handleY = boundaryTop + boundaryHeight * (1.0 - ratio);
          final handleH = (height - handleY).toInt();

          if (_currentLang == AppLanguage.french) {
            details.add('Hauteur Poignée: $handleH mm');
          } else if (_currentLang == AppLanguage.english) {
            details.add('Handle Height: $handleH mm');
          } else {
            details.add('ارتفاع المقبض: $handleH مم');
          }
        }
      }
    }

    // 5. Glass / Vitrage Details (window only - not for standalone shutters)
    final allGlassSpecs = <Map<String, dynamic>>[];
    if (!isShutterOnly &&
        map['zones'] != null &&
        (map['zones'] as List).isNotEmpty) {
      for (final z in (map['zones'] as List)) {
        if (z == null || z is! Map) continue;
        if (z['glass'] != null) {
          allGlassSpecs.add(Map<String, dynamic>.from(z['glass']));
        }
        if (z['cellGlassSpec'] != null && z['cellGlassSpec'] is Map) {
          (z['cellGlassSpec'] as Map).forEach((k, v) {
            if (v != null && v is Map) {
              allGlassSpecs.add(Map<String, dynamic>.from(v));
            }
          });
        }
      }
    }

    final glassLines = <String>[];
    final uniqueSpecs = <String>{};
    for (final g in allGlassSpecs) {
      final structure =
          g['structure']?.toString().toLowerCase().trim() ?? 'single';
      final double tOutVal = _glassOuterThickness(g, structure);
      final double tInVal = _glassInnerThickness(g);
      final int tInterVal = _glassIntercallThickness(g);
      final String fOutVal =
          g['finishOuter']?.toString().toLowerCase().trim() ?? '';
      final String cOutVal =
          g['colorOuter']?.toString().toLowerCase().trim() ?? '';
      final String pOutVal =
          g['processingOuter']?.toString().toLowerCase().trim() ?? '';
      final bool tempOutVal = g['temperedOuter'] as bool? ?? false;
      final String key =
          '${structure}_${tOutVal}_${tInVal}_${tInterVal}_${fOutVal}_${cOutVal}_${pOutVal}_${tempOutVal}';

      if (uniqueSpecs.contains(key)) continue;
      uniqueSpecs.add(key);

      if (structure == 'double') {
        final tOut = tOutVal;
        final tIn = tInVal;
        final tInter = tInterVal;
        final totalT = (tOut + tIn + tInter).toStringAsFixed(0);
        final tStr =
            '${tOut.toStringAsFixed(0)}+$tInter+${tIn.toStringAsFixed(0)}';

        final outF = _formatFace(
          g['finishOuter']?.toString() ?? '',
          g['colorOuter']?.toString() ?? '',
          g['processingOuter']?.toString() ?? '',
          isTempered: g['temperedOuter'] as bool? ?? false,
        );
        final inF = _formatFace(
          g['finishInner']?.toString() ?? '',
          g['colorInner']?.toString() ?? '',
          g['processingInner']?.toString() ?? '',
          isTempered: g['temperedInner'] as bool? ?? false,
        );

        if (_currentLang == AppLanguage.french) {
          glassLines.add('Vitrage: Double ${totalT}mm ($tStr)');
          glassLines.add('  - Face Extérieure: $outF');
          glassLines.add('  - Face Intérieure: $inF');
        } else if (_currentLang == AppLanguage.english) {
          glassLines.add('Glass: Double ${totalT}mm ($tStr)');
          glassLines.add('  - Outer Face: $outF');
          glassLines.add('  - Inner Face: $inF');
        } else {
          glassLines.add('الزجاج: مزدوج ${totalT}مم ($tStr)');
          glassLines.add('  - الوجه الخارجي: $outF');
          glassLines.add('  - الوجه الداخلي: $inF');
        }
      } else if (structure == 'closed') {
        final fv = g['finishOuter']?.toString() ?? '';
        final cv = g['colorOuter']?.toString() ?? '';
        final double pThick = tOutVal;
        final pThickStr = '${pThick.toStringAsFixed(0)}mm';
        final outF = _formatFace(
          fv,
          cv,
          g['processingOuter']?.toString() ?? '',
          isTempered: g['temperedOuter'] as bool? ?? false,
        );
        if (_currentLang == AppLanguage.french) {
          glassLines.add('Vitrage: Panneau $pThickStr ($outF)');
        } else if (_currentLang == AppLanguage.english) {
          glassLines.add('Glass: Panel $pThickStr ($outF)');
        } else {
          glassLines.add('الزجاج: بانو ${pThick.toStringAsFixed(0)}مم ($outF)');
        }
      } else {
        final tOut = tOutVal;
        final tStr = '${tOut.toStringAsFixed(0)}mm';
        final outF = _formatFace(
          g['finishOuter']?.toString() ?? '',
          g['colorOuter']?.toString() ?? '',
          g['processingOuter']?.toString() ?? '',
          isTempered: g['temperedOuter'] as bool? ?? false,
        );
        if (_currentLang == AppLanguage.french) {
          glassLines.add('Vitrage: Simple $tStr ($outF)');
        } else if (_currentLang == AppLanguage.english) {
          glassLines.add('Glass: Simple $tStr ($outF)');
        } else {
          glassLines.add('الزجاج: مفرد ${tOut.toStringAsFixed(0)}مم ($outF)');
        }
      }
    }

    if (!isShutterOnly) {
      if (glassLines.isNotEmpty) {
        for (final line in glassLines) {
          if (!details.contains(line)) {
            details.add(line);
          }
        }
      } else {
        final glass = item['glass']?.toString();
        if (glass != null && glass.isNotEmpty) {
          final glassStr = _currentLang == AppLanguage.french
              ? 'Vitrage: ${_glassLabel(glass)}'
              : _currentLang == AppLanguage.english
              ? 'Glass: ${_glassLabel(glass)}'
              : 'الزجاج: ${_glassLabel(glass)}';
          if (!details.contains(glassStr)) {
            details.add(glassStr);
          }
        }
      }
    }

    // Glass Decor Rosettes and Baguettes (window only)
    int totalRosettes = 0;
    bool hasBaguetteDecor = false;
    String? decorColorName;
    if (!isShutterOnly &&
        map['zones'] != null &&
        (map['zones'] as List).isNotEmpty) {
      for (final z in (map['zones'] as List)) {
        if (z == null || z is! Map) continue;
        int zonePieces = 1;
        final content = z['content']?.toString() ?? '';
        if (content.contains('doubleSash')) {
          zonePieces = 2;
        } else if (content.contains('slidingSash')) {
          final sCount = (z['slidingSashesCount'] as num?)?.toInt() ?? 2;
          zonePieces = sCount;
        }

        if (z['cellGlassSpec'] != null && z['cellGlassSpec'] is Map) {
          (z['cellGlassSpec'] as Map).forEach((k, v) {
            if (v != null && v is Map) {
              final h = (v['decorH'] as num?)?.toInt() ?? 0;
              final vc = (v['decorV'] as num?)?.toInt() ?? 0;
              if (h > 0 || vc > 0) {
                hasBaguetteDecor = true;
                if (v['decorColor'] != null) {
                  decorColorName = v['decorColor'].toString();
                }
                if (v['hasRosettes'] == true) {
                  totalRosettes += (h * vc);
                }
              }
            }
          });
        }
        if (z['glass'] != null && z['glass'] is Map) {
          final gSpec = z['glass'];
          final h = (gSpec['decorH'] as num?)?.toInt() ?? 0;
          final vc = (gSpec['decorV'] as num?)?.toInt() ?? 0;
          if (h > 0 || vc > 0) {
            hasBaguetteDecor = true;
            if (gSpec['decorColor'] != null) {
              decorColorName = gSpec['decorColor'].toString();
            }
            if (gSpec['hasRosettes'] == true) {
              totalRosettes += (h * vc) * zonePieces;
            }
          }
        }
      }
    }

    String formatDecorColor(String? col) {
      final c = col?.toLowerCase() ?? 'white';
      if (_currentLang == AppLanguage.french) {
        if (c == 'gold' || c == 'doré' || c == 'ذهبي') return 'doré';
        if (c == 'white' || c == 'blanc' || c == 'أبيض') return 'blanc';
        return c;
      } else if (_currentLang == AppLanguage.english) {
        if (c == 'gold' || c == 'doré' || c == 'ذهبي') return 'gold';
        if (c == 'white' || c == 'blanc' || c == 'أبيض') return 'white';
        return c;
      } else {
        if (c == 'gold' || c == 'doré' || c == 'ذهبي') return 'ذهبي';
        if (c == 'white' || c == 'blanc' || c == 'أبيض') return 'أبيض';
        return c;
      }
    }

    if (totalRosettes > 0) {
      if (_currentLang == AppLanguage.french) {
        details.add(
          'Décor vitrage: ${formatDecorColor(decorColorName)} ($totalRosettes rosettes par fenêtre)',
        );
      } else if (_currentLang == AppLanguage.english) {
        details.add(
          'Glass decor: ${formatDecorColor(decorColorName)} ($totalRosettes rosettes per window)',
        );
      } else {
        details.add(
          'ديكور الزجاج: ${formatDecorColor(decorColorName)} ($totalRosettes ورادة في النافذة)',
        );
      }
    } else if (hasBaguetteDecor) {
      if (_currentLang == AppLanguage.french) {
        details.add('Décor vitrage: ${formatDecorColor(decorColorName)}');
      } else if (_currentLang == AppLanguage.english) {
        details.add('Glass decor: ${formatDecorColor(decorColorName)}');
      } else {
        details.add('ديكور الزجاج: ${formatDecorColor(decorColorName)}');
      }
    }

    // 6. Colors (Profile Color & Accessory Color & Shutter Color)
    final color = item['color']?.toString().trim() ?? '';
    final rawProfColor = color.isNotEmpty
        ? _colorLabel(color)
        : (map['selectedDbColor']?['name']?.toString() ?? '');
    final rawAccColor =
        map['selectedAccessoryColor']?['name']?.toString() ?? rawProfColor;

    final profColor = _localizedColorLabel(rawProfColor);
    final accColor = _localizedColorLabel(rawAccColor);

    if (_currentLang == AppLanguage.french) {
      details.add('Couleur Profil: $profColor');
      details.add('Couleur Accessoire: $accColor');
      if (isShutterOnly || map['hasShutter'] == true) {
        details.add('Couleur Volet: $profColor');
      }
    } else if (_currentLang == AppLanguage.english) {
      details.add('Profile Color: $profColor');
      details.add('Accessory Color: $accColor');
      if (isShutterOnly || map['hasShutter'] == true) {
        details.add('Shutter Color: $profColor');
      }
    } else {
      details.add('لون المقطع: $profColor');
      details.add('لون الإكسسوار: $accColor');
      if (isShutterOnly || map['hasShutter'] == true) {
        details.add('لون الستار: $profColor');
      }
    }

    // 7. Couvre Joint (Side Covers) - window only, not for standalone shutters
    final bool isIntegrated =
        map['isIntegratedFrame'] == true ||
        (map['frameOverride'] != null &&
            map['frameOverride']['code']?.toString() == '103');
    final bool showCover =
        !isShutterOnly && (!isIntegrated || map['hasSideCovers'] == true);
    if (showCover) {
      final removedSides =
          (map['removedShutterSides'] as List?)
              ?.map((e) => e.toString().toLowerCase())
              .toList() ??
          [];
      final hasL = !removedSides.contains('left');
      final hasR = !removedSides.contains('right');
      final hasT = !removedSides.contains('top');
      final hasB =
          !removedSides.contains('bottom') && map['hasBottomFrame'] == true;

      final activeSides = <String>[];
      if (_currentLang == AppLanguage.french) {
        if (hasL) activeSides.add('Gauche');
        if (hasR) activeSides.add('Droite');
        if (hasT) activeSides.add('Haut');
        if (hasB) activeSides.add('Bas');
        details.add('Couvre-joint: ${activeSides.join(', ')}');
      } else if (_currentLang == AppLanguage.english) {
        if (hasL) activeSides.add('Left');
        if (hasR) activeSides.add('Right');
        if (hasT) activeSides.add('Top');
        if (hasB) activeSides.add('Bottom');
        details.add('Cover joint: ${activeSides.join(', ')}');
      } else {
        if (hasL) activeSides.add('يسار');
        if (hasR) activeSides.add('يمين');
        if (hasT) activeSides.add('أعلى');
        if (hasB) activeSides.add('أسفل');
        details.add('كوفرو جوان: ${activeSides.join('، ')}');
      }
    }

    // 8. Fermeture (Closure) & Montant (Ouvrant) details - window only
    final bool isPVC =
        (seriesName?.toString().toLowerCase().contains('pvc') ?? false) ||
        (gameName?.toLowerCase().contains('pvc') ?? false) ||
        (map['slidingSeriesName']?.toString().toLowerCase().contains('pvc') ??
            false);
    bool useEntrematique = false;
    bool hasKeyLock = false;
    bool hasSliding = false;
    bool hasCentralReinforced = false;
    bool hasCentralSimple = false;
    bool hasLateralReinforced = false;

    if (!isShutterOnly &&
        map['zones'] != null &&
        (map['zones'] as List).isNotEmpty) {
      for (final z in (map['zones'] as List)) {
        if (z == null || z is! Map) continue;
        final content = z['content']?.toString() ?? '';
        final lType = z['lockType']?.toString() ?? '';

        if (lType == 'clef' || lType == 'condamnation') {
          hasKeyLock = true;
        }

        if (content.contains('slidingSash')) {
          hasSliding = true;
          if (z['useClassicHandle'] != true) {
            useEntrematique = true;
          }

          final reinforcedMap = z['slidingMontantReinforced'] as Map?;
          if (reinforcedMap != null) {
            // Check lateral
            if (reinforcedMap['lateral_0'] == true ||
                reinforcedMap['lateral_1'] == true) {
              hasLateralReinforced = true;
            }
            // Check central (central_0, central_1, etc.)
            bool centralReinforced = false;
            bool centralFound = false;
            reinforcedMap.forEach((key, val) {
              if (key.toString().startsWith('central_')) {
                centralFound = true;
                if (val == true) {
                  centralReinforced = true;
                }
              }
            });
            if (centralFound) {
              if (centralReinforced) {
                hasCentralReinforced = true;
              } else {
                hasCentralSimple = true;
              }
            }
          } else {
            hasCentralSimple = true;
          }
        }
      }
    }

    if (useEntrematique && isPVC) {
      useEntrematique = false;
    }

    if (!isShutterOnly) {
      String fermetureVal = useEntrematique
          ? 'entrematique'
          : 'poignée espagnole';

      if (_currentLang == AppLanguage.french) {
        details.add('Fermeture: $fermetureVal');
      } else if (_currentLang == AppLanguage.english) {
        details.add('Closure: $fermetureVal');
      } else {
        details.add('الإغلاق (Fermeture): $fermetureVal');
      }

      // 9. Montant lateral / central renforcé or simple
      if (hasSliding && !isPVC) {
        if (_currentLang == AppLanguage.french) {
          details.add(
            'Montant latéral: ${hasLateralReinforced ? "renforcé" : "simple"}',
          );
          if (hasCentralReinforced || hasCentralSimple) {
            details.add(
              'Montant central: ${hasCentralReinforced ? "renforcé" : "simple"}',
            );
          }
        } else if (_currentLang == AppLanguage.english) {
          details.add(
            'Lateral montant: ${hasLateralReinforced ? "reinforced" : "simple"}',
          );
          if (hasCentralReinforced || hasCentralSimple) {
            details.add(
              'Central montant: ${hasCentralReinforced ? "reinforced" : "simple"}',
            );
          }
        } else {
          details.add(
            'مقطع جانبي (Montant latéral): ${hasLateralReinforced ? "مدعم" : "عادي"}',
          );
          if (hasCentralReinforced || hasCentralSimple) {
            details.add(
              'مقطع وسطي (Montant central): ${hasCentralReinforced ? "مدعم" : "عادي"}',
            );
          }
        }
      }
    }

    // 10. Shutter (Sitar)
    if (map['hasShutter'] == true) {
      String mech = map['shutterMechanism']?.toString().toLowerCase() ?? '';
      String mechLabel = '';
      if (mech.contains('sangle') || mech.contains('حزام')) {
        mechLabel = 'manuel (sangle)';
      } else if (mech.contains('moteur') || mech.contains('محرك')) {
        mechLabel = 'électrique';
      } else if (mech.contains('manivelle') || mech.contains('منايفال')) {
        mechLabel = 'manuel (manivelle)';
      } else {
        mechLabel = mech;
      }

      if (_currentLang == AppLanguage.french) {
        details.add('Volet: $mechLabel');
      } else if (_currentLang == AppLanguage.english) {
        details.add('Shutter: $mechLabel');
      } else {
        details.add('الستار (Volet): $mechLabel');
      }

      {
        final lameFullName = resolveShutterBladeName(
          map['componentOverrides'],
          fallback: map['shutterLame'],
        );
        if (lameFullName.isNotEmpty) {
          if (_currentLang == AppLanguage.french) {
            details.add('Lame: $lameFullName');
          } else if (_currentLang == AppLanguage.english) {
            details.add('Lame: $lameFullName');
          } else {
            details.add('الشفرة: $lameFullName');
          }
        }
      }

      // Shutter Direction (drive side)
      final String driveSide = map['shutterDriveSide']?.toString() ?? 'right';
      final bool isRight = driveSide == 'right';
      if (_currentLang == AppLanguage.french) {
        details.add('Sens: ${isRight ? "Droite" : "Gauche"}');
      } else if (_currentLang == AppLanguage.english) {
        details.add('Direction: ${isRight ? "Right" : "Left"}');
      } else {
        details.add('الاتجاه: ${isRight ? "يمين" : "يسار"}');
      }

      // Shutter Box (Caisson)
      final bool isTunnel = map['isCaissonTunnel'] == true;
      final bool isIntView = map['isInternalView'] == true;
      if (_currentLang == AppLanguage.french) {
        details.add(
          'Coffre: ${isTunnel ? "Tunnel" : (isIntView ? "Intérieur" : "Extérieur")}',
        );
      } else if (_currentLang == AppLanguage.english) {
        details.add(
          'Box: ${isTunnel ? "Tunnel" : (isIntView ? "Interior" : "Exterior")}',
        );
      } else {
        details.add(
          'الصندوق (Coffre): ${isTunnel ? "نفق (Tunnel)" : (isIntView ? "داخلي" : "خارجي")}',
        );
      }

      if (map['shutterGlissiere'] != null) {
        String glis = map['shutterGlissiere'].toString();
        String rawGlis = glis
            .replaceAll('Glissière', '')
            .replaceAll('Glissiere', '')
            .replaceAll('كوليس', '')
            .replaceAll(':', '')
            .trim();
        if (rawGlis.isEmpty) rawGlis = glis;

        if (_currentLang == AppLanguage.french) {
          details.add('Coulisse: $rawGlis');
        } else if (_currentLang == AppLanguage.english) {
          details.add('Coulisse: $rawGlis');
        } else {
          details.add('كوليس (Coulisse): $rawGlis');
        }
      }
    } else if (item['volet']?.toString() == 'Yes') {
      if (_currentLang == AppLanguage.french) {
        details.add('Volet: Oui');
      } else if (_currentLang == AppLanguage.english) {
        details.add('Shutter: Yes');
      } else {
        details.add('الستار (Volet): موجود');
      }
    }

    final unifiedDetails = _buildUnifiedWindowDetails(
      item: item,
      map: map,
      existingDetails: details,
      systemType: systemType,
      displaySeries: displaySeries,
      width: width,
      height: height,
      isShutterOnly: isShutterOnly,
      itemProfColor: itemProfColor,
      seriesName: seriesName?.toString(),
      gameName: gameName,
    );
    if (unifiedDetails.isNotEmpty) {
      details
        ..clear()
        ..addAll(unifiedDetails);
      title = _compactInvoiceTitle(
        map: map,
        systemType: systemType,
        isShutterOnly: isShutterOnly,
      );
    }

    if (customLines.isNotEmpty) {
      details.addAll(customLines);
    }

    return DevisLineItem(
      imagePath: item['drawing_image_path']?.toString(),
      imageBase64: item['drawing_image_base64']?.toString(),
      title: title,
      details: _removeRedundantGlassSummaryLines(details),
      unitPrice: unitPrice,
      quantity: (item['quantity'] as num?)?.toInt() ?? 1,
      isReplaced: isReplaced,
      replacementReason: replacementReason,
      width: width,
      height: height,
      color: itemProfColor,
      detailId: detailId,
    );
  }

  static List<String> _buildUnifiedWindowDetails({
    required Map<String, dynamic> item,
    required Map<String, dynamic> map,
    required List<String> existingDetails,
    required String systemType,
    required String displaySeries,
    required int width,
    required int height,
    required bool isShutterOnly,
    required String itemProfColor,
    String? seriesName,
    String? gameName,
  }) {
    final details = <String>[];
    final zones = _zonesFromMap(map);
    final hasWindowStructure = zones.isNotEmpty || map.isNotEmpty;
    if (!isShutterOnly && !hasWindowStructure) return details;
    final isPVC =
        (seriesName?.toLowerCase().contains('pvc') ?? false) ||
        (gameName?.toLowerCase().contains('pvc') ?? false) ||
        (map['slidingSeriesName']?.toString().toLowerCase().contains('pvc') ??
            false);
    final fixedOnlyWindow = !isShutterOnly && _isFixedOnlyWindow(zones);

    final translatedSystem = Localization.translate(systemType, _currentLang);
    final translatedSeries = Localization.translate(
      displaySeries,
      _currentLang,
    );
    final gammeParts = <String>[
      if (translatedSystem.trim().isNotEmpty) translatedSystem.trim(),
      if (translatedSeries.trim().isNotEmpty &&
          translatedSeries.trim().toLowerCase() !=
              translatedSystem.trim().toLowerCase())
        translatedSeries.trim(),
    ];
    if (gammeParts.isNotEmpty) {
      final value = gammeParts.join(' - ');
      details.add(switch (_currentLang) {
        AppLanguage.french => 'Gamme: $value',
        AppLanguage.english => 'Series: $value',
        AppLanguage.arabic => 'السلسلة: $value',
      });
    }

    if (width > 0) {
      details.add(switch (_currentLang) {
        AppLanguage.french => 'Largeur: $width mm',
        AppLanguage.english => 'Width: $width mm',
        AppLanguage.arabic => 'العرض: $width مم',
      });
    }
    if (height > 0) {
      details.add(switch (_currentLang) {
        AppLanguage.french => 'Hauteur: $height mm',
        AppLanguage.english => 'Height: $height mm',
        AppLanguage.arabic => 'الارتفاع: $height مم',
      });
    }

    if (!fixedOnlyWindow) {
      final handleLine = _handleHeightDetail(zones, height);
      if (handleLine != null) details.add(handleLine);
    }

    final rawProfColor = itemProfColor.trim().isNotEmpty
        ? itemProfColor
        : (map['selectedDbColor']?['name']?.toString() ?? '');
    final rawAccColor =
        map['selectedAccessoryColor']?['name']?.toString() ?? rawProfColor;
    final profColor = _localizedColorLabel(rawProfColor);
    final accColor = _localizedColorLabel(rawAccColor);
    details.add(switch (_currentLang) {
      AppLanguage.french => 'Couleur profil: $profColor',
      AppLanguage.english => 'Profile color: $profColor',
      AppLanguage.arabic => 'لون البروفيل: $profColor',
    });
    if (!fixedOnlyWindow) {
      details.add(switch (_currentLang) {
        AppLanguage.french => 'Couleur accessoire: $accColor',
        AppLanguage.english => 'Accessory color: $accColor',
        AppLanguage.arabic => 'لون الإكسسوار: $accColor',
      });
    }
    if (isShutterOnly || map['hasShutter'] == true) {
      details.add(switch (_currentLang) {
        AppLanguage.french => 'Couleur volet: $profColor',
        AppLanguage.english => 'Shutter color: $profColor',
        AppLanguage.arabic => 'لون الستار: $profColor',
      });
    }

    if (!isShutterOnly) {
      details.addAll(
        _unifiedGlassDetails(item, map, useFillingLabel: fixedOnlyWindow),
      );
      details.addAll(
        _matchingDetails(existingDetails, const [
          'décor vitrage:',
          'decor vitrage:',
          'glass decor:',
          'ديكور الزجاج:',
        ]),
      );
      if (!fixedOnlyWindow) {
        details.addAll(_coverJointDetails(map));
        details.add(switch (_currentLang) {
          AppLanguage.french =>
            'Cadre de base: ${map['hasBottomFrame'] == false ? "absent" : "présent"}',
          AppLanguage.english =>
            'Base frame: ${map['hasBottomFrame'] == false ? "absent" : "present"}',
          AppLanguage.arabic =>
            'الإطار السفلي: ${map['hasBottomFrame'] == false ? "غير موجود" : "موجود"}',
        });
        details.add(
          _closureDetail(
            zones,
            map: map,
            seriesName: seriesName,
            gameName: gameName,
          ),
        );
        details.addAll(
          _slidingMontantDetails(
            zones,
            seriesName: seriesName,
            gameName: gameName,
            displaySeries: displaySeries,
            isPvc: isPVC,
          ),
        );
      }
    }

    if (map['hasShutter'] == true || isShutterOnly) {
      details.addAll(_shutterDetails(map));
    } else if (item['volet']?.toString() == 'Yes') {
      details.add(switch (_currentLang) {
        AppLanguage.french => 'Mécanisme volet: Oui',
        AppLanguage.english => 'Shutter mechanism: Yes',
        AppLanguage.arabic => 'ميكانيزم الستار: موجود',
      });
    }

    return _removeRedundantGlassSummaryLines(details);
  }

  static List<Map<String, dynamic>> _zonesFromMap(Map<String, dynamic> map) {
    final rawZones = map['zones'];
    if (rawZones is! List) return const [];
    return rawZones
        .whereType<Map>()
        .map((zone) => Map<String, dynamic>.from(zone))
        .toList(growable: false);
  }

  static String _compactInvoiceTitle({
    required Map<String, dynamic> map,
    required String systemType,
    required bool isShutterOnly,
  }) {
    if (isShutterOnly) {
      return switch (_currentLang) {
        AppLanguage.french => 'Volet roulant',
        AppLanguage.english => 'Rolling shutter',
        AppLanguage.arabic => 'ستار رولان',
      };
    }

    final zones = _zonesFromMap(map);
    final fixedOnlyWindow = _isFixedOnlyWindow(zones);
    final systemLower = systemType.toLowerCase();
    final isDoor =
        systemLower.contains('porte') ||
        systemLower.contains('door') ||
        systemType.contains('باب');
    final isSliding =
        systemLower.contains('coulissant') ||
        systemLower.contains('sliding') ||
        systemType.contains('منزلق');
    final isDouble = _hasDoubleGlass(map);
    if (fixedOnlyWindow) {
      return switch (_currentLang) {
        AppLanguage.french =>
          'Fixe ${isDouble ? "double vitrage" : "simple vitrage"}',
        AppLanguage.english =>
          'Fixed frame ${isDouble ? "double glazing" : "single glazing"}',
        AppLanguage.arabic =>
          'إطار ثابت ${isDouble ? "بزجاج مزدوج" : "بزجاج مفرد"}',
      };
    }
    final fixedCount = zones
        .where((zone) => zone['content']?.toString() == 'fixedGlass')
        .length;

    return switch (_currentLang) {
      AppLanguage.french =>
        '${isDoor ? "Porte" : (isSliding ? "Fenêtre coulissante" : "Fenêtre")} '
            '${isDouble ? "double vitrage" : "simple vitrage"}'
            '${_fixedSuffix(fixedCount)}',
      AppLanguage.english =>
        '${isDoor ? "Door" : (isSliding ? "Sliding window" : "Window")} '
            '${isDouble ? "double glazing" : "single glazing"}'
            '${_fixedSuffix(fixedCount)}',
      AppLanguage.arabic =>
        '${isDoor ? "باب" : (isSliding ? "نافذة منزلقة" : "نافذة")} '
            '${isDouble ? "بزجاج مزدوج" : "بزجاج مفرد"}'
            '${_fixedSuffix(fixedCount)}',
    };
  }

  static String _fixedSuffix(int count) {
    if (count <= 0) return '';
    return switch (_currentLang) {
      AppLanguage.french =>
        count == 1
            ? ' avec fixe'
            : count == 2
            ? ' avec deux fixes'
            : ' avec $count fixes',
      AppLanguage.english =>
        count == 1
            ? ' with fixed'
            : count == 2
            ? ' with two fixed'
            : ' with $count fixed',
      AppLanguage.arabic =>
        count == 1
            ? ' مع ثابت'
            : count == 2
            ? ' مع ثابتين'
            : ' مع $count ثوابت',
    };
  }

  static String _gasSuffix() {
    return switch (_currentLang) {
      AppLanguage.french => ' avec gaz',
      AppLanguage.english => ' with gas',
      AppLanguage.arabic => ' مع غاز',
    };
  }

  static bool _isFixedOnlyWindow(List<Map<String, dynamic>> zones) {
    if (zones.isEmpty) return false;
    var hasFixedFilling = false;
    for (final z in zones) {
      final content = z['content']?.toString().toLowerCase() ?? '';
      if (content.contains('sash')) return false;
      if (_hasTruthyMapValue(z['cellIsSash']) ||
          _hasTruthyMapValue(z['cellIsDoubleSash'])) {
        return false;
      }
      if (content == 'fixedglass' || z['glass'] is Map) {
        hasFixedFilling = true;
      }
    }
    return hasFixedFilling;
  }

  static bool _hasTruthyMapValue(dynamic value) {
    if (value is! Map) return false;
    return value.values.any(
      (entry) =>
          entry == true ||
          entry == 1 ||
          entry?.toString().toLowerCase() == 'true',
    );
  }

  static bool _isOpeningDetailForFixedOnly(String line) {
    final lower = line.trim().toLowerCase();
    return lower.startsWith('hauteur poignée:') ||
        lower.startsWith('hauteur poignee:') ||
        lower.startsWith('handle height:') ||
        lower.startsWith('ارتفاع المقبض:') ||
        lower.startsWith('couleur accessoire:') ||
        lower.startsWith('accessory color:') ||
        lower.startsWith('لون الإكسسوار:') ||
        lower.startsWith('couvre-joint:') ||
        lower.startsWith('cover joint:') ||
        lower.startsWith('القطعة الجانبية:') ||
        lower.startsWith('كوفرو جوان:') ||
        lower.startsWith('de base:') ||
        lower.startsWith('base frame:') ||
        lower.startsWith('الإطار السفلي:') ||
        lower.startsWith('fermeture:') ||
        lower.startsWith('closure:') ||
        lower.startsWith('الإغلاق') ||
        lower.startsWith('نوعية الغلق:') ||
        lower.startsWith('montant') ||
        lower.startsWith('central montant:') ||
        lower.startsWith('lateral montant:') ||
        lower.startsWith('مونتو') ||
        lower.startsWith('المونتو') ||
        lower.startsWith('مقطع وسطي') ||
        lower.startsWith('مقطع جانبي');
  }

  static String? _handleHeightDetail(
    List<Map<String, dynamic>> zones,
    int height,
  ) {
    if (height <= 0) return null;
    final sashZones = zones.where((z) {
      final content = z['content']?.toString().toLowerCase() ?? '';
      return content.contains('sash');
    }).toList();
    if (sashZones.isEmpty) return null;

    final z = sashZones.first;
    final useOcto = z['useOctoHandle'] == true;
    final openDir = (z['openDirection']?.toString() ?? '').toLowerCase();
    if (useOcto || (openDir != 'left' && openDir != 'right')) return null;

    final ratio =
        double.tryParse(z['handlePositionRatio']?.toString() ?? '0.5') ?? 0.5;
    final boundaryMap = z['boundary'];
    var boundaryTop = 0.0;
    var boundaryHeight = height.toDouble();
    if (boundaryMap is Map) {
      boundaryTop =
          double.tryParse(boundaryMap['top']?.toString() ?? '0.0') ?? 0.0;
      boundaryHeight =
          double.tryParse(boundaryMap['height']?.toString() ?? '$height') ??
          height.toDouble();
    }
    final handleY = boundaryTop + boundaryHeight * (1.0 - ratio);
    final handleH = (height - handleY).toInt();
    return switch (_currentLang) {
      AppLanguage.french => 'Hauteur poignée: $handleH mm',
      AppLanguage.english => 'Handle height: $handleH mm',
      AppLanguage.arabic => 'ارتفاع المقبض: $handleH مم',
    };
  }

  static double _glassOuterThickness(Map<String, dynamic> glass, String type) {
    final value = (glass['thicknessOuter'] as num?)?.toDouble();
    if (value != null && value > 0) return value;
    return type == 'double' ? 4.0 : 5.0;
  }

  static double _glassInnerThickness(Map<String, dynamic> glass) {
    final value = (glass['thicknessInner'] as num?)?.toDouble();
    return value != null && value > 0 ? value : 4.0;
  }

  static int _glassIntercallThickness(Map<String, dynamic> glass) {
    final value = (glass['intercallThickness'] as num?)?.toInt();
    return value != null && value > 0 ? value : 12;
  }

  static List<String> _unifiedGlassDetails(
    Map<String, dynamic> item,
    Map<String, dynamic> map, {
    bool useFillingLabel = false,
  }) {
    final specs = <Map<String, dynamic>>[];
    for (final z in _zonesFromMap(map)) {
      final content = z['content']?.toString() ?? '';
      if (content.endsWith('empty')) continue;
      final keys = <String>[];
      void grid(String prefix, String h, String v) {
        for (var r = 0; r <= ((z[h] as num?)?.toInt() ?? 0); r++) {
          for (var c = 0; c <= ((z[v] as num?)?.toInt() ?? 0); c++) {
            keys.add('${prefix}_cell_${r}_$c');
          }
        }
      }

      if (content.contains('slidingSash')) {
        for (
          var i = 0;
          i < ((z['slidingSashesCount'] as num?)?.toInt() ?? 2);
          i++
        ) {
          keys.add('main_cell_0_$i');
        }
      } else if (content.contains('doubleSash')) {
        grid('left', 'innerH', 'innerV');
        grid('right', 'rightInnerH', 'rightInnerV');
      } else {
        grid('main', 'innerH', 'innerV');
      }
      final cells = z['cellGlassSpec'];
      for (final key in keys) {
        final glass = (cells is Map ? cells[key] : null) ?? z['glass'];
        if (glass is Map) specs.add(Map<String, dynamic>.from(glass));
      }
    }

    final lines = <String>[];
    final seen = <String>{};
    for (final g in specs) {
      final key = _glassDetailKey(g);
      if (!seen.add(key)) continue;
      final structure =
          g['structure']?.toString().toLowerCase().trim() ?? 'simple';
      final tOut = _glassOuterThickness(g, structure);
      final tIn = _glassInnerThickness(g);
      final tInter = _glassIntercallThickness(g);
      final outF = _formatFace(
        g['finishOuter']?.toString() ?? '',
        g['colorOuter']?.toString() ?? '',
        g['processingOuter']?.toString() ?? '',
        isTempered: g['temperedOuter'] as bool? ?? false,
      );
      final inF = _formatFace(
        g['finishInner']?.toString() ?? '',
        g['colorInner']?.toString() ?? '',
        g['processingInner']?.toString() ?? '',
        isTempered: g['temperedInner'] as bool? ?? false,
      );

      if (structure == 'double') {
        final tStr =
            '${tOut.toStringAsFixed(0)}+$tInter+${tIn.toStringAsFixed(0)}';
        final gas = g['hasGas'] == true ? _gasSuffix() : '';
        lines.add(switch (_currentLang) {
          AppLanguage.french =>
            '${useFillingLabel ? "Remplissage" : "Vitrage"}: Vitrage double ($tStr)$gas',
          AppLanguage.english => 'Glass: Double glazing ($tStr)$gas',
          AppLanguage.arabic =>
            '${useFillingLabel ? "التعبئة" : "الزجاج"}: زجاج مزدوج ($tStr)$gas',
        });
        lines.add(switch (_currentLang) {
          AppLanguage.french => 'Intérieur: $inF',
          AppLanguage.english => 'Interior: $inF',
          AppLanguage.arabic => 'الوجه الداخلي: $inF',
        });
        lines.add(switch (_currentLang) {
          AppLanguage.french => 'Extérieur: $outF',
          AppLanguage.english => 'Exterior: $outF',
          AppLanguage.arabic => 'الوجه الخارجي: $outF',
        });
      } else if (structure == 'closed') {
        lines.add(
          _panelReplacementLine(
            g,
            tOut,
            outF,
            useFillingLabel: useFillingLabel,
          ),
        );
      } else {
        lines.add(switch (_currentLang) {
          AppLanguage.french =>
            '${useFillingLabel ? "Remplissage" : "Vitrage"}: Vitrage simple ${tOut.toStringAsFixed(0)} mm - $outF',
          AppLanguage.english =>
            'Glass: Simple glazing ${tOut.toStringAsFixed(0)} mm - $outF',
          AppLanguage.arabic =>
            '${useFillingLabel ? "التعبئة" : "الزجاج"}: زجاج مفرد ${tOut.toStringAsFixed(0)} مم - $outF',
        });
      }
    }

    if (lines.isEmpty) {
      final glass = item['glass']?.toString();
      if (glass != null && glass.trim().isNotEmpty) {
        lines.add(switch (_currentLang) {
          AppLanguage.french =>
            '${useFillingLabel ? "Remplissage" : "Vitrage"}: ${_glassLabel(glass)}',
          AppLanguage.english => 'Glass: ${_glassLabel(glass)}',
          AppLanguage.arabic =>
            '${useFillingLabel ? "التعبئة" : "الزجاج"}: ${_glassLabel(glass)}',
        });
      }
    }
    return lines;
  }

  static String _glassDetailKey(Map<String, dynamic> g) {
    final structure = g['structure']?.toString().toLowerCase().trim() ?? '';
    if (structure == 'closed') {
      return [
        structure,
        g['finishOuter']?.toString().toLowerCase().trim() ?? '',
        g['colorP']?.toString().toLowerCase().trim() ?? '',
        g['panneauSubtype']?.toString().toLowerCase().trim() ?? '',
        g['panneauColor']?.toString().toLowerCase().trim() ?? '',
        (g['thicknessOuter'] as num?)?.toString() ?? '',
      ].join('|');
    }
    return [
      structure,
      g['finishOuter']?.toString().toLowerCase().trim() ?? '',
      g['finishInner']?.toString().toLowerCase().trim() ?? '',
      g['colorOuter']?.toString().toLowerCase().trim() ?? '',
      g['colorInner']?.toString().toLowerCase().trim() ?? '',
      g['processingOuter']?.toString().toLowerCase().trim() ?? '',
      g['processingInner']?.toString().toLowerCase().trim() ?? '',
      g['temperedOuter'] == true,
      g['temperedInner'] == true,
      g['hasGas'] == true,
      (g['thicknessOuter'] as num?)?.toString() ?? '',
      (g['thicknessInner'] as num?)?.toString() ?? '',
      (g['intercallThickness'] as num?)?.toString() ?? '',
    ].join('|');
  }

  static String _panelReplacementLine(
    Map<String, dynamic> g,
    double thickness,
    String fallbackFace, {
    bool useFillingLabel = false,
  }) {
    final panelName = _panelLabel(g);
    final panelColor = _panelColorLabel(g, fallbackFace);
    final thicknessText = '${thickness.toStringAsFixed(0)} mm';
    return switch (_currentLang) {
      AppLanguage.french =>
        '${useFillingLabel ? "Remplissage panneau" : "Panneau vitrage"}: $panelName - $panelColor - $thicknessText',
      AppLanguage.english =>
        'Panel replacement: $panelName - $panelColor - $thicknessText',
      AppLanguage.arabic =>
        '${useFillingLabel ? "التعبئة" : "الزجاج"}: بانو $panelName - $panelColor - ${thickness.toStringAsFixed(0)} مم',
    };
  }

  static String _panelLabel(Map<String, dynamic> g) {
    final subtype = g['panneauSubtype']?.toString().trim() ?? '';
    if (subtype.isNotEmpty && subtype.toLowerCase() != 'null') {
      return subtype;
    }

    final finish = g['finishOuter']?.toString().trim() ?? '';
    final isFr = _currentLang == AppLanguage.french;
    final isEn = _currentLang == AppLanguage.english;
    switch (finish) {
      case 'resine':
        return isEn
            ? 'Resin'
            : isFr
            ? 'Résine'
            : 'ريزين';
      case 'paneauSandwitch':
        return isEn
            ? 'Sandwich panel'
            : isFr
            ? 'Panneau sandwich'
            : 'بانو ساندويتش';
      case 'paneauSandwitchDecore':
        return isEn
            ? 'Decor panel'
            : isFr
            ? 'Panneau décor'
            : 'بانو ديكور';
      case 'plexyGlass':
        return isEn
            ? 'Plexiglass'
            : isFr
            ? 'Plexiglass'
            : 'بليكسي غلاس';
      case 'bardage':
        return isEn
            ? 'Cladding'
            : isFr
            ? 'Bardage'
            : 'بارداج';
      default:
        return isEn
            ? 'Panel'
            : isFr
            ? 'Panneau'
            : 'بانو';
    }
  }

  static String _panelColorLabel(Map<String, dynamic> g, String fallbackFace) {
    final raw = g['panneauColor']?.toString().trim().isNotEmpty == true
        ? g['panneauColor'].toString().trim()
        : g['colorP']?.toString().trim() ?? '';
    if (raw.isEmpty || raw.toLowerCase() == 'null') return fallbackFace;
    return _localizedColorLabel(raw);
  }

  static bool _hasDoubleGlass(Map<String, dynamic> map) {
    for (final z in _zonesFromMap(map)) {
      final glass = z['glass'];
      if (glass is Map &&
          glass['structure']?.toString().toLowerCase() == 'double') {
        return true;
      }
      final cellGlass = z['cellGlassSpec'];
      if (cellGlass is Map) {
        for (final value in cellGlass.values) {
          if (value is Map &&
              value['structure']?.toString().toLowerCase() == 'double') {
            return true;
          }
        }
      }
    }
    return false;
  }

  static List<String> _coverJointDetails(Map<String, dynamic> map) {
    final isIntegrated =
        map['isIntegratedFrame'] == true ||
        (map['frameOverride'] is Map &&
            (map['frameOverride'] as Map)['code']?.toString() == '103');
    if (isIntegrated && map['hasSideCovers'] != true) return const [];

    final removedSides =
        (map['removedShutterSides'] as List?)
            ?.map((side) => side.toString().toLowerCase())
            .toSet() ??
        <String>{};
    final customSegments = map['sideCoverSegments'];
    final customSides =
        customSegments is List &&
            map['useCustomSideCoverLayout'] == true &&
            customSegments.isNotEmpty
        ? customSegments
              .whereType<Map>()
              .where(
                (segment) =>
                    ((segment['endOffset'] as num?) ?? 0) >
                        ((segment['startOffset'] as num?) ?? 0) &&
                    ((segment['visibleWidth'] as num?) ?? 0) > 0,
              )
              .map((segment) => segment['side']?.toString())
              .toSet()
        : null;
    final hidden = (map['hiddenSideCoverSegments'] as List? ?? const [])
        .map((side) => side.toString())
        .toSet();
    bool hasSide(String side) =>
        map['hasSideCovers'] != false &&
        !hidden.contains(side) &&
        !removedSides.contains(side) &&
        (customSides == null || customSides.contains(side));
    final hasTop = hasSide('top');
    final hasBottom = hasSide('bottom') && map['hasBottomFrame'] != false;
    final hasRight = hasSide('right');
    final hasLeft = hasSide('left');
    final activeSides = <String>[];

    if (_currentLang == AppLanguage.french) {
      if (hasTop) activeSides.add('Haut');
      if (hasBottom) activeSides.add('Bas');
      if (hasRight) activeSides.add('Droite');
      if (hasLeft) activeSides.add('Gauche');
      return [
        'Couvre-joint: ${activeSides.isEmpty ? "Aucun" : activeSides.join(", ")}',
      ];
    }
    if (_currentLang == AppLanguage.english) {
      if (hasTop) activeSides.add('Top');
      if (hasBottom) activeSides.add('Bottom');
      if (hasRight) activeSides.add('Right');
      if (hasLeft) activeSides.add('Left');
      return [
        'Cover joint: ${activeSides.isEmpty ? "None" : activeSides.join(", ")}',
      ];
    }
    if (hasTop) activeSides.add('أعلى');
    if (hasBottom) activeSides.add('أسفل');
    if (hasRight) activeSides.add('يمين');
    if (hasLeft) activeSides.add('يسار');
    return [
      'القطعة الجانبية: ${activeSides.isEmpty ? "غير موجودة" : activeSides.join("، ")}',
    ];
  }

  static String _closureDetail(
    List<Map<String, dynamic>> zones, {
    required Map<String, dynamic> map,
    String? seriesName,
    String? gameName,
  }) {
    final isPVC =
        (seriesName?.toLowerCase().contains('pvc') ?? false) ||
        (gameName?.toLowerCase().contains('pvc') ?? false);
    var value = 'poignée espagnole';
    for (final z in zones) {
      final lockType = z['lockType']?.toString();
      if (lockType == 'clef' || lockType == 'LockType.clef') {
        value = 'poignée avec clé';
        break;
      }
      if (lockType == 'condamnation' || lockType == 'LockType.condamnation') {
        value = 'condamnation';
        break;
      }
      if (lockType == 'point' || lockType == 'LockType.point') {
        value = 'point';
      } else if (lockType == 'rouleau' || lockType == 'LockType.rouleau') {
        value = 'maréchal';
      } else if (lockType == 'rouleau2000' ||
          lockType == 'LockType.rouleau2000') {
        value = 'rouleau 2000';
      }
      final content = z['content']?.toString() ?? '';
      if (content.contains('slidingSash') && z['useClassicHandle'] != true) {
        value = isPVC ? 'poignée espagnole' : 'entrematique';
      }
    }
    final kits = _closureKitLabels(map, canUseDemiOB: isPVC);
    if (kits.isNotEmpty) {
      value = '$value - ${kits.join(' - ')}';
    }
    return switch (_currentLang) {
      AppLanguage.french => 'Fermeture: $value',
      AppLanguage.english => 'Closure: $value',
      AppLanguage.arabic => 'نوعية الغلق: $value',
    };
  }

  static List<String> _closureKitLabels(
    Map<String, dynamic> map, {
    required bool canUseDemiOB,
  }) {
    final labels = <String>[];
    if (_truthy(map['useSystemOB'])) {
      labels.add('système OB');
    }
    if (canUseDemiOB && _truthy(map['useDemiOB'])) {
      labels.add('système demi-OB');
    }
    if (_truthy(map['useVerrouCentral'])) {
      labels.add('verrou central');
    }
    return labels;
  }

  static bool _truthy(dynamic value) {
    return value == true || value?.toString().toLowerCase() == 'true';
  }

  static List<String> _slidingMontantDetails(
    List<Map<String, dynamic>> zones, {
    String? seriesName,
    String? gameName,
    required String displaySeries,
    bool isPvc = false,
  }) {
    if (isPvc) return const [];
    final haystack = '${seriesName ?? ''} ${gameName ?? ''} $displaySeries'
        .toLowerCase();
    final isTpr = haystack.contains('tpr') || haystack.contains('67000');
    final isHps = haystack.contains('hps');
    if (!isTpr && !isHps) return const [];

    final slidingZones = zones
        .where((z) => z['content']?.toString().contains('slidingSash') == true)
        .toList();
    if (slidingZones.isEmpty) return const [];

    var centralCount = 0;
    var lateralCount = 0;
    var centralReinforced = 0;
    var lateralReinforced = 0;
    for (final zone in slidingZones) {
      final sashes = (zone['slidingSashesCount'] as num?)?.toInt() ?? 2;
      final count = sashes > 1 ? (sashes - 1) * 2 : 0;
      centralCount += count;
      lateralCount += 2;
      final flags = zone['slidingMontantReinforced'];
      bool reinforced(String kind, int index) {
        if (flags is! Map) return false;
        return (flags['${kind}_$index'] ??
                flags['${kind}_${index.isEven ? 'left' : 'right'}']) ==
            true;
      }

      for (var i = 0; i < count; i++) {
        if (reinforced('central', i)) centralReinforced++;
      }
      for (var i = 0; i < 2; i++) {
        if (reinforced('lateral', i)) lateralReinforced++;
      }
    }
    String describe(
      String fr,
      String en,
      String ar,
      int total,
      int reinforced,
    ) {
      final regular = total - reinforced;
      return switch (_currentLang) {
        AppLanguage.french =>
          '$fr: $reinforced renforcé(s), $regular non renforcé(s)',
        AppLanguage.english => '$en: $reinforced reinforced, $regular standard',
        AppLanguage.arabic => '$ar: $reinforced معزز، $regular عادي',
      };
    }

    final lines = <String>[
      describe(
        'Montant central',
        'Central montant',
        'القائم الوسطي',
        centralCount,
        centralReinforced,
      ),
      describe(
        'Montant latéral',
        'Lateral montant',
        'القائم الجانبي',
        lateralCount,
        lateralReinforced,
      ),
    ];
    return lines;
  }

  static List<String> _shutterDetails(Map<String, dynamic> map) {
    final lines = <String>[];
    final mech = map['shutterMechanism']?.toString().toLowerCase() ?? '';
    var mechLabel = mech;
    if (mech.contains('sangle') || mech.contains('حزام')) {
      mechLabel = 'manuel (sangle)';
    } else if (mech.contains('moteur') || mech.contains('محرك')) {
      mechLabel = 'électrique';
    } else if (mech.contains('manivelle') ||
        mech.contains('منايفال') ||
        mech.contains('مانيفال')) {
      mechLabel = 'manuel (manivelle)';
    }
    if (mechLabel.trim().isNotEmpty) {
      lines.add(switch (_currentLang) {
        AppLanguage.french => 'Mécanisme volet: $mechLabel',
        AppLanguage.english => 'Shutter mechanism: $mechLabel',
        AppLanguage.arabic => 'ميكانيزم الستار: $mechLabel',
      });
    }

    final lame = resolveShutterBladeName(
      map['componentOverrides'],
      fallback: map['shutterLame'],
    );
    if (lame.isNotEmpty) {
      lines.add(switch (_currentLang) {
        AppLanguage.french => 'Lame volet: $lame',
        AppLanguage.english => 'Shutter blade: $lame',
        AppLanguage.arabic => 'لام الستار: $lame',
      });
    }

    final glissiere = map['shutterGlissiere']?.toString().trim() ?? '';
    if (glissiere.isNotEmpty) {
      final cleaned = glissiere
          .replaceAll('Glissière', '')
          .replaceAll('Glissiere', '')
          .replaceAll('كوليس', '')
          .replaceAll(':', '')
          .trim();
      final value = cleaned.isEmpty ? glissiere : cleaned;
      lines.add(switch (_currentLang) {
        AppLanguage.french => 'Coulisse: $value',
        AppLanguage.english => 'Coulisse: $value',
        AppLanguage.arabic => 'كوليس: $value',
      });
    }
    return lines;
  }

  static List<String> _matchingDetails(
    List<String> details,
    List<String> prefixes,
  ) {
    return details
        .where((line) {
          final lower = line.trim().toLowerCase();
          return prefixes.any(lower.startsWith);
        })
        .toList(growable: false);
  }

  static List<String> _dedupeDetails(List<String> details) {
    final seen = <String>{};
    final result = <String>[];
    for (final line in details) {
      final clean = line.trim();
      if (clean.isEmpty) continue;
      if (seen.add(clean.toLowerCase())) result.add(clean);
    }
    return result;
  }

  /// Old edited order descriptions could contain both a generic glass summary
  /// (for example, "Vitrage: Clair 5 mm") and the precise glass line built
  /// from the drawing. Keep the precise line only when both are present.
  /// Also normalize the old French "Remplacement" label to "Vitrage".
  static List<String> _removeRedundantGlassSummaryLines(List<String> details) {
    final normalized = details
        .map((line) {
          final trimmed = line.trim();
          final lower = trimmed.toLowerCase();
          if (_currentLang == AppLanguage.french &&
              lower.startsWith('remplacement panneau:')) {
            return 'Panneau vitrage:${trimmed.substring('Remplacement panneau:'.length)}';
          }
          if (_currentLang == AppLanguage.french &&
              lower.startsWith('remplacement:')) {
            return 'Vitrage:${trimmed.substring('Remplacement:'.length)}';
          }
          return trimmed;
        })
        .toList(growable: false);

    bool isGlassLine(String line) {
      final lower = line.trim().toLowerCase();
      return lower.startsWith('vitrage:') ||
          lower.startsWith('remplacement:') ||
          lower.startsWith('remplissage:') ||
          lower.startsWith('glass:') ||
          lower.startsWith('الزجاج:');
    }

    String glassValue(String line) {
      final separator = line.indexOf(':');
      return separator >= 0
          ? line.substring(separator + 1).trim().toLowerCase()
          : line.trim().toLowerCase();
    }

    bool isGenericSummary(String line) {
      final value = glassValue(line);
      return value == 'simple' ||
          value == 'single' ||
          value == 'double' ||
          value == 'clair' ||
          value == 'clear' ||
          value.startsWith('vitrage clair ') ||
          value.startsWith('glass clear ') ||
          value.startsWith('clair ') ||
          value.startsWith('clear ') ||
          value.startsWith('شفاف ') ||
          value.startsWith('زجاج شفاف');
    }

    final glassLines = normalized.where(isGlassLine).toList(growable: false);
    final hasPreciseLine = glassLines.any((line) => !isGenericSummary(line));
    final filtered = normalized
        .where((line) {
          return !(hasPreciseLine &&
              isGlassLine(line) &&
              isGenericSummary(line));
        })
        .toList(growable: false);
    return _dedupeDetails(filtered);
  }

  static String _windowTitle(String? type) {
    final value = type?.toLowerCase() ?? '';
    if (value.contains('sliding') ||
        value.contains('coulissant') ||
        value.contains('منزلق') ||
        value.contains('جرار')) {
      if (_currentLang == AppLanguage.french) return 'Fenêtre coulissante';
      if (_currentLang == AppLanguage.english) return 'Sliding window';
      return 'نافذة منزلقة';
    }
    if (value.contains('rolling') ||
        value.contains('roulant') ||
        value.contains('volet') ||
        value.contains('shutter') ||
        value.contains('ستار')) {
      if (_currentLang == AppLanguage.french) return 'Volet roulant';
      if (_currentLang == AppLanguage.english) return 'Rolling shutter';
      return 'ستار رولان (Volet roulant)';
    }
    if (_currentLang == AppLanguage.french) return 'Système battant';
    if (_currentLang == AppLanguage.english) return 'Battant system';
    return 'نظام مفصلي';
  }

  static bool _isGenericWindowLabel(String value) {
    final lower = value.toLowerCase();
    return lower.contains('fenêtre') ||
        lower.contains('fenetre') ||
        lower.contains('window') ||
        value.contains('نافذة');
  }

  /// Replaces only the generic window part of a title and keeps a selected
  /// series prefix, e.g. "TPR - نافذة منزلقة" becomes
  /// "TPR - Fenêtre coulissante".
  static String _localizeWindowTitle(String value, String localizedSystemType) {
    if (!_isGenericWindowLabel(value)) return value;

    final parts = value
        .split(RegExp(r'\s*[-–—]\s*'))
        .where((part) => part.trim().isNotEmpty)
        .toList();
    if (parts.length > 1 && _isGenericWindowLabel(parts.last)) {
      return '${parts.sublist(0, parts.length - 1).join(' - ')} - '
          '$localizedSystemType';
    }
    return localizedSystemType;
  }

  static String _glassLabel(String glass) {
    switch (glass.toLowerCase()) {
      case 'double':
        if (_currentLang == AppLanguage.french) return 'Double Vitrage';
        if (_currentLang == AppLanguage.english) return 'Double Glazing';
        return 'مزدوج';
      case 'single':
        if (_currentLang == AppLanguage.french) return 'Simple Vitrage';
        if (_currentLang == AppLanguage.english) return 'Single Glazing';
        return 'مفرد';
      default:
        return glass;
    }
  }

  static String _colorLabel(String color) {
    final lower = color.toLowerCase();
    if (_currentLang == AppLanguage.french) {
      switch (lower) {
        case 'white':
        case 'blanc':
        case 'أبيض':
          return 'Blanc';
        case 'gray':
        case 'grey':
        case 'gris':
        case 'رمادي':
          return 'Gris';
        case 'brown':
        case 'faux bois':
        case 'bouni':
        case 'بني':
          return 'Faux Bois';
        case 'black':
        case 'noir':
        case 'أسود':
          return 'Noir';
        case 'beige':
        case 'بيج':
          return 'Beige';
        default:
          return color;
      }
    } else if (_currentLang == AppLanguage.english) {
      switch (lower) {
        case 'white':
        case 'blanc':
        case 'أبيض':
          return 'White';
        case 'gray':
        case 'grey':
        case 'gris':
        case 'رمادي':
          return 'Grey';
        case 'brown':
        case 'faux bois':
        case 'بني':
          return 'Wood Faux';
        case 'black':
        case 'noir':
        case 'أسود':
          return 'Black';
        case 'beige':
        case 'بيج':
          return 'Beige';
        default:
          return color;
      }
    } else {
      switch (lower) {
        case 'white':
        case 'blanc':
        case 'أبيض':
          return 'أبيض';
        case 'gray':
        case 'grey':
        case 'gris':
        case 'رمادي':
          return 'رمادي';
        case 'brown':
        case 'faux bois':
        case 'بني':
          return 'بني فاتح (Faux Bois)';
        case 'black':
        case 'noir':
        case 'أسود':
          return 'أسود';
        case 'beige':
        case 'بيج':
          return 'بيج / FBM';
        default:
          return color;
      }
    }
  }

  /// Database colour names are catalogue data and may be saved in Arabic,
  /// French or English.  Do not expose that stored label in a Devis: its
  /// colour name must always follow the language chosen for the document.
  static String _localizedColorLabel(String rawColor) {
    final raw = rawColor.trim();
    final normalized = raw.toLowerCase();
    String? colorKey;
    if (const <String>{
      'white',
      'blanc',
      'أبيض',
      'الأبيض',
      'الابيض',
    }.contains(normalized)) {
      colorKey = 'white';
    } else if (const <String>{
      'gray',
      'grey',
      'gris',
      'رمادي',
      'الرمادي',
    }.contains(normalized)) {
      colorKey = 'grey';
    } else if (const <String>{
      'black',
      'noir',
      'أسود',
      'الأسود',
      'الاسود',
    }.contains(normalized)) {
      colorKey = 'black';
    } else if (const <String>{
      'brown',
      'wood',
      'bois',
      'faux bois',
      'بني',
      'البني',
      'خشبي',
      'الخشبي',
    }.contains(normalized)) {
      colorKey = 'wood';
    }

    if (colorKey != null) {
      final labels = switch (colorKey) {
        'white' => const ['أبيض', 'Blanc', 'White'],
        'grey' => const ['رمادي', 'Gris', 'Grey'],
        'black' => const ['أسود', 'Noir', 'Black'],
        _ => const ['خشبي', 'Faux Bois', 'Wood'],
      };
      return switch (_currentLang) {
        AppLanguage.arabic => labels[0],
        AppLanguage.french => labels[1],
        AppLanguage.english => labels[2],
      };
    }

    final normalizedLabel = _colorLabel(raw);
    if (normalizedLabel != raw) return normalizedLabel;
    return Localization.translate(raw, _currentLang);
  }

  static String amountToFrenchWords(double amount) {
    final intPart = amount.round();
    if (intPart == 0) return 'zéro dinars algériens';
    return '${_numberToFrench(intPart)} dinars algériens';
  }

  static String _numberToFrench(int n) {
    if (n < 0) return 'moins ${_numberToFrench(-n)}';
    if (n == 0) return 'zéro';

    const units = [
      '',
      'un',
      'deux',
      'trois',
      'quatre',
      'cinq',
      'six',
      'sept',
      'huit',
      'neuf',
      'dix',
      'onze',
      'douze',
      'treize',
      'quatorze',
      'quinze',
      'seize',
      'dix-sept',
      'dix-huit',
      'dix-neuf',
    ];
    const tens = [
      '',
      '',
      'vingt',
      'trente',
      'quarante',
      'cinquante',
      'soixante',
      'soixante',
      'quatre-vingt',
      'quatre-vingt',
    ];

    String under100(int x) {
      if (x < 20) return units[x];
      if (x < 70) {
        final t = x ~/ 10;
        final u = x % 10;
        if (u == 0) return tens[t];
        if (u == 1 && t != 8) return '${tens[t]}-et-un';
        return '${tens[t]}-${units[u]}';
      }
      if (x < 80) return 'soixante-${units[x - 60]}';
      if (x < 100) {
        final u = x - 80;
        if (u == 0) return 'quatre-vingts';
        return 'quatre-vingt-${units[u]}';
      }
      return '';
    }

    String under1000(int x) {
      if (x < 100) return under100(x);
      final h = x ~/ 100;
      final r = x % 100;
      final hundred = h == 1 ? 'cent' : '${units[h]} cent';
      if (r == 0) return h > 1 ? '$hundred${h > 1 ? 's' : ''}' : 'cent';
      return '$hundred${h > 1 ? 's' : ''} ${_numberToFrench(r)}';
    }

    if (n < 1000) return under1000(n);
    if (n < 1000000) {
      final th = n ~/ 1000;
      final r = n % 1000;
      final thousand = th == 1 ? 'mille' : '${_numberToFrench(th)} mille';
      if (r == 0) return thousand;
      return '$thousand ${_numberToFrench(r)}';
    }

    final m = n ~/ 1000000;
    final r = n % 1000000;
    final million = m == 1 ? 'un million' : '${_numberToFrench(m)} millions';
    if (r == 0) return million;
    return '$million ${_numberToFrench(r)}';
  }
}
