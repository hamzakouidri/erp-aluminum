import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../sql_database.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';

class LinkExistingOrdersScreen extends StatefulWidget {
  final SqlDatabase db;
  final int projectId;

  const LinkExistingOrdersScreen({
    super.key,
    required this.db,
    required this.projectId,
  });

  @override
  State<LinkExistingOrdersScreen> createState() => _LinkExistingOrdersScreenState();
}

class _LinkExistingOrdersScreenState extends State<LinkExistingOrdersScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _unlinkedOrders = [];
  String _searchQuery = '';
  final Set<int> _selectedOrderIds = {};
  final TextEditingController _searchController = TextEditingController();

  String _tr(String ar, String fr, String en, AppLanguage lang) {
    switch (lang) {
      case AppLanguage.arabic:
        return ar;
      case AppLanguage.french:
        return fr;
      default:
        return en;
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchUnlinkedOrders();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchUnlinkedOrders() async {
    setState(() => _isLoading = true);
    try {
      final myDb = await widget.db.db;
      final data = await myDb!.rawQuery('''
        SELECT co.*, c.firstname, c.lastname FROM Commandes co
        JOIN Client c ON co.client_id = c.id
        WHERE (co.is_deleted IS NULL OR co.is_deleted = 0)
          AND (co.project_id IS NULL OR co.project_id = 0)
        ORDER BY co.created_at DESC
      ''');
      setState(() {
        _unlinkedOrders = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        final lang = Provider.of<AppSettingsProvider>(
          context,
          listen: false,
        ).language;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_tr('خطأ أثناء جلب الطلبيات', 'Erreur lors du chargement des commandes', 'Error loading orders', lang)}: $e',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredOrders {
    if (_searchQuery.trim().isEmpty) return _unlinkedOrders;
    
    final query = _searchQuery.toLowerCase();
    return _unlinkedOrders.where((o) {
      final orderId = o['id']?.toString() ?? '';
      final firstName = (o['firstname'] ?? '').toString().toLowerCase();
      final lastName = (o['lastname'] ?? '').toString().toLowerCase();
      final clientName = '$firstName $lastName';
      
      return orderId.contains(query) || 
             firstName.contains(query) || 
             lastName.contains(query) ||
             clientName.contains(query);
    }).toList();
  }

  Future<void> _saveSelectedOrders() async {
    if (_selectedOrderIds.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final myDb = await widget.db.db;
      for (final id in _selectedOrderIds) {
        await myDb!.rawUpdate(
          'UPDATE Commandes SET project_id = ? WHERE id = ?',
          [widget.projectId, id],
        );
      }
      if (mounted) {
        Navigator.pop(context, true); // return true to refresh parent
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        final lang = Provider.of<AppSettingsProvider>(
          context,
          listen: false,
        ).language;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_tr('خطأ أثناء ربط الطلبيات', 'Erreur lors de la liaison des commandes', 'Error linking orders', lang)}: $e',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final isRtl = lang == AppLanguage.arabic;
    final list = _filteredOrders;

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          title: const Text(
            'ربط طلبيات موجودة للمشروع',
            style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.blueGrey.shade900,
          foregroundColor: Colors.white,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // Search Input field
                    TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val),
                      decoration: InputDecoration(
                        hintText: Localization.translate(
                          'البحث برقم الطلبية أو اسم الزبون...',
                          Provider.of<AppSettingsProvider>(context).language,
                        ),
                        hintStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Scrollable list of unlinked orders
                    Expanded(
                      child: list.isEmpty
                          ? Center(
                              child: Text(
                                _searchQuery.isEmpty
                                    ? 'لا توجد طلبيات غير مرتبطة بمشاريع حالياً.'
                                    : 'لا توجد نتائج للبحث المكتوب.',
                                style: TextStyle(color: Colors.grey.shade500, fontFamily: 'Cairo'),
                              ),
                            )
                          : ListView.builder(
                              itemCount: list.length,
                              itemBuilder: (context, idx) {
                                final order = list[idx];
                                final orderId = order['id'] as int;
                                final clientName = '${order['firstname']} ${order['lastname']}'.trim();
                                final date = order['created_at']?.toString().split('T')[0] ?? '';
                                final netPayable = (order['net_payable'] as num?)?.toDouble() ?? 0.0;
                                final rawTotal = (order['total'] as num?)?.toDouble() ?? 0.0;
                                final total = netPayable > 0 ? netPayable : rawTotal;
                                final status = order['status'] ?? 'New';
                                
                                final isSelected = _selectedOrderIds.contains(orderId);

                                return Card(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  elevation: isSelected ? 3 : 1,
                                  borderOnForeground: true,
                                  color: isSelected ? Colors.indigo.shade50.withValues(alpha: 0.3) : Colors.white,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                    leading: CircleAvatar(
                                      backgroundColor: isSelected ? Colors.indigo.shade100 : Colors.blue.shade50,
                                      child: Icon(
                                        isSelected ? Icons.check_circle : Icons.receipt_long_rounded,
                                        color: isSelected ? Colors.indigo : Colors.blue,
                                      ),
                                    ),
                                    title: Text(
                                      'طلب #${(order['order_code'] as num?)?.toInt() ?? (order['display_number'] as num?)?.toInt() ?? (orderId < 100000 ? orderId : '')} - $clientName',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                                    ),
                                    subtitle: Text(
                                      'التاريخ: $date  ·  الحالة: $status  ·  المبلغ: ${total.toStringAsFixed(2)} دج',
                                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 11),
                                    ),
                                    trailing: Checkbox(
                                      value: isSelected,
                                      activeColor: Colors.indigo,
                                      onChanged: (checked) {
                                        setState(() {
                                          if (checked == true) {
                                            _selectedOrderIds.add(orderId);
                                          } else {
                                            _selectedOrderIds.remove(orderId);
                                          }
                                        });
                                      },
                                    ),
                                    onTap: () {
                                      setState(() {
                                        if (isSelected) {
                                          _selectedOrderIds.remove(orderId);
                                        } else {
                                          _selectedOrderIds.add(orderId);
                                        }
                                      });
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
        // Bottom add bar
        bottomNavigationBar: _selectedOrderIds.isEmpty
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      elevation: 4,
                    ),
                    icon: const Icon(Icons.add_link),
                    label: Text(
                      'ربط الطلبيات المحددة (${_selectedOrderIds.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'Cairo'),
                    ),
                    onPressed: _saveSelectedOrders,
                  ),
                ),
              ),
      ),
    );
  }
}
