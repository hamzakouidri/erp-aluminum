import 'dart:async';
import 'package:database_data/widgets/app_material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:latlong2/latlong.dart';
import '../services/cloud_sync_service.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../sql_database.dart';
import 'map_picker_screen.dart';
import 'supplier_details_screen.dart';

class SuppliersScreen extends StatefulWidget {
  final SqlDatabase db;
  const SuppliersScreen({super.key, required this.db});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  List<Map<String, dynamic>> _suppliers = [];
  bool _isLoading = true;
  StreamSubscription? _syncSub;

  @override
  void initState() {
    super.initState();
    _fetchSuppliers();
    _syncSub = CloudSyncService().dbUpdateStream.listen((_) {
      if (mounted) {
        _fetchSuppliers();
      }
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchSuppliers() async {
    final data = await widget.db.readSuppliers();
    setState(() {
      _suppliers = data;
      _isLoading = false;
    });
  }

  void _showSupplierDialog([Map<String, dynamic>? supplier]) {
    final nameController = TextEditingController(text: supplier?['name'] ?? '');
    final phoneController = TextEditingController(
      text: supplier?['phone'] ?? '',
    );
    final emailController = TextEditingController(
      text: supplier?['email'] ?? '',
    );
    final notesController = TextEditingController(
      text: supplier?['notes'] ?? '',
    );
    final addressController = TextEditingController(
      text: supplier?['address']?.toString() ?? '',
    );
    double? latitude = supplier?['latitude'] != null ? (supplier!['latitude'] as num).toDouble() : null;
    double? longitude = supplier?['longitude'] != null ? (supplier!['longitude'] as num).toDouble() : null;

    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(
            supplier == null
                ? Localization.translate('إضافة مورد جديد', lang)
                : Localization.translate('تعديل بيانات المورد', lang),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: Localization.translate('اسم المورد', lang),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: InputDecoration(
                    labelText: Localization.translate('رقم الهاتف', lang),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: Localization.translate('البريد الإلكتروني', lang),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: addressController,
                  decoration: InputDecoration(
                    labelText: Localization.translate('العنوان', lang),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: Localization.translate('ملاحظات', lang),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final LatLng? picked = await Navigator.push<LatLng>(
                            context,
                            MaterialPageRoute(
                              builder: (context) => MapPickerScreen(
                                initialLatitude: latitude,
                                initialLongitude: longitude,
                              ),
                            ),
                          );
                          if (picked != null) {
                            setStateDialog(() {
                              latitude = picked.latitude;
                              longitude = picked.longitude;
                            });
                          }
                        },
                        icon: const Icon(Icons.map, color: Colors.blue),
                        label: Text(
                          Localization.translate(
                            latitude == null ? 'تحديد الموقع على الخريطة' : 'تعديل الموقع على الخريطة',
                            lang,
                          ),
                        ),
                      ),
                    ),
                    if (latitude != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.clear, color: Colors.red),
                        onPressed: () {
                          setStateDialog(() {
                            latitude = null;
                            longitude = null;
                          });
                        },
                        tooltip: Localization.translate('حذف الموقع', lang),
                      ),
                    ],
                  ],
                ),
                if (latitude != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6.0),
                    child: Text(
                      '📍 Lat: ${latitude!.toStringAsFixed(6)}, Lng: ${longitude!.toStringAsFixed(6)}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(Localization.translate('إلغاء', lang)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(Localization.translate('الاسم مطلوب', lang))));
                  return;
                }

                final data = {
                  'name': nameController.text.trim(),
                  'phone': phoneController.text.trim(),
                  'email': emailController.text.trim(),
                  'notes': notesController.text.trim(),
                  'address': addressController.text.trim(),
                  'latitude': latitude,
                  'longitude': longitude,
                };

                if (supplier == null) {
                  await widget.db.insertSupplier(data);
                } else {
                  await widget.db.updateSupplier(supplier['id'], data);
                }

                if (context.mounted) Navigator.pop(context);
                _fetchSuppliers();
              },
              child: Text(Localization.translate('حفظ', lang)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSupplier(int id) async {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(Localization.translate('تأكيد الحذف', lang)),
        content: Text(Localization.translate('هل أنت متأكد من حذف هذا المورد؟', lang)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(Localization.translate('إلغاء', lang)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              Localization.translate('حذف', lang),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.db.deleteSupplier(id);
      _fetchSuppliers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    return Scaffold(
      appBar: AppBar(
        title: Text(Localization.translate('الموردين', lang)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: Localization.translate('تحديث', lang),
            onPressed: () async {
              await CloudSyncService().syncPendingNow();
              _fetchSuppliers();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showSupplierDialog(),
        icon: const Icon(Icons.add),
        label: Text(Localization.translate('مورد جديد', lang)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _suppliers.isEmpty
              ? Center(child: Text(Localization.translate('لا يوجد موردين مضافين حتى الآن.', lang)))
          : ListView.builder(
              itemCount: _suppliers.length,
              itemBuilder: (context, index) {
                final sup = _suppliers[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: ListTile(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SupplierDetailsScreen(supplier: sup),
                        ),
                      );
                    },
                    leading: const CircleAvatar(
                      backgroundColor: Colors.blue,
                      child: Icon(Icons.local_shipping, color: Colors.white),
                    ),
                    title: Text(
                      sup['name'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (sup['phone'] != null && sup['phone'].isNotEmpty)
                          Text('📞 ${sup['phone']}'),
                        if (sup['email'] != null && sup['email'].isNotEmpty)
                          Text('✉️ ${sup['email']}'),
                        if (sup['notes'] != null && sup['notes'].isNotEmpty)
                          Text('📝 ${sup['notes']}'),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (sup['latitude'] != null && sup['longitude'] != null)
                          IconButton(
                            icon: const Icon(Icons.map, color: Colors.blue),
                            onPressed: () => _launchMap(
                              (sup['latitude'] as num).toDouble(),
                              (sup['longitude'] as num).toDouble(),
                            ),
                            tooltip: Localization.translate('فتح الموقع في الخرائط', lang),
                          ),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.green),
                          onPressed: () => _showSupplierDialog(sup),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteSupplier(sup['id']),
                        ),
                      ],
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
    );
  }

  Future<void> _launchMap(double lat, double lng) async {
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}
