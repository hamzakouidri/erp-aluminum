import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:database_data/services/supabase_workshop_sync_service.dart';
import 'package:database_data/sql_database.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';

class WorkshopProfileScreen extends StatefulWidget {
  const WorkshopProfileScreen({super.key});

  @override
  State<WorkshopProfileScreen> createState() => _WorkshopProfileScreenState();
}

class _WorkshopProfileScreenState extends State<WorkshopProfileScreen> {
  final _auth = FirebaseAuth.instance;
  final _db = SqlDatabase();

  bool _isLoading = true;
  Map<String, dynamic>? _managerData;
  List<Map<String, dynamic>> _workers = [];

  final _workshopNameController = TextEditingController();
  final _locationController = TextEditingController();
  final _phoneController = TextEditingController();
  final _specialtiesController = TextEditingController();
  final _managerNameController = TextEditingController();
  final _workerCountController = TextEditingController();
  final _rcController = TextEditingController();
  final _nifController = TextEditingController();
  final _nisController = TextEditingController();

  String _t(String key) => Localization.translate(
    key,
    Provider.of<AppSettingsProvider>(context, listen: false).language,
  );
  final _aiController = TextEditingController();
  final _ribController = TextEditingController();

  String? _logoBase64;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      try {
        final profile = await SupabaseWorkshopSyncService()
            .readWorkshopProfile();
        if (profile.isNotEmpty) {
          _managerData = profile;
          _workshopNameController.text =
              profile['workshop_name']?.toString() ?? '';
          _locationController.text =
              profile['workshop_address']?.toString() ?? '';
          _phoneController.text = profile['phone']?.toString() ?? '';
          _specialtiesController.text =
              profile['workshop_specialties']?.toString() ?? '';
          _managerNameController.text =
              profile['manager_name']?.toString() ?? '';
          _workerCountController.text = (profile['worker_count'] ?? '')
              .toString();
          _logoBase64 = profile['logo']?.toString();
        }
      } catch (syncError) {
        debugPrint('Could not load workshop profile from Supabase: $syncError');
      }

      final prefs = await SharedPreferences.getInstance();
      final localRc = prefs.getString('workshop_rc') ?? '';
      final localNif = prefs.getString('workshop_nif') ?? '';
      final localNis = prefs.getString('workshop_nis') ?? '';
      final localAi = prefs.getString('workshop_ai') ?? '';
      final localRib = prefs.getString('workshop_rib') ?? '';
      final localAddress = prefs.getString('workshop_address') ?? '';

      if (_locationController.text.isEmpty) {
        _locationController.text = localAddress;
      }

      _rcController.text = _managerData?['rc']?.toString() ?? localRc;
      _nifController.text = _managerData?['nif']?.toString() ?? localNif;
      _nisController.text = _managerData?['nis']?.toString() ?? localNis;
      _aiController.text = _managerData?['ai']?.toString() ?? localAi;
      _ribController.text = _managerData?['rib']?.toString() ?? localRib;

