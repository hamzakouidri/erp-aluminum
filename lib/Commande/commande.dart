import 'dart:io';
import 'dart:convert';
import 'package:database_data/sql_database.dart';
import 'package:flutter/material.dart';
import 'package:database_data/Commande/add_commande.dart'; // تأكد من المسار الصحيح لصفحة CommandePage
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:database_data/Commande/pdf_fiche_coupe_api.dart';
import 'package:database_data/Commande/order_date_utils.dart';
import 'package:database_data/Commande/devis_builder.dart';
import 'package:database_data/Commande/devis_preview_screen.dart';
import 'package:database_data/Commande/capture_image.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/Screen/consumption_report_screen.dart';
import 'package:database_data/Commande/order_required_goods_screen.dart';
import 'package:database_data/Commande/order_measurements_confirm_screen.dart';
import 'package:database_data/Commande/partial_proforma_screen.dart';
import 'package:database_data/Screen/order_allocation_screen.dart';

class Commande extends StatefulWidget {
  const Commande({super.key});

  @override
  State<Commande> createState() => _CommandeState();
}

class _CommandeState extends State<Commande> {
  final SqlDatabase db = SqlDatabase();
  late Future<List<Map<String, dynamic>>> _data;
  String _searchQuery = '';
  BuildContext? _loadingDialogContext;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = Provider.of<AppSettingsProvider>(context);
    if (!settings.isManager && !settings.canViewOrders()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });
    }
  }

  String formatDate(Map<String, dynamic> order) {
    return formatOrderDate(order['created_at'], fallback: order['updated_at']);
  }

  String _translateStatus(String status, AppLanguage lang) {
    return Localization.translate(status, lang);
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Confirmed':
        return const Color(0xFF2E7D32); // أخضر داكن
      case 'Pending':
        return const Color(0xFFE65100); // برتقالي
      case 'In Progress':
        return const Color(0xFF1565C0); // أزرق
      case 'Partial Manufacturing':
        return const Color(0xFF0288D1); // أزرق فاتح
      case 'Full Manufacturing':
        return const Color(0xFF00796B); // تيل داكن
      case 'Partial Distribution':
        return const Color(0xFFF57C00); // برتقالي داكن
      case 'Full Distribution':
        return const Color(0xFF388E3C); // أخضر
      case 'Installation':
        return const Color(0xFF6A1B9A); // بنفسجي
      case 'Reserve':
        return const Color(0xFFD84315); // برتقالي محروق / تحت التحفظ
      case 'Done':
        return const Color(0xFF00695C); // تيل/أخضر مائل
      case 'New':
      default:
        return const Color(0xFF546E7A); // رمادي مزرق
    }
  }

  TextSpan highlightText(String text, String query) {
    if (query.isEmpty) {
      return TextSpan(text: text);
    }

    List<String> queryWords = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (queryWords.isEmpty) return TextSpan(text: text);

    String pattern = queryWords.map((w) => RegExp.escape(w)).join('|');
    RegExp regExp = RegExp('($pattern)', caseSensitive: false);

    List<TextSpan> spans = [];
    int start = 0;
    for (var match in regExp.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(0),
          style: TextStyle(
            color: Colors.blue,
            fontWeight: FontWeight.bold,
            backgroundColor: Colors.yellow.withValues(alpha: 0.3),
          ),
        ),
      );
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }

    return TextSpan(children: spans);
  }

  @override
  void initState() {
    super.initState();
    _data = db.readCommandesWithClients();
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          Localization.translate(
            "Commande",
            lang,
          ),
        ),
        centerTitle: true,
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).appBarTheme.backgroundColor
            : Colors.blue,
      ),
      body: Column(
        children: [
          // 🔍 Filters
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(width: 1, color: Theme.of(context).dividerColor),
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.filter_alt_outlined, color: Colors.blue),
                    const SizedBox(width: 10),
                    Text(
                      Localization.translate(
                        "Filters Commandes",
                        Provider.of<AppSettingsProvider>(context).language,
                      ),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: Localization.translate(
                      "Search",
                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _data,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (snapshot.hasError) {
                    // 🟢 التصميم التفاعلي لحالة الخطأ (بدون أكواد SQL مرعبة)
                    return Center(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(25),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.warning_amber_rounded,
                                  size: 70,
                                  color: Colors.red.shade400,
                                ),
                              ),
                              const SizedBox(height: 25),
                              Text(
                                'عذراً، حدث خطأ غير متوقع!',
                                style: TextStyle(
                                  color: Colors.red.shade800,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 15),
                              Container(
                                padding: const EdgeInsets.all(15),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(
                                    color: Colors.red.shade200,
                                  ),
                                ),
                                child: Text(
                                  // 🟢 الرسالة المفهومة للمستخدم بدلاً من snapshot.error
                                  'تعذر تحميل البيانات حالياً. يرجى التأكد من استقرار النظام أو تحديث الصفحة للمحاولة مرة أخرى.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.red.shade700,
                                    fontSize: 15,
                                    height: 1.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 30),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.red.shade600,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 30,
                                    vertical: 12,
                                  ),
                                  elevation: 0,
                                  side: BorderSide(
                                    color: Colors.red.shade200,
                                    width: 1.5,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _data = db.readCommandesWithClients();
                                  });
                                },
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  size: 22,
                                ),
                                label: const Text(
                                  'تحديث الصفحة',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  // 🟢 التصميم التفاعلي لحالة عدم وجود طلبات
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(30),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.receipt_long_outlined,
                                size: 80,
                                color: Colors.blue.shade400,
                              ),
                            ),
                            const SizedBox(height: 25),
                            Text(
                              Localization.translate(
                                "No Data",
                                Provider.of<AppSettingsProvider>(
                                  context,
                                ).language,
                              ),
                              style: TextStyle(
                                color: Colors.blueGrey.shade800,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'لا توجد أي طلبيات مسجلة حالياً.\nابدأ الآن بإنشاء أول فاتورة أو ورقة تقطيع للعميل.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 15,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 35),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue.shade600,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 30,
                                  vertical: 15,
                                ),
                                elevation: 4,
                                shadowColor: Colors.blue.withValues(alpha: 0.4),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
                              onPressed: () async {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => CommandePage(db: db),
                                  ),
                                );
                                if (result == true) {
                                  setState(() {
                                    _data = db.readCommandesWithClients();
                                  });
                                }
                              },
                              icon: const Icon(
                                Icons.add_circle_outline,
                                size: 24,
                              ),
                              label: const Text(
                                'إنشاء طلبية جديدة',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final rawData = snapshot.data!;
                  final data = rawData.where((d) {
                    final query = _searchQuery.toLowerCase().trim();
                    if (query.isEmpty) return true;
                    final first = (d['firstname'] ?? '')
                        .toString()
                        .toLowerCase();
                    final last = (d['lastname'] ?? '').toString().toLowerCase();
                    final phone = (d['phone'] ?? '').toString().toLowerCase();
                    final full = '$first $last $phone';
                    return query
                        .split(' ')
                        .every((term) => full.contains(term));
                  }).toList();

                  if (data.isEmpty) {
                    return const Center(
                      child: Text(
                        'لا توجد نتائج مطابقة للبحث',
                        style: TextStyle(fontSize: 16),
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: data.length,
                    itemBuilder: (context, index) {
                      final id = data[index]['id'];
                      final clientFirst = data[index]['firstname'] ?? '';
                      final clientLast = data[index]['lastname'] ?? '';

                      final clientPhone = data[index]['phone'];
                      final bool hasPhone =
                          clientPhone != null &&
                          clientPhone.toString().trim().isNotEmpty &&
                          clientPhone.toString() != 'null';

                      final clientName = '$clientFirst $clientLast'.trim();
                      final clientDisplay = clientName.isEmpty
                          ? 'زبون غير معروف'
                          : clientName;

                      final netPayable = (data[index]['net_payable'] as num?)?.toDouble() ?? 0.0;
                      final rawTotal = (data[index]['total'] as num?)?.toDouble() ?? 0.0;
                      final total = netPayable > 0.0 ? netPayable : rawTotal;
                      final status = data[index]['status'] ?? 'New';

                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        elevation: 2,
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(15),
                          leading: CircleAvatar(
                            radius: 25,
                            backgroundColor: Colors.blue.shade100,
                            child: const Icon(
                              Icons.receipt_long,
                              color: Colors.blue,
                            ),
                          ),
                          title: RichText(
                            text: TextSpan(
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Theme.of(context).textTheme.bodyLarge?.color,
                              ),
                              children: [
                                highlightText(clientDisplay, _searchQuery),
                              ],
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 5),
                              Text(
                                formatDate(data[index]),
                                style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color),
                              ),
                              if (hasPhone)
                                RichText(
                                  text: TextSpan(
                                    style: TextStyle(
                                      color: Theme.of(context).textTheme.bodySmall?.color,
                                      fontSize: 14,
                                    ),
                                    children: [
                                      highlightText(
                                        clientPhone.toString(),
                                        _searchQuery,
                                      ),
                                    ],
                                  ),
                                ),
                              if (data[index]['project_name'] != null && data[index]['project_name'].toString().isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Flexible(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.folder, size: 12, color: Colors.blue.shade700),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                data[index]['project_name'].toString(),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                                style: TextStyle(
                                                  color: Colors.blue.shade800,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${total.toStringAsFixed(2)} دج',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(status),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _translateStatus(status, Provider.of<AppSettingsProvider>(context, listen: false).language),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          onTap: settings.canViewOrderDetails()
                              ? () {
                                  _showOrderOptions(context, data[index]);
                                }
                              : null,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),

      floatingActionButton: settings.canCreateOrders()
          ? FloatingActionButton(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => CommandePage(db: db)),
                );
                if (result == true) {
                  setState(() {
                    _data = db.readCommandesWithClients();
                  });
                }
              },
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  void _showOrderOptions(BuildContext context, Map<String, dynamic> orderData) async {
    final orderId = (orderData['id'] as num?)?.toInt() ?? 0;
    final isFullyManufactured = await db.isOrderFullyManufactured(orderId);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) {
        final settings = Provider.of<AppSettingsProvider>(context, listen: false);
        final lang = settings.language;
        final currentStatus = orderData['status']?.toString() ?? 'Pending';
        final statusRaw = (orderData['status']?.toString() ?? '').trim().toLowerCase();
        final isPending = statusRaw == 'en attente' ||
            statusRaw == 'في الانتظار' ||
            statusRaw == 'pending' ||
            statusRaw == 'draft' ||
            statusRaw == 'new' ||
            statusRaw == 'en_attente';
        final isConfirmedOrBeyond = !isPending;
        final isManufacturingOrBeyond = isConfirmedOrBeyond &&
            statusRaw != 'confirmed' &&
            statusRaw != 'مؤكدة' &&
            statusRaw != 'مؤكد';

        final isDistributedOrBeyond = isFullyManufactured ||
            statusRaw.contains('full manufacturing') ||
            statusRaw.contains('تصنيع كلي') ||
            statusRaw.contains('distribution') ||
            statusRaw.contains('توزيع') ||
            statusRaw.contains('installation') ||
            statusRaw.contains('تركيب') ||
            statusRaw.contains('reserve') ||
            statusRaw.contains('تحفظ') ||
            statusRaw.contains('done') ||
            statusRaw.contains('انتهاء') ||
            statusRaw.contains('منتهية');

        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              Container(
                width: 50,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 15),

              // Beautiful Header showing Order details & Status
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${lang == AppLanguage.french ? "Commande" : "طلب"} #${orderData['id']}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              fontFamily: 'Cairo',
                              color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${orderData['client_name']?.toString() ?? orderData['client_display']?.toString() ?? "Client"}',
                            style: TextStyle(
                              color: Theme.of(context).brightness == Brightness.dark ? Colors.grey.shade400 : Colors.grey.shade600,
                              fontSize: 13,
                              fontFamily: 'Cairo',
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _getStatusColor(currentStatus),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _translateStatus(currentStatus, lang),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              const SizedBox(height: 10),

              // 1. الوثائق والمستندات الرسمية للطلبية
              // 1. الوثائق والمستندات الرسمية للطلبية
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                title: Text(Localization.translate('doc_devis_menu', lang)),
                onTap: () async {
                  Navigator.pop(ctx);
                  _showHeavyLoadingDialog(context, lang);
                  try {
                    final rawItems = await db.readCommandeDetails(orderData['id']);
                    final List<Map<String, dynamic>> items = rawItems.map((item) => Map<String, dynamic>.from(item)).toList();

                    for (var item in items) {
                      final path = item['drawing_image_path']?.toString() ?? '';
                      if (path.isEmpty || !File(path).existsSync()) {
                        final jsonRaw = item['partitions_json'];
                        if (jsonRaw != null) {
                          try {
                            Map<String, dynamic> modelMap = {};
                            if (jsonRaw is Map<String, dynamic>) {
                              modelMap = jsonRaw;
                            } else if (jsonRaw is Map) {
                              modelMap = Map<String, dynamic>.from(jsonRaw);
                            } else {
                              final str = jsonRaw.toString().trim();
                              if (str.length >= 5) {
                                modelMap = jsonDecode(str) as Map<String, dynamic>;
                              }
                            }
                            if (modelMap.isNotEmpty) {
                              final model = WindowModel(db: db);
                              await applyWindowModelAndLoadCatalog(model, modelMap);
                              final newPath = await saveWindowImageToDisk(model);
                              if (newPath.isNotEmpty) {
                                await db.updateCommandeDetailImagePath(item['id'] as int, newPath);
                                item['drawing_image_path'] = newPath;
                              }
                            }
                          } catch (err) {
                            debugPrint('Error generating missing image: $err');
                          }
                        }
                      }
                    }

                    final workshop = await DevisBuilder.loadWorkshopInfo();
                    final devis = await DevisBuilder.build(
                      order: orderData,
                      items: items,
                      workshop: workshop,
                      documentTitleKey: 'doc_devis',
                    );
                    if (!mounted) return;
                    _dismissHeavyLoadingDialog();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DevisPreviewScreen(data: devis),
                      ),
                    );
                  } catch (e) {
                    if (mounted) {
                      _dismissHeavyLoadingDialog();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('خطأ أثناء توليد الفاتورة: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),

              // 1.3. Facture Officielle / Proforma
              if (settings.canViewOrderDocuments())
                ListTile(
                leading: const Icon(Icons.description, color: Colors.indigo),
                title: Text(Localization.translate('فاتورة رسمية / أولية', lang)),
                onTap: () async {
                  Navigator.pop(ctx);
                  _showHeavyLoadingDialog(context, lang);
                  try {
                    final rawItems = await db.readCommandeDetails(orderData['id']);
                    final List<Map<String, dynamic>> items = rawItems.map((item) => Map<String, dynamic>.from(item)).toList();
                    final workshop = await DevisBuilder.loadWorkshopInfo();
                    final devis = await DevisBuilder.build(
                      order: orderData,
                      items: items,
                      workshop: workshop,
                      isProForma: true,
                    );
                    if (!mounted) return;
                    _dismissHeavyLoadingDialog();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DevisPreviewScreen(data: devis),
                      ),
                    );
                  } catch (e) {
                    if (mounted) {
                      _dismissHeavyLoadingDialog();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('خطأ أثناء توليد الفاتورة: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),

              

              // Facture de Vente
              if (settings.canViewOrderDocuments() && isConfirmedOrBeyond)
                ListTile(
                leading: const Icon(Icons.receipt_rounded, color: Colors.teal),
                title: Text(lang == AppLanguage.french ? 'Facture de Vente' : 'فاتورة بيع / Facture de Vente'),
                onTap: () async {
                  Navigator.pop(ctx);
                  _showHeavyLoadingDialog(context, lang);
                  try {
                    final rawItems = await db.readCommandeDetails(orderData['id']);
                    final List<Map<String, dynamic>> items = rawItems.map((item) => Map<String, dynamic>.from(item)).toList();
                    final workshop = await DevisBuilder.loadWorkshopInfo();
                    final devis = await DevisBuilder.build(
                      order: orderData,
                      items: items,
                      workshop: workshop,
                      isProForma: false,
                      documentTitleKey: 'FACTURE_VENTE',
                    );
                    if (!mounted) return;
                    _dismissHeavyLoadingDialog();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DevisPreviewScreen(data: devis),
                      ),
                    );
                  } catch (e) {
                    if (mounted) {
                      _dismissHeavyLoadingDialog();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('خطأ أثناء توليد الفاتورة: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),

              // Bon de Route
              if (settings.canViewOrderDocuments() && isConfirmedOrBeyond)
                ListTile(
                leading: const Icon(Icons.directions_car_outlined, color: Colors.blueAccent),
                title: Text(lang == AppLanguage.french ? 'Bon de Route' : 'بون دو روت / Bon de Route'),
                onTap: () async {
                  Navigator.pop(ctx);
                  _showHeavyLoadingDialog(context, lang);
                  try {
                    final rawItems = await db.readCommandeDetails(orderData['id']);
                    final List<Map<String, dynamic>> items = rawItems.map((item) => Map<String, dynamic>.from(item)).toList();
                    final workshop = await DevisBuilder.loadWorkshopInfo();
                    final devis = await DevisBuilder.build(
                      order: orderData,
                      items: items,
                      workshop: workshop,
                      isProForma: false,
                      documentTitleKey: 'BON_ROUTE',
                    );
                    if (!mounted) return;
                    _dismissHeavyLoadingDialog();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DevisPreviewScreen(data: devis),
                      ),
                    );
                  } catch (e) {
                    if (mounted) {
                      _dismissHeavyLoadingDialog();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('خطأ أثناء توليد المستند: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),


              // Bon de livraison
              if (settings.canViewOrderDocuments() && isConfirmedOrBeyond)
                ListTile(
                leading: const Icon(Icons.assignment, color: Colors.blue),
                title: Text(Localization.translate('doc_bon_livraison_menu', lang)),
                onTap: () async {
                  Navigator.pop(ctx);
                  _showHeavyLoadingDialog(context, lang);
                  try {
                    final rawItems = await db.readCommandeDetails(orderData['id']);
                    final List<Map<String, dynamic>> items = rawItems.map((item) => Map<String, dynamic>.from(item)).toList();

                    for (var item in items) {
                      final path = item['drawing_image_path']?.toString() ?? '';
                      if (path.isEmpty || !File(path).existsSync()) {
                        final jsonRaw = item['partitions_json'];
                        if (jsonRaw != null) {
                          try {
                            Map<String, dynamic> modelMap = {};
                            if (jsonRaw is Map<String, dynamic>) {
                              modelMap = jsonRaw;
                            } else if (jsonRaw is Map) {
                              modelMap = Map<String, dynamic>.from(jsonRaw);
                            } else {
                              final str = jsonRaw.toString().trim();
                              if (str.length >= 5) {
                                modelMap = jsonDecode(str) as Map<String, dynamic>;
                              }
                            }
                            if (modelMap.isNotEmpty) {
                              final model = WindowModel(db: db);
                              await applyWindowModelAndLoadCatalog(model, modelMap);
                              final newPath = await saveWindowImageToDisk(model);
                              if (newPath.isNotEmpty) {
                                await db.updateCommandeDetailImagePath(item['id'] as int, newPath);
                                item['drawing_image_path'] = newPath;
                              }
                            }
                          } catch (err) {
                            debugPrint('Error generating missing image: $err');
                          }
                        }
                      }
                    }

                    final workshop = await DevisBuilder.loadWorkshopInfo();
                    final devis = await DevisBuilder.build(
                      order: orderData,
                      items: items,
                      workshop: workshop,
                      hidePrices: false,
                      documentTitleKey: 'doc_bon_livraison',
                    );
                    if (!mounted) return;
                    _dismissHeavyLoadingDialog();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DevisPreviewScreen(data: devis),
                      ),
                    );
                  } catch (e) {
                    if (mounted) {
                      _dismissHeavyLoadingDialog();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('خطأ أثناء توليد الفاتورة: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),

              // Bon de livraison sans prix
              if (settings.canViewOrderDocuments() && isConfirmedOrBeyond)
                ListTile(
                leading: const Icon(Icons.print_disabled, color: Colors.blueGrey),
                title: Text(Localization.translate('doc_bon_livraison_sans_prix_menu', lang)),
                onTap: () async {
                  Navigator.pop(ctx);
                  _showHeavyLoadingDialog(context, lang);
                  try {
                    final rawItems = await db.readCommandeDetails(orderData['id']);
                    final List<Map<String, dynamic>> items = rawItems.map((item) => Map<String, dynamic>.from(item)).toList();

                    for (var item in items) {
                      final path = item['drawing_image_path']?.toString() ?? '';
                      if (path.isEmpty || !File(path).existsSync()) {
                        final jsonRaw = item['partitions_json'];
                        if (jsonRaw != null) {
                          try {
                            Map<String, dynamic> modelMap = {};
                            if (jsonRaw is Map<String, dynamic>) {
                              modelMap = jsonRaw;
                            } else if (jsonRaw is Map) {
                              modelMap = Map<String, dynamic>.from(jsonRaw);
                            } else {
                              final str = jsonRaw.toString().trim();
                              if (str.length >= 5) {
                                modelMap = jsonDecode(str) as Map<String, dynamic>;
                              }
                            }
                            if (modelMap.isNotEmpty) {
                              final model = WindowModel(db: db);
                              await applyWindowModelAndLoadCatalog(model, modelMap);
                              final newPath = await saveWindowImageToDisk(model);
                              if (newPath.isNotEmpty) {
                                await db.updateCommandeDetailImagePath(item['id'] as int, newPath);
                                item['drawing_image_path'] = newPath;
                              }
                            }
                          } catch (err) {
                            debugPrint('Error generating missing image: $err');
                          }
                        }
                      }
                    }

                    final workshop = await DevisBuilder.loadWorkshopInfo();
                    final devis = await DevisBuilder.build(
                      order: orderData,
                      items: items,
                      workshop: workshop,
                      hidePrices: true,
                      documentTitleKey: 'doc_bon_livraison_sans_prix',
                    );
                    if (!mounted) return;
                    _dismissHeavyLoadingDialog();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DevisPreviewScreen(data: devis),
                      ),
                    );
                  } catch (e) {
                    if (mounted) {
                      _dismissHeavyLoadingDialog();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('خطأ أثناء توليد الفاتورة: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),

              // Bon de livraison partiel
              if (settings.canViewOrderDocuments() && isConfirmedOrBeyond)
                ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined, color: Colors.blue),
                title: Text(Localization.translate('doc_bon_livraison_partiel_menu', lang)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PartialProformaScreen(
                        order: orderData,
                        documentTitleKey: 'doc_bon_livraison_partiel',
                      ),
                    ),
                  );
                },
              ),

              // Bon de livraison partiel sans prix
              if (settings.canViewOrderDocuments() && isConfirmedOrBeyond)
                ListTile(
                leading: const Icon(Icons.print_disabled_outlined, color: Colors.blueGrey),
                title: Text(Localization.translate('doc_bon_livraison_partiel_sans_prix_menu', lang)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PartialProformaScreen(
                        order: orderData,
                        hidePrices: true,
                        documentTitleKey: 'doc_bon_livraison_partiel_sans_prix',
                      ),
                    ),
                  );
                },
              ),

              
                // Bon de charge
              if (settings.canViewOrderDocuments() && isManufacturingOrBeyond)
                ListTile(
                leading: const Icon(Icons.local_shipping, color: Colors.teal),
                title: Text(Localization.translate('doc_bon_charge_menu', lang)),
                onTap: () async {
                  Navigator.pop(ctx);
                  
                  final choice = await showDialog<String>(
                    context: context,
                    builder: (dialogCtx) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      title: Row(
                        children: [
                          const Icon(Icons.local_shipping, color: Colors.teal),
                          const SizedBox(width: 8),
                          Text(
                            lang == AppLanguage.french ? 'Type de Bon d\'expédition' : 'نوع فاتورة الشحن',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 16),
                          ),
                        ],
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade300)),
                            leading: const Icon(Icons.inventory_2, color: Colors.blue),
                            title: Text(
                              lang == AppLanguage.french ? 'Expédition complète (Toutes les fenêtres)' : lang == AppLanguage.english ? 'Full Shipping (All windows)' : 'فاتورة شحن كلية (جميع النوافذ)',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13),
                            ),
                            onTap: () => Navigator.pop(dialogCtx, 'FULL'),
                          ),
                          const SizedBox(height: 10),
                          ListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade300)),
                            leading: const Icon(Icons.local_shipping_outlined, color: Colors.orange),
                            title: Text(
                              lang == AppLanguage.french ? 'Expédition partielle (Par bon de livraison)' : lang == AppLanguage.english ? 'Partial Shipping (By delivery note)' : 'فاتورة شحن جزئية (حسب وصل الشحن الجزئي)',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13),
                            ),
                            onTap: () => Navigator.pop(dialogCtx, 'PARTIAL'),
                          ),
                        ],
                      ),
                    ),
                  );

                  if (choice == null) return;

                  if (choice == 'PARTIAL') {
                    final orderId = orderData['id'] as int;
                    final deliveries = await db.readCommandeDeliveries(orderId);

                    if (deliveries.isEmpty) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            lang == AppLanguage.french 
                              ? 'Aucun bon d\'expédition partiel trouvé. Redirection...' 
                              : 'لا توجد وصولات شحن جزئية مسبقة! سيتم التوجيه لتحديد العناصر المراد شحنها.',
                            style: const TextStyle(fontFamily: 'Cairo'),
                          ),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PartialProformaScreen(
                            order: orderData,
                            hidePrices: true,
                            documentTitleKey: 'doc_bon_livraison_partiel',
                            autoOpenBonDeChargeOnSave: true,
                          ),
                        ),
                      );
                      return;
                    }

                    if (!mounted) return;
                    final selectedResult = await showModalBottomSheet<dynamic>(
                      context: context,
                      isScrollControlled: true,
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                      builder: (bottomSheetCtx) {
                        return Container(
                          padding: const EdgeInsets.all(16),
                          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                lang == AppLanguage.french ? 'Sélectionner un Bon de livraison partiel' : 'اختر وصل تسليم جزئي للتحميل',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Cairo'),
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: deliveries.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final del = deliveries[index];
                                    final isLoaded = (del['is_loaded'] == 1);
                                    List items = [];
                                    try {
                                      items = jsonDecode(del['items_json']);
                                    } catch (_) {}
                                    final itemCount = items.length;
                                    return ListTile(
                                      leading: Icon(
                                        isLoaded ? Icons.check_circle : Icons.local_shipping,
                                        color: isLoaded ? Colors.green : Colors.orange,
                                      ),
                                      title: Text('وصل بتاريخ: ${del['delivery_date']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'Cairo')),
                                      subtitle: Text('عدد القطع: $itemCount نافذة', style: const TextStyle(fontSize: 11, fontFamily: 'Cairo')),
                                      trailing: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isLoaded ? Colors.green.shade100 : Colors.orange.shade100,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          isLoaded ? (lang == AppLanguage.french ? 'Chargé' : 'تم التحميل') : (lang == AppLanguage.french ? 'En attente' : 'معلق'),
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: isLoaded ? Colors.green.shade900 : Colors.orange.shade900,
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                      ),
                                      onTap: () {
                                        Navigator.pop(bottomSheetCtx, del);
                                      },
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () {
                                  Navigator.pop(bottomSheetCtx, {'action': 'NEW'});
                                },
                                icon: const Icon(Icons.add, color: Colors.white),
                                label: Text(
                                  lang == AppLanguage.french ? '+ Nouveau bon de livraison partiel' : '+ إنشاء توصيل جزئي جديد',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );

                    if (selectedResult == null) return;

                    if (selectedResult is Map && selectedResult['action'] == 'NEW') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PartialProformaScreen(
                            order: orderData,
                            hidePrices: true,
                            documentTitleKey: 'doc_bon_livraison_partiel',
                            autoOpenBonDeChargeOnSave: true,
                          ),
                        ),
                      );
                      return;
                    }

                    if (selectedResult is Map<String, dynamic>) {
                      _showHeavyLoadingDialog(context, lang);
                      try {
                        final itemsJsonStr = selectedResult['items_json']?.toString() ?? '[]';
                        final List<dynamic> rawDecoded = jsonDecode(itemsJsonStr);
                        final List<Map<String, dynamic>> items = rawDecoded.map((it) => Map<String, dynamic>.from(it)).toList();

                        for (var item in items) {
                          final path = item['drawing_image_path']?.toString() ?? '';
                          if (path.isEmpty || !File(path).existsSync()) {
                            final jsonRaw = item['partitions_json'];
                            if (jsonRaw != null) {
                              try {
                                Map<String, dynamic> modelMap = {};
                                if (jsonRaw is Map<String, dynamic>) {
                                  modelMap = jsonRaw;
                                } else if (jsonRaw is Map) {
                                  modelMap = Map<String, dynamic>.from(jsonRaw);
                                } else {
                                  final str = jsonRaw.toString().trim();
                                  if (str.length >= 5) {
                                    modelMap = jsonDecode(str) as Map<String, dynamic>;
                                  }
                                }
                                if (modelMap.isNotEmpty) {
                                  final model = WindowModel(db: db);
                                  await applyWindowModelAndLoadCatalog(model, modelMap);
                                  final newPath = await saveWindowImageToDisk(model);
                                  if (newPath.isNotEmpty) {
                                    await db.updateCommandeDetailImagePath(item['id'] as int, newPath);
                                    item['drawing_image_path'] = newPath;
                                  }
                                }
                              } catch (err) {
                                debugPrint('Error generating missing image: $err');
                              }
                            }
                          }
                        }

                        final workshop = await DevisBuilder.loadWorkshopInfo();
                        final devis = await DevisBuilder.build(
                          order: orderData,
                          items: items,
                          workshop: workshop,
                          hidePrices: true,
                          documentTitleKey: 'BON_CHARGE',
                        );
                        if (!mounted) return;
                        _dismissHeavyLoadingDialog();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => DevisPreviewScreen(
                              data: devis,
                              deliveryId: selectedResult['id'] as int?,
                              initialIsLoaded: (selectedResult['is_loaded'] == 1),
                            ),
                          ),
                        );
                      } catch (e) {
                        if (mounted) {
                          _dismissHeavyLoadingDialog();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('خطأ أثناء توليد الفاتورة: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                      return;
                    }
                  }

                  // Full loading flow (FULL)
                  _showHeavyLoadingDialog(context, lang);
                  try {
                    final rawItems = await db.readCommandeDetails(orderData['id']);
                    final List<Map<String, dynamic>> items = rawItems.map((item) => Map<String, dynamic>.from(item)).toList();

                    for (var item in items) {
                      final path = item['drawing_image_path']?.toString() ?? '';
                      if (path.isEmpty || !File(path).existsSync()) {
                        final jsonRaw = item['partitions_json'];
                        if (jsonRaw != null) {
                          try {
                            Map<String, dynamic> modelMap = {};
                            if (jsonRaw is Map<String, dynamic>) {
                              modelMap = jsonRaw;
                            } else if (jsonRaw is Map) {
                              modelMap = Map<String, dynamic>.from(jsonRaw);
                            } else {
                              final str = jsonRaw.toString().trim();
                              if (str.length >= 5) {
                                modelMap = jsonDecode(str) as Map<String, dynamic>;
                              }
                            }
                            if (modelMap.isNotEmpty) {
                              final model = WindowModel(db: db);
                              await applyWindowModelAndLoadCatalog(model, modelMap);
                              final newPath = await saveWindowImageToDisk(model);
                              if (newPath.isNotEmpty) {
                                await db.updateCommandeDetailImagePath(item['id'] as int, newPath);
                                item['drawing_image_path'] = newPath;
                              }
                            }
                          } catch (err) {
                            debugPrint('Error generating missing image: $err');
                          }
                        }
                      }
                    }

                    final workshop = await DevisBuilder.loadWorkshopInfo();
                    final devis = await DevisBuilder.build(
                      order: orderData,
                      items: items,
                      workshop: workshop,
                      hidePrices: true,
                      documentTitleKey: 'BON_CHARGE',
                    );
                    if (!mounted) return;
                    _dismissHeavyLoadingDialog();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DevisPreviewScreen(data: devis),
                      ),
                    );
                  } catch (e) {
                    if (mounted) {
                      _dismissHeavyLoadingDialog();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('خطأ أثناء توليد الفاتورة: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),
          if (isConfirmedOrBeyond)
            const Divider(),

              // 2. Fiche de Coupe
              if (settings.canViewFicheDeCoupe())
                ListTile(
                  leading: const Icon(Icons.cut, color: Colors.orange),
                  title: Text(Localization.translate('ورقة التقطيع (Fiche de Coupe)', lang)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    if (mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(Localization.translate('جاري تجهيز جدول التقطيع...', lang)),
                        ),
                      );
                    try {
                      final items = await db.readCommandeDetails(orderData['id']);
                      final prefs = await SharedPreferences.getInstance();
                      final workshopName =
                          prefs.getString('workshop_name') ?? 'ورشتي';
                      await PdfFicheCoupeApi.generateAndPrintFicheCoupe(
                        order: orderData,
                        items: items,
                        workshopName: workshopName,
                      );
                    } catch (e) {
                      if (mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${Localization.translate('خطأ أثناء توليد الفاتورة:', lang)} $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                    }
                  },
                ),

              // 3. Fiche de Consommation & المواد والسلع المطلوبة
              if (settings.canViewOrderMaterials()) ...[
                ListTile(
                  leading: const Icon(Icons.inventory_2, color: Colors.indigo),
                  title: Text(Localization.translate('سلع الطلبية وموادها (تقرير النواقص)', lang)),
                  onTap: () {},
                ),

                ListTile(
                  leading: const Icon(Icons.shopping_basket, color: Colors.deepPurple),
                  title: Text(Localization.translate('السلع المطلوبة', lang)),
                  subtitle: Text(
                    Localization.translate('مجموع سلع جميع المنتجات مجمّعة', lang),
                    style: const TextStyle(fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OrderRequiredGoodsScreen(
                          orderData: orderData,
                          db: db,
                        ),
                      ),
                    );
                  },
                ),
              ],

              
                // 3.8 تأكيد القياسات والملصقات
                if (settings.canConfirmMeasurements())
                  ListTile(
                    leading: const Icon(Icons.line_weight_rounded, color: Colors.indigoAccent),
                    title: Text(Localization.translate('تأكيد القياسات والملصقات (Stickers)', lang)),
                    subtitle: Text(
                      Localization.translate('تعديل القياسات الفعلية للموقع وطباعة الباركود لكل قطعة', lang),
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OrderMeasurementsConfirmScreen(
                            orderData: orderData,
                            db: db,
                          ),
                        ),
                      );
                    },
                  ),

                // 3.9 توزيع المهام وإسناد العمل للعمال (تختفي عند التصنيع الكلي، التوزيع، التركيب، التحفظات أو الانتهاء)
                if (settings.canAllocateTasks() && !isDistributedOrBeyond)
                  ListTile(
                    leading: const Icon(Icons.engineering_rounded, color: Colors.purple),
                    title: Text(
                      lang == AppLanguage.french 
                        ? 'Affectation des tâches aux ouvriers' 
                        : 'توزيع المهام على العمال (إسناد الورشة)',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      lang == AppLanguage.french
                        ? 'Répartir la fabrication des éléments sur l\'équipe'
                        : 'توزيع النوافذ وتحديد أجر تصنيع كل عنصر للعمال',
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OrderAllocationScreen(
                            orderData: orderData,
                            db: db,
                          ),
                        ),
                      );
                    },
                  ),

              const Divider(),

              // 4. Move to Next Stage (نقل إلى المرحلة التالية)
              if (settings.canPassNextStage())
                ListTile(
                  leading: const Icon(Icons.forward_rounded, color: Colors.green),
                  title: Text(lang == AppLanguage.french ? 'Passer à l\'étape suivante' : 'نقل إلى المرحلة التالية'),
                  subtitle: Text(
                    lang == AppLanguage.french
                        ? 'Passer la commande de "${_translateStatus(currentStatus, lang)}" à l\'étape suivante'
                        : 'نقل الطلبية من حالة "${_translateStatus(currentStatus, lang)}" إلى المرحلة التي تليها',
                    style: const TextStyle(fontSize: 11),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    const stagesSequence = [
                      'Pending',
                      'Confirmed',
                      'In Progress',
                      'Partial Manufacturing',
                      'Partial Distribution',
                      'Full Manufacturing',
                      'Full Distribution',
                      'Installation',
                      'Reserve',
                      'Done',
                    ];

                    final normalizedStatus = (currentStatus == 'en_attente' || currentStatus == 'في الانتظار' || currentStatus == 'Draft' || currentStatus == 'New')
                        ? 'Pending'
                        : currentStatus;

                    int currentIndex = stagesSequence.indexOf(normalizedStatus);
                    if (currentIndex == -1) {
                      if (normalizedStatus.toLowerCase().contains('attente') || normalizedStatus.toLowerCase().contains('انتظار')) {
                        currentIndex = 0;
                      } else if (normalizedStatus.toLowerCase().contains('confirm')) {
                        currentIndex = 1;
                      } else {
                        currentIndex = 0;
                      }
                    }

                    if (currentIndex < stagesSequence.length - 1) {
                      final nextStatus = stagesSequence[currentIndex + 1];

                      if (normalizedStatus == 'In Progress') {
                        if (!mounted) return;
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => PopScope(
                            canPop: false,
                            child: AlertDialog(
                              content: Row(
                                children: [
                                  const CircularProgressIndicator(),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      lang == AppLanguage.french
                                          ? 'Vérification des mesures…'
                                          : 'جاري التحقق من القياسات…',
                                      style: const TextStyle(fontFamily: 'Cairo'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                        final allConfirmed = await _areAllMeasurementsConfirmed(orderData['id']);
                        if (mounted) Navigator.of(context, rootNavigator: true).pop();
                        if (!allConfirmed) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  lang == AppLanguage.french
                                      ? 'Impossible de passer à la fabrication sans valider les mesures !'
                                      : 'لا يمكن الانتقال للتصنيع إن لم تقم بتأكيد القياسات!',
                                ),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => OrderMeasurementsConfirmScreen(
                                  orderData: orderData,
                                  db: db,
                                ),
                              ),
                            );
                          }
                          return;
                        }
                      }

                      if (!mounted) return;
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => PopScope(
                          canPop: false,
                          child: AlertDialog(
                            content: Row(
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    lang == AppLanguage.french
                                        ? 'Mise à jour de la commande…'
                                        : 'جاري تحديث حالة الطلبية…',
                                    style: const TextStyle(fontFamily: 'Cairo'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );

                      await db.updateCommandeStatus(orderData['id'], nextStatus);
                      if (mounted) Navigator.of(context, rootNavigator: true).pop();

                      setState(() {
                        _data = db.readCommandesWithClients();
                      });

                      if (nextStatus == 'In Progress') {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                lang == AppLanguage.french
                                    ? 'Commande passée à: Confirmation des mesures'
                                    : 'تم نقل الطلبية إلى مرحلة تأكيد القياسات. يرجى تأكيد المقاسات.',
                              ),
                              backgroundColor: Colors.indigo,
                            ),
                          );
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => OrderMeasurementsConfirmScreen(
                                orderData: orderData,
                                db: db,
                              ),
                            ),
                          );
                        }
                      } else {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                lang == AppLanguage.french
                                    ? 'Commande passée à l\'étape: ${_translateStatus(nextStatus, lang)}'
                                    : 'تم نقل الطلبية بنجاح إلى مرحلة: ${_translateStatus(nextStatus, lang)}',
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      }
                    } else {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              lang == AppLanguage.french
                                  ? 'La commande est déjà dans la dernière étape (Done)!'
                                  : 'الطلبية وصلت بالفعل للمرحلة الأخيرة!',
                            ),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      }
                    }
                  },
                ),

              // 5. Change Status (تغيير الحالة المخصص يدوياً)
              if (settings.canChangeOrderStatus())
                ListTile(
                  leading: const Icon(Icons.swap_horiz, color: Colors.blue),
                  title: Text(Localization.translate('تغيير الحالة المخصص', lang)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showChangeStatusDialog(orderData);
                  },
                ),

              // 6. Modification
              if (settings.canEditOrders())
                ListTile(
                  leading: const Icon(Icons.edit, color: Colors.blue),
                  title: Text(
                    Localization.translate(
                      "Edit Order",
                      lang,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            CommandePage(db: db, editCommandeId: orderData['id']),
                      ),
                    ).then((_) {
                      setState(() {
                        _data = db.readCommandesWithClients();
                      });
                    });
                  },
                ),

              // NEW: 6.5 Duplicate
              if (settings.canDuplicateOrders())
                ListTile(
                  leading: const Icon(Icons.copy, color: Colors.blueGrey),
                  title: Text(Localization.translate('تكرار الطلبية (Duplicate)', lang)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      await _duplicateOrder(orderData);
                      setState(() {
                        _data = db.readCommandesWithClients();
                      });
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(Localization.translate('تم تكرار الطلبية بنجاح!', lang)),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${Localization.translate('حدث خطأ أثناء التكرار:', lang)} $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                ),

              const Divider(),

              // 7. Supprimer
              Consumer<AppSettingsProvider>(
                builder: (ctx2, settings, _) {
                  if (!settings.canDeleteOrders()) {
                    return const SizedBox.shrink();
                  }
                  return ListTile(
                    leading: const Icon(Icons.delete, color: Colors.redAccent),
                    title: Text(Localization.translate('مسح الطلبية (Supprimer)', lang)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showDeleteConfirmDialog(orderData['id']);
                    },
                  );
                },
              ),
            ],
          ),
        ),
      );
    },
    );
  }

  Future<void> _duplicateOrder(Map<String, dynamic> orderData) async {
    final oldId = orderData['id'];
    final clientId = orderData['client_id'];
    final orderType = orderData['order_type'] ?? 'Quotation';
    final description = orderData['description'] ?? '';
    final remise = (orderData['remise'] as num?)?.toDouble() ?? 0.0;
    final tva = (orderData['tva'] as num?)?.toDouble() ?? 0.0;
    final total = (orderData['total'] as num?)?.toDouble() ?? 0.0;
    final status = 'New';

    // Read commandlines
    final items = await db.readCommandeDetails(oldId);

    // Create new order (Notice: client_id should ideally be passed, but the DB insertCommande doesn't explicitly take orderType in this version.
    // wait, insertCommande signature: insertCommande(int idClient, String status, String description, double remise, double tva, double total, {double advancePayment})
    final newOrderId = await db.insertCommande(
      clientId ?? 0, // Fallback if no client
      status,
      description,
      remise,
      tva,
      total,
      advancePayment: 0.0, // duplicated order shouldn't carry over payments
    );

    // Create new lines
    for (var item in items) {
      await db.insertCommandeDetail(
        idCommande: newOrderId,
        largeur: (item['largeur'] as num?)?.toDouble() ?? 0.0,
        hauteur: (item['hauteur'] as num?)?.toDouble() ?? 0.0,
        game: item['game']?.toString() ?? '',
        quantity: (item['quantity'] as num?)?.toInt() ?? 1,
        glass: item['glass']?.toString() ?? '',
        color: item['color']?.toString() ?? '',
        volet: item['volet']?.toString() ?? '',
        accessories: item['accessories']?.toString() ?? '',
        description: item['description']?.toString() ?? '',
        price: (item['price'] as num?)?.toDouble() ?? 0.0,
        windowType: item['window_type']?.toString() ?? '',
        partitionsJson: item['partitions_json']?.toString() ?? '[]',
        drawingImagePath: item['drawing_image_path']?.toString() ?? '',
      );
    }
  }

  void _showDeleteConfirmDialog(int id) async {
    // 1. التحقق أولاً من أن عناصر الفاتورة لم تُستخدم في المخزون
    final isUsed = await db.isCommandeUsedInInventory(id);
    if (!mounted) return;

    if (isUsed) {
      // ✋ ممنوع الحذف: العناصر تُستخدم
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.block, color: Colors.red),
              const SizedBox(width: 8),
              const Text('لا يمكن الحذف'),
            ],
          ),
          content: const Text(
            'هذه الطلبية لا يمكن حذفها لأن بعض عناصرها قد تم استخدامها أو خصمها من المخزون.\n\nيمكنك تغيير حالتها بدلاً من حذفها.',
            textAlign: TextAlign.right,
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('موافق'),
            ),
          ],
        ),
      );
      return;
    }

    // 2. التحقق من الصلاحية (المدير فقط)
    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
    if (!settings.canDeleteOrders()) {
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.lock, color: Colors.orange),
              const SizedBox(width: 8),
              const Text('غير مصرح'),
            ],
          ),
          content: const Text(
            'ليس لديك صلاحية حذف الطلبيات.\nتواصل مع المدير للحصول على هذه الصلاحية.',
            textAlign: TextAlign.right,
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('موافق'),
            ),
          ],
        ),
      );
      return;
    }

    // 3. تأكيد الحذف النهائي
    bool? confirm = await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text(
          'هل أنت متأكد من حذف هذه الطلبية؟\nلا يمكن التراجع عن هذا الإجراء.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await db.deleteCommande(id);
      setState(() {
        _data = db.readCommandesWithClients();
      });
    }
  }

  Future<bool> _areAllMeasurementsConfirmed(int orderId) async {
    final details = await db.readCommandeDetails(orderId);
    if (details.isEmpty) return true;
    for (final detail in details) {
      final jsonStr = detail['instances_json']?.toString() ?? '';
      if (jsonStr.isEmpty) {
        return false;
      }
      try {
        final List decoded = jsonDecode(jsonStr);
        int sum = 0;
        for (final inst in decoded) {
          sum += (inst['qty'] as int? ?? 0);
        }
        if (sum != (detail['quantity'] as int)) {
          return false;
        }
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  void _showChangeStatusDialog(Map<String, dynamic> orderData) {
    final String currentStatus = orderData['status'] ?? 'Pending';
    final statuses = [
      'Pending',
      'Confirmed',
      'In Progress',
      'Partial Manufacturing',
      'Partial Distribution',
      'Full Manufacturing',
      'Full Distribution',
      'Installation',
      'Reserve',
      'Done',
    ];

    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.swap_horiz, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  Localization.translate('تغيير حالة الطلبية', lang),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Cairo'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Container(
            width: double.maxFinite,
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: statuses.map((stageKey) {
                  final bool isCurrent = (stageKey.toLowerCase() == currentStatus.toLowerCase()) ||
                      (stageKey == 'Pending' && (currentStatus == 'en_attente' || currentStatus == 'في الانتظار' || currentStatus == 'Draft' || currentStatus == 'New'));
                  final color = _getStatusColor(stageKey);
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: isCurrent ? color.withOpacity(0.12) : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isCurrent ? color : Colors.grey.shade300,
                        width: isCurrent ? 2 : 1,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      leading: CircleAvatar(
                        radius: 12,
                        backgroundColor: color,
                        child: isCurrent ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
                      ),
                      title: Text(
                        _translateStatus(stageKey, lang),
                        style: TextStyle(
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          color: isCurrent ? color : (Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87),
                          fontFamily: 'Cairo',
                          fontSize: 14,
                        ),
                      ),
                      trailing: isCurrent
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                lang == AppLanguage.french ? 'Actuel' : 'الحالية',
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                              ),
                            )
                          : const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                      onTap: () async {
                        final progressIndex = statuses.indexOf('In Progress');
                        final targetIndex = statuses.indexOf(stageKey);

                        if (targetIndex > progressIndex) {
                          final allConfirmed = await _areAllMeasurementsConfirmed(orderData['id']);
                          if (!allConfirmed) {
                            Navigator.pop(dialogContext);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    lang == AppLanguage.french
                                        ? 'Impossible de passer à la fabrication sans valider les mesures !'
                                        : 'لا يمكن الانتقال للتصنيع إن لم تقم بتأكيد القياسات!',
                                  ),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => OrderMeasurementsConfirmScreen(
                                    orderData: orderData,
                                    db: db,
                                  ),
                                ),
                              );
                            }
                            return;
                          }
                        }

                        Navigator.pop(dialogContext);
                        await db.updateCommandeStatus(orderData['id'], stageKey);
                        setState(() {
                          _data = db.readCommandesWithClients();
                        });

                        if (stageKey == 'In Progress') {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  lang == AppLanguage.french
                                      ? 'Commande passée à: Confirmation des mesures'
                                      : 'تم نقل الطلبية إلى مرحلة تأكيد القياسات. يرجى تأكيد المقاسات.',
                                ),
                                backgroundColor: Colors.indigo,
                              ),
                            );
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => OrderMeasurementsConfirmScreen(
                                  orderData: orderData,
                                  db: db,
                                ),
                              ),
                            );
                          }
                        } else {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  lang == AppLanguage.french
                                      ? 'Statut changé à: ${_translateStatus(stageKey, lang)}'
                                      : 'تم تغيير حالة الطلبية إلى: ${_translateStatus(stageKey, lang)}',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                Localization.translate('إلغاء', lang),
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showHeavyLoadingDialog(BuildContext context, AppLanguage lang) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogCtx) {
        _loadingDialogContext = dialogCtx;
        return PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 20),
                Text(
                  lang == AppLanguage.french ? 'Génération du document...' : 'جاري تحضير المستند...',
                  style: const TextStyle(fontFamily: 'Cairo'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _dismissHeavyLoadingDialog() {
    if (_loadingDialogContext != null) {
      Navigator.of(_loadingDialogContext!).pop();
      _loadingDialogContext = null;
    }
  }
}
