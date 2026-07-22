import re

path_profile = r'c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\Screen\workshop_profile_screen.dart'

with open(path_profile, 'r', encoding='utf-8') as f:
    code = f.read()

# 1. Insert controllers
OLD_CONTROLLERS = """  final _managerNameController = TextEditingController();
  final _workerCountController = TextEditingController();"""

NEW_CONTROLLERS = """  final _managerNameController = TextEditingController();
  final _workerCountController = TextEditingController();
  final _rcController = TextEditingController();
  final _nifController = TextEditingController();
  final _nisController = TextEditingController();
  final _aiController = TextEditingController();
  final _ribController = TextEditingController();"""

assert OLD_CONTROLLERS in code, "Controllers not found in workshop_profile_screen.dart"
code = code.replace(OLD_CONTROLLERS, NEW_CONTROLLERS, 1)

# 2. Insert load data logic
OLD_LOAD = """        _logoBase64 = _managerData?['workshopLogoUrl'];
      }"""

NEW_LOAD = """        _logoBase64 = _managerData?['workshopLogoUrl'];
      }

      final prefs = await SharedPreferences.getInstance();
      final localRc = prefs.getString('workshop_rc') ?? '';
      final localNif = prefs.getString('workshop_nif') ?? '';
      final localNis = prefs.getString('workshop_nis') ?? '';
      final localAi = prefs.getString('workshop_ai') ?? '';
      final localRib = prefs.getString('workshop_rib') ?? '';

      _rcController.text = _managerData?['rc'] ?? localRc;
      _nifController.text = _managerData?['nif'] ?? localNif;
      _nisController.text = _managerData?['nis'] ?? localNis;
      _aiController.text = _managerData?['ai'] ?? localAi;
      _ribController.text = _managerData?['rib'] ?? localRib;"""

assert OLD_LOAD in code, "Load data block not found in workshop_profile_screen.dart"
code = code.replace(OLD_LOAD, NEW_LOAD, 1)

# 3. Insert save manager data
OLD_SAVE_MAP = """      await _firestore.collection('users').doc(user.uid).update({
        'workshopName': newWorkshopName,
        'workshopLocation': _locationController.text.trim(),
        'workshopSpecialties': _specialtiesController.text.trim(),
        'phone': _phoneController.text.trim(),
        'name': _managerNameController.text.trim(),
        'workerCount': int.tryParse(_workerCountController.text.trim()) ?? 0,
        if (_logoBase64 != null) 'workshopLogoUrl': _logoBase64,
      });"""

NEW_SAVE_MAP = """      await _firestore.collection('users').doc(user.uid).update({
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
      });"""

assert OLD_SAVE_MAP in code, "Save map not found in workshop_profile_screen.dart"
code = code.replace(OLD_SAVE_MAP, NEW_SAVE_MAP, 1)

OLD_SAVE_PREFS = """      // Save to local SharedPreferences immediately
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('workshop_name', newWorkshopName);
      await prefs.setString('phone', _phoneController.text.trim());"""

NEW_SAVE_PREFS = """      // Save to local SharedPreferences immediately
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('workshop_name', newWorkshopName);
      await prefs.setString('phone', _phoneController.text.trim());
      await prefs.setString('workshop_rc', _rcController.text.trim());
      await prefs.setString('workshop_nif', _nifController.text.trim());
      await prefs.setString('workshop_nis', _nisController.text.trim());
      await prefs.setString('workshop_ai', _aiController.text.trim());
      await prefs.setString('workshop_rib', _ribController.text.trim());"""

assert OLD_SAVE_PREFS in code, "Save prefs not found in workshop_profile_screen.dart"
code = code.replace(OLD_SAVE_PREFS, NEW_SAVE_PREFS, 1)

# 4. Insert UI Fields
OLD_UI_FIELDS = """            TextField(
              controller: _specialtiesController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'تخصصات الورشة',
                border: OutlineInputBorder(),
                hintText: 'مثال: ألمنيوم، زجاج، بي في سي...',
              ),
            ),"""

NEW_UI_FIELDS = """            TextField(
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
            ),"""

assert OLD_UI_FIELDS in code, "UI fields not found in workshop_profile_screen.dart"
code = code.replace(OLD_UI_FIELDS, NEW_UI_FIELDS, 1)

with open(path_profile, 'w', encoding='utf-8') as f:
    f.write(code)
print("workshop_profile_screen.dart updated successfully.")
