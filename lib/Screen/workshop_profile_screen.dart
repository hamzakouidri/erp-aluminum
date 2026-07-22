import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WorkshopProfileScreen extends StatefulWidget {
  const WorkshopProfileScreen({super.key});

  @override
  State<WorkshopProfileScreen> createState() => _WorkshopProfileScreenState();
}

class _WorkshopProfileScreenState extends State<WorkshopProfileScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  bool _isLoading = true;
  Map<String, dynamic>? _managerData;
  List<QueryDocumentSnapshot> _workers = [];

  final _workshopNameController = TextEditingController();
  final _locationController = TextEditingController();
  final _phoneController = TextEditingController();
  final _specialtiesController = TextEditingController();
  final _managerNameController = TextEditingController();
  final _workerCountController = TextEditingController();
  final _rcController = TextEditingController();
  final _nifController = TextEditingController();
  final _nisController = TextEditingController();
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

      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        _managerData = doc.data() as Map<String, dynamic>;
        _workshopNameController.text = _managerData?['workshopName'] ?? '';
        _locationController.text = _managerData?['workshopLocation'] ?? '';
        _phoneController.text = _managerData?['phone'] ?? _managerData?['phoneNumber'] ?? '';
        _specialtiesController.text =
            _managerData?['workshopSpecialties'] ?? '';
        _managerNameController.text = _managerData?['name'] ?? '';
        _workerCountController.text = (_managerData?['workerCount'] ?? '')
            .toString();
        _logoBase64 = _managerData?['workshopLogoUrl'];
      }

      final prefs = await SharedPreferences.getInstance();
      final localRc = prefs.getString('workshop_rc') ?? '';
      final localNif = prefs.getString('workshop_nif') ?? '';
      final localNis = prefs.getString('workshop_nis') ?? '';
      final localAi = prefs.getString('workshop_ai') ?? '';
      final localRib = prefs.getString('workshop_rib') ?? '';
      final localAddress = prefs.getString('workshop_address') ?? '';

      if (_locationController.text.isEmpty) {
        _locationController.text = _managerData?['workshopLocation'] ?? localAddress;
      }

      _rcController.text = _managerData?['rc'] ?? localRc;
      _nifController.text = _managerData?['nif'] ?? localNif;
      _nisController.text = _managerData?['nis'] ?? localNis;
      _aiController.text = _managerData?['ai'] ?? localAi;
      _ribController.text = _managerData?['rib'] ?? localRib;

      final workersSnapshot = await _firestore
          .collection('users')
          .where('workshopId', isEqualTo: user.uid)
          .where('role', isEqualTo: 'worker')
          .get();

      _workers = workersSnapshot.docs;
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
          const SnackBar(content: Text('اسم الورشة لا يمكن أن يكون فارغاً')),
        );
      }
      return;
    }

    try {
      // Check for uniqueness
      final nameCheck = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'manager')
          .where('workshopName', isEqualTo: newWorkshopName)
          .get();

      for (var doc in nameCheck.docs) {
        if (doc.id != user.uid) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'اسم الورشة محجوز وموجود مسبقاً! يرجى اختيار اسم آخر.',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      await _firestore.collection('users').doc(user.uid).update({
        'workshopName': newWorkshopName,
        'workshopLocation': _locationController.text.trim(),
        'workshopSpecialties': _specialtiesController.text.trim(),
        'phone': _phoneController.text.trim(),
        'name': _managerNameController.text.trim(),
        'workerCount': int.tryParse(_workerCountController.text.trim()) ?? 0,
        'rc': _rcController.text.trim(),
        'nif': _nifController.text.trim(),
        'nis': _nisController.text.trim(),
        'ai': _aiController.text.trim(),
        'rib': _ribController.text.trim(),
        if (_logoBase64 != null) 'workshopLogoUrl': _logoBase64,
      });

      // Save to local SharedPreferences immediately
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('workshop_name', newWorkshopName);
      await prefs.setString('phone', _phoneController.text.trim());
      await prefs.setString('workshop_rc', _rcController.text.trim());
      await prefs.setString('workshop_nif', _nifController.text.trim());
      await prefs.setString('workshop_nis', _nisController.text.trim());
      await prefs.setString('workshop_ai', _aiController.text.trim());
      await prefs.setString('workshop_rib', _ribController.text.trim());
      await prefs.setString('workshop_address', _locationController.text.trim());
      if (_logoBase64 != null) {
        await prefs.setString('workshop_logo_base64', _logoBase64!);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ معلومات الورشة بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في الحفظ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _editWorker(QueryDocumentSnapshot workerDoc) async {
    final data = workerDoc.data() as Map<String, dynamic>;
    final nameCtrl = TextEditingController(text: data['name'] ?? '');
    final jobTitleCtrl = TextEditingController(text: data['jobTitle'] ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تعديل معلومات العامل'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'اسم العامل'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: jobTitleCtrl,
              decoration: const InputDecoration(
                labelText: 'المسمى الوظيفي',
                hintText: 'مثال: رئيس ورشة، عامل متقدم، مبتدئ...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        await _firestore.collection('users').doc(workerDoc.id).update({
          'name': nameCtrl.text.trim(),
          'jobTitle': jobTitleCtrl.text.trim(),
        });
        _loadData();
      } catch (e) {
        debugPrint('Error updating worker: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('ملف ومعلومات الورشة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveManagerData,
            tooltip: 'حفظ المعلومات',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Logo Section
            Center(
              child: GestureDetector(
                onTap: _pickImage,
                child: CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.grey.shade300,
                  backgroundImage:
                      _logoBase64 != null && _logoBase64!.isNotEmpty
                      ? MemoryImage(base64Decode(_logoBase64!))
                      : null,
                  child: _logoBase64 == null || _logoBase64!.isEmpty
                      ? const Icon(
                          Icons.add_a_photo,
                          size: 40,
                          color: Colors.grey,
                        )
                      : null,
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
              decoration: const InputDecoration(
                labelText: 'اسم الورشة',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: 'موقع الورشة',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'رقم الهاتف',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _specialtiesController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'تخصصات الورشة',
                border: OutlineInputBorder(),
                hintText: 'مثال: ألمنيوم، زجاج، بي في سي...',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _rcController,
              decoration: const InputDecoration(
                labelText: 'رقم السجل التجاري (RC)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nifController,
              decoration: const InputDecoration(
                labelText: 'رقم التعريف الجبائي (NIF)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nisController,
              decoration: const InputDecoration(
                labelText: 'رقم التعريف الإحصائي (NIS)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _aiController,
              decoration: const InputDecoration(
                labelText: 'رقم المادة (AI)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _ribController,
              decoration: const InputDecoration(
                labelText: 'الحساب البنكي (RIB)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),

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
              decoration: const InputDecoration(
                labelText: 'اسم مدير الورشة',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _workerCountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'عدد عمال الورشة',
                border: OutlineInputBorder(),
                hintText: 'مثال: 5',
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _saveManagerData,
              icon: const Icon(Icons.save),
              label: const Text('حفظ التعديلات الرئيسية'),
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
                'لا يوجد عمال مسجلين في ورشتك بعد.',
                style: TextStyle(color: Colors.grey),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _workers.length,
                itemBuilder: (context, index) {
                  final wData = _workers[index].data() as Map<String, dynamic>;
                  final wName = wData['name'] ?? 'بدون اسم';
                  final wJobTitle = wData['jobTitle'] ?? 'عامل (غير مصنف)';

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