      // Employees is the canonical local mirror of the Supabase workshop
      // members. This page used to query Firebase users, which made the team
      // appear empty after the workshop data moved to Supabase.
      final managerUid = (prefs.getString('workshop_code') ?? '').trim();
      final employees = await _db.readEmployees();
      _workers = employees.where((worker) {
        final uid = (worker['uid'] ?? '').toString().trim();
        final email = (worker['email'] ?? '').toString().trim().toLowerCase();
        return uid.isNotEmpty &&
            uid != user.uid &&
            (managerUid.isEmpty || uid != managerUid) &&
            email.isNotEmpty &&
            email != 'no email' &&
            email != 'no_email';
      }).toList();
    } catch (e) {
      debugPrint('Error loading workshop profile: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
    );
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      // Only allow images < 500KB to fit well within Firestore 1MB doc limit
      if (bytes.lengthInBytes > 500 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'حجم الصورة كبير جداً، يرجى اختيار صورة أصغر من 500 كيلوبايت',
              ),
            ),
          );
        }
        return;
      }
      final base64String = base64Encode(bytes);
      setState(() {
        _logoBase64 = base64String;
      });
    }
  }

  Future<void> _saveManagerData() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final newWorkshopName = _workshopNameController.text.trim();
    if (newWorkshopName.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('اسم الورشة لا يمكن أن يكون فارغاً'))),
        );
      }
      return;
    }

    try {
      // Save to local SharedPreferences immediately
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('workshop_name', newWorkshopName);
      await prefs.setString('phone', _phoneController.text.trim());
      await prefs.setString('workshop_rc', _rcController.text.trim());
      await prefs.setString('workshop_nif', _nifController.text.trim());
      await prefs.setString('workshop_nis', _nisController.text.trim());
      await prefs.setString('workshop_ai', _aiController.text.trim());
      await prefs.setString('workshop_rib', _ribController.text.trim());
      await prefs.setString(
        'workshop_address',
        _locationController.text.trim(),
      );
      if (_logoBase64 != null) {
        await prefs.setString('workshop_logo_base64', _logoBase64!);
      }

      // The manager is the source of truth for the workshop header. Publish
      // these values to Supabase so worker devices receive them through the
      // workshop sync path; they are no longer written to Firebase.
      try {
        await SupabaseWorkshopSyncService().saveWorkshopProfile({
          'workshop_name': newWorkshopName,
          'workshop_address': _locationController.text.trim(),
          'phone': _phoneController.text.trim(),
          'workshop_specialties': _specialtiesController.text.trim(),
          'manager_name': _managerNameController.text.trim(),
          'worker_count': int.tryParse(_workerCountController.text.trim()) ?? 0,
          'rc': _rcController.text.trim(),
          'nif': _nifController.text.trim(),
          'nis': _nisController.text.trim(),
          'ai': _aiController.text.trim(),
          'rib': _ribController.text.trim(),
          'logo': _logoBase64 ?? prefs.getString('workshop_logo_base64') ?? '',
        });
      } catch (syncError) {
        // A temporary Supabase/network failure must not undo the local save.
        debugPrint('Workshop profile Supabase sync deferred: $syncError');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_t('تم حفظ معلومات الورشة بنجاح')),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_t('خطأ في الحفظ:')} $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _workshopNameController.dispose();
    _locationController.dispose();
    _phoneController.dispose();
    _specialtiesController.dispose();
    _managerNameController.dispose();
    _workerCountController.dispose();
    _rcController.dispose();
    _nifController.dispose();
    _nisController.dispose();
    _aiController.dispose();
    _ribController.dispose();
    super.dispose();
  }

  Future<void> _editWorker(Map<String, dynamic> data) async {
    final uid = (data['uid'] ?? '').toString().trim();
    if (uid.isEmpty) return;
    final nameCtrl = TextEditingController(text: data['name'] ?? '');
    final jobTitleCtrl = TextEditingController(text: data['job_role'] ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('تعديل معلومات المستخدم')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(labelText: _t('اسم المستخدم')),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: jobTitleCtrl,
              decoration: InputDecoration(
                labelText: _t('المسمى الوظيفي'),
                hintText: _t('مثال: رئيس ورشة، عامل متقدم، مبتدئ...'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_t('إلغاء')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('حفظ')),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        await _db.updateEmployeeInfo(
          uid,
          name: nameCtrl.text.trim(),
          phone: (data['phone'] ?? '').toString(),
          address: (data['address'] ?? '').toString(),
          jobRole: jobTitleCtrl.text.trim(),
        );
        await _loadData();
      } catch (e) {
        debugPrint('Error updating worker: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('ملف ومعلومات الورشة')),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _isLoading ? null : _saveManagerData,
            tooltip: _t('حفظ المعلومات'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isLoading) const LinearProgressIndicator(),
            if (_isLoading) const SizedBox(height: 12),
            // Logo Section
            Center(
              child: GestureDetector(
                onTap: _pickImage,
                child: Builder(
                  builder: (context) {
                    ImageProvider? logoProvider;
                    if (_logoBase64 != null && _logoBase64!.isNotEmpty) {
                      if (_logoBase64!.startsWith('http')) {
                        logoProvider = NetworkImage(_logoBase64!);
                      } else {
                        try {
                          final bytes = base64Decode(_logoBase64!);
                          if (bytes.isNotEmpty) {
                            logoProvider = MemoryImage(bytes);
                          }
                        } catch (e) {
                          debugPrint('Error decoding profile logo base64: $e');
                        }
                      }
                    }

                    return CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.grey.shade300,
                      backgroundImage: logoProvider,
                      child: logoProvider == null
                          ? const Icon(
                              Icons.add_a_photo,
                              size: 40,
                              color: Colors.grey,
                            )
                          : null,
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Workshop Info
            Text(
              'معلومات الورشة',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.blue.shade300
                    : Colors.blue.shade800,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _workshopNameController,
              decoration: InputDecoration(
                labelText: _t('اسم الورشة'),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _locationController,
              decoration: InputDecoration(
                labelText: _t('موقع الورشة'),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: _t('رقم الهاتف'),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _specialtiesController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: _t('تخصصات الورشة'),
                border: OutlineInputBorder(),
                hintText: _t('مثال: ألمنيوم، زجاج، بي في سي...'),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'معلومات إضافية',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.blue.shade300
                    : Colors.blue.shade800,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _rcController,
              decoration: InputDecoration(
                labelText: _t('رقم السجل التجاري (RC)'),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nifController,
              decoration: InputDecoration(
                labelText: _t('رقم التعريف الجبائي (NIF)'),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nisController,
              decoration: InputDecoration(
                labelText: _t('رقم التعريف الإحصائي (NIS)'),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _aiController,
              decoration: InputDecoration(
                labelText: _t('رقم المادة (AI)'),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _ribController,
              decoration: InputDecoration(
                labelText: _t('الحساب البنكي (RIB)'),
                border: OutlineInputBorder(),
              ),
            ),
            // Manager Info
            Text(
              'معلومات المدير',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.blue.shade300
                    : Colors.blue.shade800,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _managerNameController,
              decoration: InputDecoration(
                labelText: _t('اسم مدير الورشة'),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _workerCountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: _t('عدد مستخدمي الورشة'),
                border: OutlineInputBorder(),
                hintText: _t('مثال: 5'),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _saveManagerData,
              icon: const Icon(Icons.save),
              label: Text(_t('حفظ التعديلات الرئيسية')),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 45),
              ),
            ),
            const Divider(height: 40, thickness: 2),

            // Workers Section
            Text(
              'فريق العمل',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.blue.shade300
                    : Colors.blue.shade800,
              ),
            ),
            const SizedBox(height: 10),
            if (_workers.isEmpty)
              const Text(
                'لا يوجد مستخدمون مسجلون في ورشتك بعد.',
                style: TextStyle(color: Colors.grey),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _workers.length,
                itemBuilder: (context, index) {
                  final wData = _workers[index];
                  final wName = wData['name'] ?? 'بدون اسم';
                  final wJobTitle = wData['job_role'] ?? 'عامل (غير مصنف)';

                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(
                        wName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        wJobTitle,
                        style: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white70
                              : Colors.blueGrey,
                        ),
                      ),
                      trailing: IconButton(
                        icon: Icon(
                          Icons.edit,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.blue.shade300
                              : Colors.blue,
                        ),
                        onPressed: () => _editWorker(_workers[index]),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
