import re

path_builder = r'c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\Commande\devis_builder.dart'

with open(path_builder, 'r', encoding='utf-8') as f:
    code = f.read()

# 1. Update DevisWorkshopInfo
OLD_WORKSHOP_INFO = """class DevisWorkshopInfo {
  final String name;
  final String phone;
  final String address;

  const DevisWorkshopInfo({
    required this.name,
    required this.phone,
    required this.address,
  });

  static const empty = DevisWorkshopInfo(name: 'ورشتي', phone: '', address: '');
}"""

NEW_WORKSHOP_INFO = """class DevisWorkshopInfo {
  final String name;
  final String phone;
  final String address;
  final String rc;
  final String nif;
  final String nis;
  final String ai;
  final String rib;

  const DevisWorkshopInfo({
    required this.name,
    required this.phone,
    required this.address,
    this.rc = '',
    this.nif = '',
    this.nis = '',
    this.ai = '',
    this.rib = '',
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
  );
}"""

assert OLD_WORKSHOP_INFO in code, "DevisWorkshopInfo not found in devis_builder"
code = code.replace(OLD_WORKSHOP_INFO, NEW_WORKSHOP_INFO, 1)

# 2. Update DevisData
OLD_DEVIS_DATA = """class DevisData {
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
  final bool hidePrices; // Added!

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
    this.hidePrices = false, // Added!
  });
}"""

NEW_DEVIS_DATA = """class DevisData {
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
  });
}"""

assert OLD_DEVIS_DATA in code, "DevisData not found in devis_builder"
code = code.replace(OLD_DEVIS_DATA, NEW_DEVIS_DATA, 1)

# 3. Update loadWorkshopInfo
OLD_LOAD_WORKSHOP = """  static Future<DevisWorkshopInfo> loadWorkshopInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localWorkshopName = prefs.getString('workshop_name') ?? 'ورشتي';
      final localWorkshopPhone = prefs.getString('phone') ?? '';

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return DevisWorkshopInfo(
          name: localWorkshopName,
          phone: localWorkshopPhone,
          address: '',
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
          address: '',
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
        address: data['workshopLocation']?.toString() ?? '',
      );
    } catch (_) {
      return DevisWorkshopInfo.empty;
    }
  }"""

NEW_LOAD_WORKSHOP = """  static Future<DevisWorkshopInfo> loadWorkshopInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localWorkshopName = prefs.getString('workshop_name') ?? 'ورشتي';
      final localWorkshopPhone = prefs.getString('phone') ?? '';
      
      final rc = prefs.getString('workshop_rc') ?? '';
      final nif = prefs.getString('workshop_nif') ?? '';
      final nis = prefs.getString('workshop_nis') ?? '';
      final ai = prefs.getString('workshop_ai') ?? '';
      final rib = prefs.getString('workshop_rib') ?? '';

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return DevisWorkshopInfo(
          name: localWorkshopName,
          phone: localWorkshopPhone,
          address: '',
          rc: rc,
          nif: nif,
          nis: nis,
          ai: ai,
          rib: rib,
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
          address: '',
          rc: rc,
          nif: nif,
          nis: nis,
          ai: ai,
          rib: rib,
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
        address: data['workshopLocation']?.toString() ?? '',
        rc: data['rc']?.toString() ?? rc,
        nif: data['nif']?.toString() ?? nif,
        nis: data['nis']?.toString() ?? nis,
        ai: data['ai']?.toString() ?? ai,
        rib: data['rib']?.toString() ?? rib,
      );
    } catch (_) {
      return DevisWorkshopInfo.empty;
    }
  }"""

assert OLD_LOAD_WORKSHOP in code, "loadWorkshopInfo not found in devis_builder"
code = code.replace(OLD_LOAD_WORKSHOP, NEW_LOAD_WORKSHOP, 1)

# 4. Update DevisBuilder.build signature
OLD_BUILD_SIGNATURE = """  static Future<DevisData> build({
    required Map<String, dynamic> order,
    required List<Map<String, dynamic>> items,
    DevisWorkshopInfo? workshop,
    bool isPartial = false,
    bool hidePrices = false,
  }) async {"""

NEW_BUILD_SIGNATURE = """  static Future<DevisData> build({
    required Map<String, dynamic> order,
    required List<Map<String, dynamic>> items,
    DevisWorkshopInfo? workshop,
    bool isPartial = false,
    bool hidePrices = false,
    bool isProForma = false,
  }) async {"""

assert OLD_BUILD_SIGNATURE in code, "DevisBuilder.build signature not found"
code = code.replace(OLD_BUILD_SIGNATURE, NEW_BUILD_SIGNATURE, 1)

# 5. Update DevisBuilder.build return DevisData construction
OLD_BUILD_RETURN = """    return DevisData(
      orderId: order['id'] as int,
      orderDate: orderDate,
      validUntil: validUntil,
      workshop: supplier,
      clientName: '$firstName $lastName'.trim(),
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
      hidePrices: hidePrices, // Added!
    );"""

NEW_BUILD_RETURN = """    return DevisData(
      orderId: order['id'] as int,
      orderDate: orderDate,
      validUntil: validUntil,
      workshop: supplier,
      clientName: '$firstName $lastName'.trim(),
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
    );"""

assert OLD_BUILD_RETURN in code, "DevisBuilder.build return construction not found"
code = code.replace(OLD_BUILD_RETURN, NEW_BUILD_RETURN, 1)

with open(path_builder, 'w', encoding='utf-8') as f:
    f.write(code)
print("devis_builder.dart updated successfully.")
