import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:database_data/sql_database.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/Commande/devis_builder.dart';
import 'package:database_data/Commande/devis_preview_screen.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/Commande/capture_image.dart';

class PartialProformaScreen extends StatefulWidget {
  final Map<String, dynamic> order;
  final bool hidePrices;
  final String? documentTitleKey;
  final bool autoOpenBonDeChargeOnSave;

  const PartialProformaScreen({
    super.key,
    required this.order,
    this.hidePrices = false,
    this.documentTitleKey,
    this.autoOpenBonDeChargeOnSave = false,
  });

  @override
  State<PartialProformaScreen> createState() => _PartialProformaScreenState();
}

class _PartialProformaScreenState extends State<PartialProformaScreen> {
  final SqlDatabase _db = SqlDatabase();
  bool _isLoading = true;
  List<Map<String, dynamic>> _items = [];
  
  // Map to hold quantities to deliver now
  final Map<int, int> _deliverQtys = {};
  
  // Track remaining quantities
  final Map<int, int> _remainingQtys = {};

  // Controllers for text fields to keep them in sync
  final Map<int, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _loadOrderDetails();
  }

  Future<void> _loadOrderDetails() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final rawItems = await _db.readCommandeDetails(widget.order['id']);
      _items = rawItems.map((item) => Map<String, dynamic>.from(item)).toList();
      
      _deliverQtys.clear();
      _remainingQtys.clear();
      
      for (var ctrl in _controllers.values) {
        ctrl.dispose();
      }
      _controllers.clear();
      
      for (var item in _items) {
        final id = item['id'] as int;
        final totalQty = item['quantity'] as int;
        final deliveredQty = item['delivered_qty'] as int? ?? 0;
        final remaining = totalQty - deliveredQty;
        
        _remainingQtys[id] = remaining >= 0 ? remaining : 0;
        _deliverQtys[id] = 0;
        _controllers[id] = TextEditingController(text: '0');
      }
    } catch (e) {
      debugPrint('Error loading order details: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    for (var ctrl in _controllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  String _tr(String ar, String fr, String en, AppLanguage lang) {
    switch (lang) {
      case AppLanguage.french:
        return fr;
      case AppLanguage.english:
        return en;
      case AppLanguage.arabic:
        return ar;
    }
  }

  String _t(String key) {
    return Localization.translate(key, Provider.of<AppSettingsProvider>(context, listen: false).language);
  }

  // Helper to format currency
  String _formatPrice(double value) {
    final formatter = NumberFormat('#,###.##');
    return '${formatter.format(value)} د.ج';
  }

  // Calculate totals for currently selected items to deliver now
  int get _totalSelectedCount {
    return _deliverQtys.values.fold(0, (sum, val) => sum + val);
  }

  double get _totalSelectedAmount {
    double total = 0.0;
    for (var item in _items) {
      final id = item['id'] as int;
      final qty = _deliverQtys[id] ?? 0;
      final price = (item['price'] as num?)?.toDouble() ?? 0.0;
      total += qty * price;
    }
    return total;
  }

  Future<void> _resetAllDeliveries() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.red),
            const SizedBox(width: 8),
            Text(
              _t('تأكيد إعادة التعيين'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
            ),
          ],
        ),
        content: Text(
          _t('هل أنت متأكد من رغبتك في إعادة تعيين كل كميات التسليم إلى صفر لهذه الطلبية؟ سيتم حذف جميع سجلات التسليم السابقة لمواد هذا الطلب.'),
          style: const TextStyle(fontFamily: 'Cairo', height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_t('إلغاء'), style: TextStyle(color: Colors.grey.shade600, fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('تأكيد وإعادة تعيين'), style: const TextStyle(color: Colors.white, fontFamily: 'Cairo')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _isLoading = true;
      });
      try {
        await _db.resetCommandeDeliveredQty(widget.order['id'] as int);
        await _loadOrderDetails();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_t('تمت إعادة تعيين كل كميات التسليم بنجاح')),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_t('حدث خطأ أثناء إعادة التعيين: $e')),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  // Open dialog to edit previously delivered quantity directly
  Future<void> _showEditDeliveredDialog(Map<String, dynamic> item) async {
    final id = item['id'] as int;
    final total = item['quantity'] as int;
    final currentDelivered = item['delivered_qty'] as int? ?? 0;
    
    final controller = TextEditingController(text: currentDelivered.toString());
    
    final newDelivered = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          _t('تعديل الكمية المسلمة سابقاً'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${item['description']}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              '${_t('الكمية الإجمالية المطلوبة')}: $total',
              style: TextStyle(color: Colors.grey.shade600, fontFamily: 'Cairo', fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                labelText: _t('الكمية المسلمة المعدلة'),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_t('إلغاء'), style: TextStyle(color: Colors.grey.shade600, fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              final val = int.tryParse(controller.text) ?? -1;
              if (val < 0 || val > total) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${_t('الكمية يجب أن تكون بين')} 0 و $total'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.pop(context, val);
            },
            child: Text(_t('حفظ'), style: const TextStyle(color: Colors.white, fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
    
    if (newDelivered != null) {
      setState(() {
        _isLoading = true;
      });
      try {
        await _db.updateCommandeDetailDeliveredQty(id, newDelivered);
        await _loadOrderDetails();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_t('تم تحديث الكمية المسلمة بنجاح')),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطأ أثناء التعديل: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  // Preview partial proforma PDF without saving/committing to database
  Future<void> _previewProformaOnly() async {
    if (_totalSelectedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('يرجى تحديد كمية أكبر من صفر لعنصر واحد على الأقل للمعاينة!')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final List<Map<String, dynamic>> partialItems = [];

      for (var item in _items) {
        final id = item['id'] as int;
        final qtyNow = _deliverQtys[id] ?? 0;
        if (qtyNow > 0) {
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
                  final model = WindowModel(db: _db);
                  await applyWindowModelAndLoadCatalog(model, modelMap);
                  final newPath = await saveWindowImageToDisk(model);
                  if (newPath.isNotEmpty) {
                    await _db.updateCommandeDetailImagePath(id, newPath);
                    item['drawing_image_path'] = newPath;
                  }
                }
              } catch (_) {}
            }
          }

          final clonedItem = Map<String, dynamic>.from(item);
          clonedItem['quantity'] = qtyNow;
          partialItems.add(clonedItem);
        }
      }

      final workshop = await DevisBuilder.loadWorkshopInfo();
      final devis = await DevisBuilder.build(
        order: widget.order,
        items: partialItems,
        workshop: workshop,
        isPartial: true,
        hidePrices: widget.hidePrices,
        documentTitleKey: widget.documentTitleKey,
      );

      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DevisPreviewScreen(data: devis),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء معاينة الفاتورة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Confirm and commit selected quantities to database
  Future<void> _confirmAndSaveDelivery() async {
    if (_totalSelectedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('يرجى تحديد كمية أكبر من صفر لعنصر واحد على الأقل لتأكيد التسليم!')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.green),
            const SizedBox(width: 8),
            Text(
              _t('تأكيد وحفظ التسليم'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
            ),
          ],
        ),
        content: Text(
          '${_t('هل ترغب في تأكيد وحفظ تسليم')} $_totalSelectedCount ${_t('نافذة في قاعدة البيانات؟')} \n\n${_t('سيتم تحديث سجلات الطلب بالكميات المحددة.')}',
          style: const TextStyle(fontFamily: 'Cairo', height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_t('إلغاء'), style: TextStyle(color: Colors.grey.shade600, fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('تأكيد وحفظ'), style: const TextStyle(color: Colors.white, fontFamily: 'Cairo')),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final List<Map<String, dynamic>> partialItems = [];

      for (var item in _items) {
        final id = item['id'] as int;
        final qtyNow = _deliverQtys[id] ?? 0;
        if (qtyNow > 0) {
          final oldDelivered = item['delivered_qty'] as int? ?? 0;
          final newDelivered = oldDelivered + qtyNow;
          
          await _db.updateCommandeDetailDeliveredQty(id, newDelivered);
          
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
                  final model = WindowModel(db: _db);
                  await applyWindowModelAndLoadCatalog(model, modelMap);
                  final newPath = await saveWindowImageToDisk(model);
                  if (newPath.isNotEmpty) {
                    await _db.updateCommandeDetailImagePath(id, newPath);
                    item['drawing_image_path'] = newPath;
                  }
                }
              } catch (_) {}
            }
          }

          final clonedItem = Map<String, dynamic>.from(item);
          clonedItem['quantity'] = qtyNow;
          partialItems.add(clonedItem);
        }
      }

      // Save delivery history
      final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
      final itemsStr = jsonEncode(partialItems);
      final deliveryId = await _db.insertCommandeDelivery(
        widget.order['id'] as int,
        widget.order['client_id'] as int? ?? 0,
        dateStr,
        itemsStr,
        _totalSelectedAmount,
      );

      final workshop = await DevisBuilder.loadWorkshopInfo();
      final devis = await DevisBuilder.build(
        order: widget.order,
        items: partialItems,
        workshop: workshop,
        isPartial: true,
        hidePrices: widget.hidePrices,
        documentTitleKey: widget.autoOpenBonDeChargeOnSave ? 'BON_CHARGE' : widget.documentTitleKey,
      );

      await _loadOrderDetails();

      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        if (widget.autoOpenBonDeChargeOnSave) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => DevisPreviewScreen(
                data: devis,
                deliveryId: deliveryId,
                initialIsLoaded: false,
              ),
            ),
          );
        } else {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Column(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 50),
                  const SizedBox(height: 10),
                  Text(
                    _t('تم حفظ التسليم بنجاح'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                  ),
                ],
              ),
              content: Text(
                _t('تم تأكيد وحفظ كميات التسليم في قاعدة البيانات بنجاح. هل ترغب في طباعة الفاتورة التقديرية الجزئية للتسليم الحالي الآن؟'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Cairo', height: 1.4),
              ),
              actionsAlignment: MainAxisAlignment.center,
              actions: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: Text(_t('إغلاق'), style: const TextStyle(fontFamily: 'Cairo')),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DevisPreviewScreen(data: devis),
                      ),
                    );
                  },
                  icon: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 18),
                  label: Text(_t('طباعة الفاتورة'), style: const TextStyle(color: Colors.white, fontFamily: 'Cairo')),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ أثناء تأكيد وحفظ التسليم: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

  // Retrieve and show modal bottom sheet with all past partial delivery invoices
  Future<void> _showDeliveriesHistory() async {
    setState(() {
      _isLoading = true;
    });
    List<Map<String, dynamic>> history = [];
    try {
      history = await _db.readCommandeDeliveries(widget.order['id'] as int);
    } catch (e) {
      debugPrint('Error reading deliveries: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }

    if (mounted) {
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) {
          final isRtl = Provider.of<AppSettingsProvider>(context, listen: false).language == AppLanguage.arabic;
          return Directionality(
            textDirection: isRtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
            child: Container(
              padding: const EdgeInsets.all(16),
              height: MediaQuery.of(context).size.height * 0.6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _t('سجل الفواتير الجزئية المسلمة'),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: history.isEmpty
                        ? Center(
                            child: Text(
                              _t('لا توجد فواتير جزئية مسلمة سابقاً'),
                              style: const TextStyle(fontFamily: 'Cairo', color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            itemCount: history.length,
                            itemBuilder: (context, idx) {
                              final del = history[idx];
                              final date = del['delivery_date']?.toString() ?? '';
                              final amount = (del['total_amount'] as num?)?.toDouble() ?? 0.0;
                              
                              List<dynamic> itemsList = [];
                              try {
                                itemsList = jsonDecode(del['items_json'] as String) as List;
                              } catch (_) {}
                              
                              int count = 0;
                              for (var it in itemsList) {
                                count += (it['quantity'] as num?)?.toInt() ?? 0;
                              }

                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: Colors.grey.shade200),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  title: Text(
                                    date,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text(
                                    '$count ${_t('نافذة')} | ${_formatPrice(amount)}',
                                    style: TextStyle(
                                      color: Colors.blue.shade700,
                                      fontFamily: 'Cairo',
                                      fontSize: 13,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                                    onPressed: () async {
                                      Navigator.pop(ctx);
                                      setState(() {
                                        _isLoading = true;
                                      });
                                      try {
                                        final List<Map<String, dynamic>> items = itemsList
                                            .map((e) => Map<String, dynamic>.from(e as Map))
                                            .toList();
                                        
                                        final workshop = await DevisBuilder.loadWorkshopInfo();
                                        final devis = await DevisBuilder.build(
                                          order: widget.order,
                                          items: items,
                                          workshop: workshop,
                                          isPartial: true,
                                          hidePrices: widget.hidePrices,
                                          documentTitleKey: widget.documentTitleKey,
                                        );

                                        if (mounted) {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => DevisPreviewScreen(data: devis),
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
                                          );
                                        }
                                      } finally {
                                        if (mounted) {
                                          setState(() {
                                            _isLoading = false;
                                          });
                                        }
                                      }
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
  }

  // Update quantity and rebuild UI
  void _updateQty(int id, int newVal, int remaining) {
    if (newVal < 0 || newVal > remaining) return;
    setState(() {
      _deliverQtys[id] = newVal;
      _controllers[id]?.text = newVal.toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    final language = Provider.of<AppSettingsProvider>(context).language;
    final isRtl = language == AppLanguage.arabic;

    int totalOrderItemsCount = 0;
    int totalDeliveredItemsCount = 0;
    for (var item in _items) {
      totalOrderItemsCount += item['quantity'] as int;
      totalDeliveredItemsCount += item['delivered_qty'] as int? ?? 0;
    }
    double deliveryProgress = totalOrderItemsCount > 0 
        ? totalDeliveredItemsCount / totalOrderItemsCount 
        : 0.0;

    final clientFirst = widget.order['firstname'] ?? '';
    final clientLast = widget.order['lastname'] ?? '';
    final clientName = '$clientFirst $clientLast'.trim().isEmpty ? 'زبون غير معروف' : '$clientFirst $clientLast'.trim();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          _tr('فاتورة تحميل جزئية', 'Facture de chargement partielle', 'Partial Loading Note', language),
          style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
        ),
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Theme.of(context).appBarTheme.backgroundColor,
        actions: [
          IconButton(
            tooltip: _tr('سجل الفواتير المسلمة', 'Historique des livraisons', 'Deliveries History', language),
            icon: const Icon(Icons.history_edu_rounded),
            onPressed: _showDeliveriesHistory,
          ),
          IconButton(
            tooltip: _tr('إعادة تعيين كل التسليمات', 'Réinitialiser toutes les livraisons', 'Reset All Deliveries', language),
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _resetAllDeliveries,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Text(
                    _tr('لا توجد عناصر في هذه الطلبية!', 'Aucun élément dans cette commande!', 'No items found in this order!', language),
                    style: TextStyle(fontSize: 16, fontFamily: 'Cairo', color: textColor),
                  ),
                )
              : Directionality(
                  textDirection: isRtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
                  child: Column(
                    children: [
                      // Top Order Progress Card
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.all(12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isDark ? const Color(0xFF334155) : Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${_tr('الطلب', 'Commande', 'Order', language)} #${widget.order['id']}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    fontFamily: 'Cairo',
                                    color: textColor,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    clientName,
                                    style: TextStyle(
                                      color: Colors.blue.shade800,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${_t('إجمالي تقدم تسليم الطلبية')}:',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                                Text(
                                  '$totalDeliveredItemsCount / $totalOrderItemsCount ${_t('نافذة')}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: deliveryProgress,
                                minHeight: 8,
                                backgroundColor: Colors.grey.shade100,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  deliveryProgress == 1.0 ? Colors.green : Colors.blue,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // List of elements
                      Expanded(
                        child: ListView.builder(
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            final id = item['id'] as int;
                            final total = item['quantity'] as int;
                            final delivered = item['delivered_qty'] as int? ?? 0;
                            final remaining = _remainingQtys[id] ?? 0;
                            final qtyNow = _deliverQtys[id] ?? 0;
                            final itemPrice = (item['price'] as num?)?.toDouble() ?? 0.0;
                            final itemSubtotal = qtyNow * itemPrice;
                            final ctrl = _controllers[id];

                            final imagePath = item['drawing_image_path']?.toString() ?? '';
                            final hasImage = imagePath.isNotEmpty && File(imagePath).existsSync();

                            return Card(
                              color: cardBg,
                              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(color: isDark ? const Color(0xFF334155) : Colors.transparent),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 1. Image + Title/Subtitle Info
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (hasImage)
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(10),
                                            child: Image.file(
                                              File(imagePath),
                                              width: 65,
                                              height: 65,
                                              fit: BoxFit.contain,
                                            ),
                                          )
                                        else
                                          Container(
                                            width: 65,
                                            height: 65,
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade100,
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: Colors.grey.shade200),
                                            ),
                                            child: const Icon(Icons.crop_square_outlined, color: Colors.grey, size: 28),
                                          ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item['description']?.toString() ?? '',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                  fontFamily: 'Cairo',
                                                  color: textColor,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${item['game']} | ${item['largeur']} × ${item['hauteur']}',
                                                style: TextStyle(
                                                  color: Colors.grey.shade600,
                                                  fontSize: 12,
                                                  fontFamily: 'Cairo',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    const Divider(height: 1),
                                    const SizedBox(height: 12),
                                    
                                    // 2. Status counts (Total, Delivered, Remaining)
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        _statItem(_t('الإجمالي'), total, Colors.blue),
                                        
                                        // Delivered with Edit Button
                                        Column(
                                          children: [
                                            Text(
                                              _t('سلمت سابقاً'),
                                              style: TextStyle(
                                                color: Colors.grey.shade600,
                                                fontSize: 12,
                                                fontFamily: 'Cairo',
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green.withOpacity(0.08),
                                                    borderRadius: BorderRadius.circular(12),
                                                    border: Border.all(color: Colors.green.withOpacity(0.2)),
                                                  ),
                                                  child: Text(
                                                    delivered.toString(),
                                                    style: const TextStyle(
                                                      color: Colors.green,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                IconButton(
                                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                                  padding: EdgeInsets.zero,
                                                  icon: const Icon(Icons.edit_outlined, color: Colors.blueGrey, size: 18),
                                                  tooltip: _t('تعديل الكمية المسلمة سابقاً'),
                                                  onPressed: () => _showEditDeliveredDialog(item),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        
                                        _statItem(_t('المتبقي'), remaining, remaining > 0 ? Colors.orange : Colors.grey),
                                      ],
                                    ),
                                    
                                    // 3. Delivery Action Selector if remaining > 0
                                    if (remaining > 0) ...[
                                      const SizedBox(height: 14),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.blue.shade100),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  _t('التسليم الحالي:'),
                                                  style: TextStyle(
                                                    fontFamily: 'Cairo',
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                    color: Colors.blue.shade900,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  _formatPrice(itemSubtotal),
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                    color: Colors.blue.shade700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            // Numeric Spinner
                                            Container(
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius: BorderRadius.circular(25),
                                                border: Border.all(color: Colors.blue.shade200),
                                              ),
                                              child: Row(
                                                children: [
                                                  IconButton(
                                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                                    padding: EdgeInsets.zero,
                                                    icon: const Icon(Icons.remove, color: Colors.blue, size: 18),
                                                    onPressed: qtyNow > 0
                                                        ? () => _updateQty(id, qtyNow - 1, remaining)
                                                        : null,
                                                  ),
                                                  Container(
                                                    width: 40,
                                                    alignment: Alignment.center,
                                                    child: TextField(
                                                      controller: ctrl,
                                                      keyboardType: TextInputType.number,
                                                      textAlign: TextAlign.center,
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 15,
                                                        color: Colors.blue.shade900,
                                                      ),
                                                      decoration: const InputDecoration(
                                                        isDense: true,
                                                        contentPadding: EdgeInsets.zero,
                                                        border: InputBorder.none,
                                                      ),
                                                      onChanged: (text) {
                                                        final val = int.tryParse(text) ?? 0;
                                                        if (val < 0) {
                                                          _updateQty(id, 0, remaining);
                                                        } else if (val > remaining) {
                                                          _updateQty(id, remaining, remaining);
                                                        } else {
                                                          setState(() {
                                                            _deliverQtys[id] = val;
                                                          });
                                                        }
                                                      },
                                                    ),
                                                  ),
                                                  IconButton(
                                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                                    padding: EdgeInsets.zero,
                                                    icon: const Icon(Icons.add, color: Colors.blue, size: 18),
                                                    onPressed: qtyNow < remaining
                                                        ? () => _updateQty(id, qtyNow + 1, remaining)
                                                        : null,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ] else ...[
                                      const SizedBox(height: 12),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade50,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.green.shade100),
                                        ),
                                        alignment: Alignment.center,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Icon(Icons.check_circle, color: Colors.green, size: 20),
                                            const SizedBox(width: 8),
                                            Text(
                                              _t('تم تسليم هذا البند بالكامل'),
                                              style: TextStyle(
                                                fontFamily: 'Cairo',
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                                color: Colors.green.shade800,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      
                      // Bottom Summary & Actions Panel
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                          border: Border(top: BorderSide(color: isDark ? const Color(0xFF334155) : Colors.grey.shade200)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 15,
                              offset: const Offset(0, -4),
                            ),
                          ],
                        ),
                        child: SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Summary counts and prices
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${_t('الكميات المحددة')}:',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 13,
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '$_totalSelectedCount ${_t('نافذة')}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${_t('القيمة الإجمالية للتسليم')}:',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 13,
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _formatPrice(_totalSelectedAmount),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                          color: Colors.blue.shade800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              
                              // Dual Actions: Preview vs. Confirm & Save
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(double.infinity, 54),
                                        side: BorderSide(color: Colors.blue.shade600, width: 1.5),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                      ),
                                      onPressed: _previewProformaOnly,
                                      icon: Icon(Icons.remove_red_eye_outlined, color: Colors.blue.shade700, size: 20),
                                      label: Text(
                                        _t('معاينة الفاتورة'),
                                        style: TextStyle(
                                          color: Colors.blue.shade700,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green.shade600,
                                        minimumSize: const Size(double.infinity, 54),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        elevation: 2,
                                      ),
                                      onPressed: _confirmAndSaveDelivery,
                                      icon: const Icon(Icons.check, color: Colors.white, size: 20),
                                      label: Text(
                                        _t('تأكيد وحفظ التسليم'),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _statItem(String label, int value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 12,
            fontFamily: 'Cairo',
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Text(
            value.toString(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
