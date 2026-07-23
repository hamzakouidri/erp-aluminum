// Force compile sync trigger
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../settings/localization.dart';
import '../settings/app_settings.dart';
import 'order_date_utils.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter/foundation.dart';

class DevisLineItem {
  final String? imagePath;
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
  final int clientId;
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
    this.isPartial = false,
    this.hidePrices = false,
    this.isProForma = false,
    this.documentTitleKey,
    this.clientNif = '',
    this.clientNis = '',
    this.clientRc = '',
    this.clientAi = '',
    this.chequeNumber = '',
    this.clientId = 0,
    this.priorConfirmedWindowsCount = 0,
    this.rawOrder,
    this.rawItems,
  });
}

class DevisBuilder {
  static AppLanguage _currentLang = AppLanguage.arabic;
  static String t(String key) => Localization.translate(key, _currentLang);

  static double _toDouble(dynamic value) => (value as num?)?.toDouble() ?? 0.0;

  static Future<DevisWorkshopInfo> loadWorkshopInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localWorkshopName = prefs.getString('workshop_name') ?? 'ورشتي';
      final localWorkshopPhone = prefs.getString('phone') ?? '';
      
      final rc = prefs.getString('workshop_rc') ?? '';
      final nif = prefs.getString('workshop_nif') ?? '';
      final nis = prefs.getString('workshop_nis') ?? '';
      final ai = prefs.getString('workshop_ai') ?? '';
      final rib = prefs.getString('workshop_rib') ?? '';
      final address = prefs.getString('workshop_address') ?? '';

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return DevisWorkshopInfo(
          name: localWorkshopName,
          phone: localWorkshopPhone,
          address: address,
          rc: rc,
          nif: nif,
          nis: nis,
          ai: ai,
          rib: rib,
          logoBase64: '',
        );
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!doc.exists) {
        return DevisWorkshopInfo(
          name: localWorkshopName,
          phone: localWorkshopPhone,
          address: address,
          rc: rc,
          nif: nif,
          nis: nis,
          ai: ai,
          rib: rib,
          logoBase64: '',
        );
      }

      final data = doc.data() ?? {};
      return DevisWorkshopInfo(
        name: data['workshopName']?.toString().trim().isNotEmpty == true
            ? data['workshopName'].toString()
            : localWorkshopName,
        phone:
            data['phone']?.toString() ??
            data['phoneNumber']?.toString() ??
            user.phoneNumber ??
            localWorkshopPhone,
        address: data['workshopLocation']?.toString() ?? address,
        rc: data['rc']?.toString() ?? rc,
        nif: data['nif']?.toString() ?? nif,
        nis: data['nis']?.toString() ?? nis,
        ai: data['ai']?.toString() ?? ai,
        rib: data['rib']?.toString() ?? rib,
        logoBase64: data['workshopLogoUrl']?.toString() ?? data['logoUrl']?.toString() ?? '',
      );
    } catch (_) {
      return DevisWorkshopInfo.empty;
    }
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
    final langIndex = prefs.getInt('app_language') ?? 0;
    _currentLang = overrideLang ?? AppLanguage.values[langIndex];
    final supplier = workshop ?? await loadWorkshopInfo();
    final orderDate = _formatDisplayDate(order);
    final validUntil = _formatValidUntil(order);

    final bool isOfficialInvoice = isProForma || documentTitleKey == 'FACTURE_VENTE' || documentTitleKey == 'BON_ROUTE';
    final lineItems = items.map((it) => _buildLineItem(it, isOfficialInvoice: isOfficialInvoice)).toList();
    final totalBrut = lineItems.fold<double>(
      0.0,
      (acc, item) => acc + (item.isReplaced ? 0.0 : item.unitPrice * item.quantity),
    );
    final remise = isOfficialInvoice ? (_toDouble(order['remise']) / 1.19) : _toDouble(order['remise']);
    final tvaPercent = isOfficialInvoice ? 19.0 : _toDouble(order['tva']);
    final totalBrutValue = totalBrut;
    final totalBeforeTax = totalBrutValue - remise;
    final tvaAmount = (totalBeforeTax * tvaPercent) / 100;
    final totalTTC = totalBeforeTax + tvaAmount;
    final amountPaid = _toDouble(order['advance_payment']);

    var firstName = order['firstname']?.toString() ?? '';
    var lastName = order['lastname']?.toString() ?? '';

    // 🟢 استعلام عن تفاصيل الزبون الجبائية عند بنائها
    String clientNif = '';
    String clientNis = '';
    String clientRc = '';
    String clientAi = '';

    final db = SqlDatabase();
    final clientId = order['client_id'] as int?;
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
    final orderIdVal = order['id'] as int?;
    if (orderIdVal != null) {
      try {
        priorConfirmedWindowsCount = await db.getPriorConfirmedWindowsCount(orderIdVal);
      } catch (e) {
        debugPrint('Error getting prior confirmed windows count: $e');
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
      isPartial: isPartial,
      hidePrices: hidePrices,
      isProForma: isProForma,
      documentTitleKey: documentTitleKey,
      clientNif: clientNif,
      clientNis: clientNis,
      clientRc: clientRc,
      clientAi: clientAi,
      chequeNumber: chequeNumber,
      clientId: clientId ?? 0,
      priorConfirmedWindowsCount: priorConfirmedWindowsCount,
      rawOrder: order,
      rawItems: items,
    );
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

  static String _formatFace(String finish, String color, String processing, {bool isTempered = false}) {
    String res = '';
    final bool isTemp = processing == 'trempe' || processing == 'tempered' || isTempered;
    if (_currentLang == AppLanguage.french) {
      if (finish == 'stopSol') res += 'Stop Sol ';
      else if (finish == 'sable') res += 'Sablé ';
      else if (finish == 'martle') res += 'Martelé ';
      else res += 'Clair ';

      if (color != 'transparent' &&
          color != 'white' &&
          color != 'black' &&
          color != 'none' &&
          color.isNotEmpty &&
          color != 'null') {
        switch (color) {
          case 'blue': res += 'Bleu '; break;
          case 'blueAgc': res += 'Bleu Belge '; break;
          case 'green': res += 'Vert '; break;
          case 'brown': res += 'Marron '; break;
          case 'gray': res += 'Gris '; break;
          case 'grayAgc': res += 'Gris Belge '; break;
          default: res += '$color '; break;
        }
      }
      if (isTemp) res += 'Trempé ';
      else if (processing == 'lowE') res += 'Low-E ';

    } else if (_currentLang == AppLanguage.english) {
      if (finish == 'stopSol') res += 'Stop Sol ';
      else if (finish == 'sable') res += 'Sandblasted ';
      else if (finish == 'martle') res += 'Hammered ';
      else res += 'Clear ';

      if (color != 'transparent' &&
          color != 'white' &&
          color != 'black' &&
          color != 'none' &&
          color.isNotEmpty &&
          color != 'null') {
        switch (color) {
          case 'blue': res += 'Blue '; break;
          case 'blueAgc': res += 'Belgian Blue '; break;
          case 'green': res += 'Green '; break;
          case 'brown': res += 'Brown '; break;
          case 'gray': res += 'Grey '; break;
          case 'grayAgc': res += 'Belgian Grey '; break;
          default: res += '$color '; break;
        }
      }
      if (isTemp) res += 'Tempered ';
      else if (processing == 'lowE') res += 'Low-E ';

    } else {
      if (finish == 'stopSol') res += 'عاكس (Stop Sol) ';
      else if (finish == 'sable') res += 'رملي (Sablé) ';
      else if (finish == 'martle') res += 'مطرّق (Martelé) ';
      else res += 'شفاف ';

      if (color != 'transparent' &&
          color != 'white' &&
          color != 'black' &&
          color != 'none' &&
          color.isNotEmpty &&
          color != 'null') {
        switch (color) {
          case 'blue': res += 'أزرق '; break;
          case 'blueAgc': res += 'أزرق بلجيكي '; break;
          case 'green': res += 'أخضر '; break;
          case 'brown': res += 'بني '; break;
          case 'gray': res += 'رمادي '; break;
          case 'grayAgc': res += 'رمادي بلجيكي '; break;
          default: res += '$color '; break;
        }
      }
      if (isTemp) res += 'مقص ';
      else if (processing == 'lowE') res += 'Low-E ';
    }
    return res.trim();
  }

  static bool _isAutogeneratedLine(String line) {
    final trimmed = line.trim().toLowerCase();
    if (trimmed.isEmpty) return true;

    // Remove any bullet points, numbers, dashes, or spaces from start of string
    final cleanLine = trimmed.replaceFirst(RegExp(r'^[\s\-\*\•\d\.\:\)\(]+'), '');

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
      'glass',
      'الزجاج',
      'cache latéral',
      'cache lateral',
      'side cover',
      'غطاء جانبي',
      'couvre-joint',
      'كوفرو جوان',
      'volet',
      'shutter',
      'الستار',
      'ستار',
      'lame',
      'اللام',
      'الشرائح',
      'coulisse',
      'كوليس',
      'fermeture',
      'fermuteure',
      'الإغلاق',
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
        final nextChar = cleanLine.substring(p.length, p.length + 1);
        if (RegExp(r'^[\s\:\-\d\.\,\/\|]').hasMatch(nextChar)) {
          return true;
        }
      }
    }

    return false;
  }



  static DevisLineItem _buildLineItem(Map<String, dynamic> item, {bool isOfficialInvoice = false}) {
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

    final itemColor = item['color']?.toString();
    final itemRawProfColor = map['selectedDbColor']?['name']?.toString() ?? _colorLabel(itemColor ?? '');
    final itemProfColor = Localization.translate(itemRawProfColor, _currentLang);
    final detailId = item['id'] as int? ?? 0;

    final seriesName = map['seriesName'];
    final profileName = map['profileName'];
    final manualDesc = map['description']?.toString();
    final gameName = item['game']?.toString();
    final bool isShutterOnly = map['isShutterOnly'] == true ||
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
      final isDoor = zonesList.any((z) => z is Map && (z['lockType']?.toString() == 'clef' || z['lockType']?.toString() == 'condamnation' || z['lockType']?.toString() == 'LockType.clef' || z['lockType']?.toString() == 'LockType.condamnation'));
      final hasDoubleSash = zonesList.any((z) => z is Map && z['content']?.toString() == 'doubleSash');
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
        final hasSlidingSash = zonesList.any((z) => z is Map && z['content']?.toString() == 'slidingSash');
        if (hasSlidingSash) {
          if (_currentLang == AppLanguage.french) {
            systemType = 'Fenêtre coulissante';
          } else if (_currentLang == AppLanguage.english) {
            systemType = 'Sliding window';
          } else {
            systemType = 'نافذة منزلقة';
          }
        } else {
          final hasSingleSash = zonesList.any((z) => z is Map && z['content']?.toString() == 'singleSash');
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

    final bool isCaissonTunnel = map['isCaissonTunnel'] == true ||
        (item['game']?.toString().contains('Caisson Tunnel') == true) ||
        (displaySeries.toLowerCase().contains('caisson tunnel'));

    // Build DevisLineItem Title
    final String title;
    if (isCaissonTunnel) {
      title = 'Caisson Tunnel';
    } else if (isShutterOnly) {
      title = 'Volet roulant';
    } else {
      if (displaySeries.isNotEmpty) {
        final cleanSeries = displaySeries.trim();
        final lowerSeries = cleanSeries.toLowerCase();
        final lowerSystem = systemType.toLowerCase();
        if (lowerSeries.contains(lowerSystem) || 
            lowerSeries.contains('fenêtre') || 
            lowerSeries.contains('fenetre') || 
            lowerSeries.contains('window') || 
            lowerSeries.contains('نافذة')) {
          title = cleanSeries;
        } else {
          title = "$cleanSeries - $systemType"; // Reversed!
        }
      } else {
        title = systemType;
      }
    }

    final width = map['width'] != null
        ? (double.tryParse(map['width'].toString())?.toInt() ?? 0)
        : (double.tryParse(item['largeur']?.toString() ?? '0')?.toInt() ?? 0);
    final height = map['height'] != null
        ? (double.tryParse(map['height'].toString())?.toInt() ?? 0)
        : (double.tryParse(item['hauteur']?.toString() ?? '0')?.toInt() ?? 0);

    final isReplaced = (map['isReplaced'] == true || map['isReplaced']?.toString().toLowerCase() == 'true');
    final replacementReason = map['replacementReason']?.toString() ?? '';

    // ── Caisson Tunnel: build details from caissonPayload ──────────────────
    if (isCaissonTunnel) {

      final payload = (map['caissonPayload'] is Map)
          ? (map['caissonPayload'] as Map<String, dynamic>)
          : map;
      final kitTypeStr = payload['kitType']?.toString() ?? map['kitType']?.toString() ?? '';
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
            details.add('Caisson N°${i + 1}: Dimension: ${lenStr} cm | Diamètre Caisson: ${szCm} cm | Qty: $qty');
          }
        }
      } else {
        final grandBars = payload['grandTotalCaissonBars'] ?? map['grandTotalCaissonBars'] ?? 0;
        final grandBottom = payload['grandTotalBottomCoverBars'] ?? map['grandTotalBottomCoverBars'] ?? 0;
        final grandPairs = payload['grandTotalPairs'] ?? map['grandTotalPairs'] ?? 0;
        details.add('Barres Caisson: $grandBars | Fond: $grandBottom | Paires: $grandPairs');
      }

      return DevisLineItem(
        imagePath: 'assets/Icon/caisson_tunnel.jpg',
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

    final hasPartitions = map.isNotEmpty && map['zones'] != null;
    if (!hasPartitions && manualDesc != null && manualDesc.trim().isNotEmpty) {
      final overrideLines = manualDesc.trim().split('\n');
      for (final line in overrideLines) {
        details.add(line);
      }
      return DevisLineItem(
        imagePath: item['drawing_image_path']?.toString(),
        title: title,
        details: details,
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
        final isDefault = lower.startsWith('gamme:') ||
            lower.startsWith('series:') ||
            lower.startsWith('القطاع:') ||
            lower.startsWith('السلسلة:') ||
            lower.startsWith('couleur profil:') ||
            lower.startsWith('profile color:') ||
            lower.startsWith('لون المقطع:') ||
            lower.startsWith('couleur accessoire:') ||
            lower.startsWith('accessory color:') ||
            lower.startsWith('لون الإكسسوار:') ||
            lower.startsWith('couleur volet:') ||
            lower.startsWith('shutter color:') ||
            lower.startsWith('لون الستار:') ||
            lower.startsWith('largeur:') ||
            lower.startsWith('width:') ||
            lower.startsWith('العرض:') ||
            lower.startsWith('hauteur poignée:') ||
            lower.startsWith('handle height:') ||
            lower.startsWith('ارتفاع المقبض:') ||
            lower.startsWith('vitrage:') ||
            lower.startsWith('glass:') ||
            lower.startsWith('الزجاج:') ||
            lower.startsWith('décor vitrage:') ||
            lower.startsWith('glass decor:') ||
            lower.startsWith('ديكور الزجاج:') ||
            lower.startsWith('moustiquaire:') ||
            lower.startsWith('mosquito net:') ||
            lower.startsWith('ناموسية:') ||
            lower.startsWith('système coulissant') ||
            lower.startsWith('sliding system') ||
            lower.startsWith('نظام منزلق') ||
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
    final translatedSeries = Localization.translate(displaySeries, _currentLang);
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
    if (!isShutterOnly && map['zones'] != null && (map['zones'] as List).isNotEmpty) {
      final allSashZones = (map['zones'] as List)
          .where((z) => (z['content']?.toString() ?? '').toLowerCase().contains('sash'))
          .toList();
      if (allSashZones.isNotEmpty) {
        final z = allSashZones.first;
        final bool useOcto = z['useOctoHandle'] == true;
        final String openDir = (z['openDirection']?.toString() ?? '').toLowerCase();
        final bool showHandleHeight = !useOcto && (openDir == 'left' || openDir == 'right');

        if (showHandleHeight) {
          final ratio = double.tryParse(z['handlePositionRatio']?.toString() ?? '0.5') ?? 0.5;
          final boundaryMap = z['boundary'];
          double boundaryTop = 0.0;
          double boundaryHeight = height.toDouble();
          if (boundaryMap != null) {
            boundaryTop = double.tryParse(boundaryMap['top']?.toString() ?? '0.0') ?? 0.0;
            boundaryHeight = double.tryParse(boundaryMap['height']?.toString() ?? height.toString()) ?? height.toDouble();
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
    if (!isShutterOnly && map['zones'] != null && (map['zones'] as List).isNotEmpty) {
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
      final structure = g['structure']?.toString().toLowerCase().trim() ?? 'single';
      final double tOutVal = (g['thicknessOuter'] as num?)?.toDouble() ?? 6.0;
      final double tInVal = (g['thicknessInner'] as num?)?.toDouble() ?? 4.0;
      final int tInterVal = (g['intercallThickness'] as num?)?.toInt() ?? 16;
      final String fOutVal = g['finishOuter']?.toString().toLowerCase().trim() ?? '';
      final String cOutVal = g['colorOuter']?.toString().toLowerCase().trim() ?? '';
      final String pOutVal = g['processingOuter']?.toString().toLowerCase().trim() ?? '';
      final bool tempOutVal = g['temperedOuter'] as bool? ?? false;
      final String key = '${structure}_${tOutVal}_${tInVal}_${tInterVal}_${fOutVal}_${cOutVal}_${pOutVal}_${tempOutVal}';

      if (uniqueSpecs.contains(key)) continue;
      uniqueSpecs.add(key);

      if (structure == 'double') {
        final tOut = tOutVal;
        final tIn = tInVal;
        final tInter = tInterVal;
        final totalT = (tOut + tIn + tInter).toStringAsFixed(0);
        final tStr = '${tOut.toStringAsFixed(0)}+${tInter}+${tIn.toStringAsFixed(0)}';

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
    if (!isShutterOnly && map['zones'] != null && (map['zones'] as List).isNotEmpty) {
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
        details.add('Décor vitrage: ${formatDecorColor(decorColorName)} ($totalRosettes rosettes par fenêtre)');
      } else if (_currentLang == AppLanguage.english) {
        details.add('Glass decor: ${formatDecorColor(decorColorName)} ($totalRosettes rosettes per window)');
      } else {
        details.add('ديكور الزجاج: ${formatDecorColor(decorColorName)} ($totalRosettes ورادة في النافذة)');
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
    final color = item['color']?.toString();
    final rawProfColor = map['selectedDbColor']?['name']?.toString() ?? _colorLabel(color ?? '');
    final rawAccColor = map['selectedAccessoryColor']?['name']?.toString() ?? rawProfColor;
    
    final profColor = Localization.translate(rawProfColor, _currentLang);
    final accColor = Localization.translate(rawAccColor, _currentLang);

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
    final bool isIntegrated = map['isIntegratedFrame'] == true ||
        (map['frameOverride'] != null && map['frameOverride']['code']?.toString() == '103');
    final bool showCover = !isShutterOnly && (!isIntegrated || map['hasSideCovers'] == true);
    if (showCover) {
      final removedSides = (map['removedShutterSides'] as List?)?.map((e) => e.toString().toLowerCase()).toList() ?? [];
      final hasL = !removedSides.contains('left');
      final hasR = !removedSides.contains('right');
      final hasT = !removedSides.contains('top');
      final hasB = !removedSides.contains('bottom') && map['hasBottomFrame'] == true;

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
    final bool isPVC = (seriesName?.toString().toLowerCase().contains('pvc') ?? false) || (gameName?.toLowerCase().contains('pvc') ?? false);
    bool useEntrematique = false;
    bool hasKeyLock = false;
    bool hasSliding = false;
    bool hasCentralReinforced = false;
    bool hasCentralSimple = false;
    bool hasLateralReinforced = false;

    if (!isShutterOnly && map['zones'] != null && (map['zones'] as List).isNotEmpty) {
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
            if (reinforcedMap['lateral_0'] == true || reinforcedMap['lateral_1'] == true) {
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
      String fermetureVal = useEntrematique ? 'entrematique' : 'poignée espagnole';

      if (_currentLang == AppLanguage.french) {
        details.add('Fermeture: $fermetureVal');
      } else if (_currentLang == AppLanguage.english) {
        details.add('Closure: $fermetureVal');
      } else {
        details.add('الإغلاق (Fermeture): $fermetureVal');
      }

      // 9. Montant lateral / central renforcé or simple
      if (hasSliding) {
        if (_currentLang == AppLanguage.french) {
          details.add('Montant latéral: ${hasLateralReinforced ? "renforcé" : "simple"}');
          if (hasCentralReinforced || hasCentralSimple) {
            details.add('Montant central: ${hasCentralReinforced ? "renforcé" : "simple"}');
          }
        } else if (_currentLang == AppLanguage.english) {
          details.add('Lateral montant: ${hasLateralReinforced ? "reinforced" : "simple"}');
          if (hasCentralReinforced || hasCentralSimple) {
            details.add('Central montant: ${hasCentralReinforced ? "reinforced" : "simple"}');
          }
        } else {
          details.add('مقطع جانبي (Montant latéral): ${hasLateralReinforced ? "مدعم" : "عادي"}');
          if (hasCentralReinforced || hasCentralSimple) {
            details.add('مقطع وسطي (Montant central): ${hasCentralReinforced ? "مدعم" : "عادي"}');
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

      if (map['shutterLame'] != null) {
        final String lameFullName = map['shutterLame'].toString();
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
        details.add('Coffre: ${isTunnel ? "Tunnel" : (isIntView ? "Intérieur" : "Extérieur")}');
      } else if (_currentLang == AppLanguage.english) {
        details.add('Box: ${isTunnel ? "Tunnel" : (isIntView ? "Interior" : "Exterior")}');
      } else {
        details.add('الصندوق (Coffre): ${isTunnel ? "نفق (Tunnel)" : (isIntView ? "داخلي" : "خارجي")}');
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



    if (customLines.isNotEmpty) {
      details.addAll(customLines);
    }

    return DevisLineItem(
      imagePath: item['drawing_image_path']?.toString(),
      title: title,
      details: details,
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

  static String _windowTitle(String? type) {
    final value = type?.toLowerCase() ?? '';
    if (value.contains('sliding') || value.contains('coulissant')) {
      if (_currentLang == AppLanguage.french) return 'Système coulissant';
      if (_currentLang == AppLanguage.english) return 'Sliding system';
      return 'نظام منزلق';
    }
    if (value.contains('rolling') || value.contains('roulant') || value.contains('volet') || value.contains('shutter') || value.contains('ستار')) {
      if (_currentLang == AppLanguage.french) return 'Volet roulant';
      if (_currentLang == AppLanguage.english) return 'Rolling shutter';
      return 'ستار رولان (Volet roulant)';
    }
    if (_currentLang == AppLanguage.french) return 'Système battant';
    if (_currentLang == AppLanguage.english) return 'Battant system';
    return 'نظام مفصلي';
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
