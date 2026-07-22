import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:archive/archive_io.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';

import '../sql_database.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';

class MeasurementsScreen extends StatefulWidget {
  final SqlDatabase db;
  const MeasurementsScreen({super.key, required this.db});

  @override
  State<MeasurementsScreen> createState() => _MeasurementsScreenState();
}

class _MeasurementsScreenState extends State<MeasurementsScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _lengthController = TextEditingController();
  final _widthController = TextEditingController();
  final _locationController = TextEditingController(text: 'المطبخ');
  final _noteController = TextEditingController();

  // Focus Nodes
  final _lengthFocus = FocusNode();
  final _widthFocus = FocusNode();
  final _noteFocus = FocusNode();

  // Form State Values
  List<Map<String, dynamic>> _allColors = [];
  Map<String, dynamic>? _selectedColor;

  String _openingSystem = 'French'; // French (Ouvrant / Batteur) or Sliding (Coulissant)
  bool _shutterExists = false;
  String _shutterSide = 'Inside'; // Inside or Outside
  String _shutterType = 'Aluminium'; // Aluminium or PVC
  bool _shutterMotorManeuver = false;
  String _glassType = 'Double'; // Simple or Double
  bool _bottomFrameExists = true;

  // Attached files
  File? _imageFile;
  File? _videoFile;
  String? _recordedAudioPath;

  // Voice recording state
  final _audioRecorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  bool _isPlaying = false;

  // Measurements list
  List<Map<String, dynamic>> _savedMeasurements = [];

  @override
  void initState() {
    super.initState();
    _loadAllColors();
    _loadSavedMeasurements();
  }

  @override
  void dispose() {
    _lengthController.dispose();
    _widthController.dispose();
    _locationController.dispose();
    _noteController.dispose();
    _lengthFocus.dispose();
    _widthFocus.dispose();
    _noteFocus.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // ── Database Loaders ──────────────────────────────────────────────────
  Future<void> _loadAllColors() async {
    try {
      final dbClient = await widget.db.db;
      if (dbClient != null) {
        final colorsData = await dbClient.query('Colors');
        setState(() {
          _allColors = colorsData;
          if (_allColors.isNotEmpty) {
            _selectedColor = _allColors.first;
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading colors: $e');
    }
  }

  Future<void> _loadSavedMeasurements() async {
    try {
      final data = await widget.db.readMeasurements();
      setState(() {
        _savedMeasurements = data;
      });
    } catch (e) {
      debugPrint('Error loading measurements: $e');
    }
  }

  // ── Media handling ────────────────────────────────────────────────────
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera);
    if (picked != null) {
      final appDir = await getApplicationDocumentsDirectory();
      final targetFolder = Directory(p.join(appDir.path, 'measurements_media'));
      if (!await targetFolder.exists()) {
        await targetFolder.create(recursive: true);
      }
      final filename = 'img_${DateTime.now().millisecondsSinceEpoch}${p.extension(picked.path)}';
      final savedFile = await File(picked.path).copy(p.join(targetFolder.path, filename));
      setState(() {
        _imageFile = savedFile;
      });
    }
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.camera);
    if (picked != null) {
      final appDir = await getApplicationDocumentsDirectory();
      final targetFolder = Directory(p.join(appDir.path, 'measurements_media'));
      if (!await targetFolder.exists()) {
        await targetFolder.create(recursive: true);
      }
      final filename = 'vid_${DateTime.now().millisecondsSinceEpoch}${p.extension(picked.path)}';
      final savedFile = await File(picked.path).copy(p.join(targetFolder.path, filename));
      setState(() {
        _videoFile = savedFile;
      });
    }
  }

  // ── Voice recording ───────────────────────────────────────────────────
  Future<void> _toggleAudioRecording() async {
    try {
      if (_isRecording) {
        final path = await _audioRecorder.stop();
        setState(() {
          _isRecording = false;
          _recordedAudioPath = path;
        });
        if (mounted) {
          final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(Localization.translate('تم حفظ التسجيل الصوتي بنجاح', lang))),
          );
        }
      } else {
        final appDir = await getApplicationDocumentsDirectory();
        final targetFolder = Directory(p.join(appDir.path, 'measurements_media'));
        if (!await targetFolder.exists()) {
          await targetFolder.create(recursive: true);
        }
        final path = p.join(targetFolder.path, 'rec_${DateTime.now().millisecondsSinceEpoch}.m4a');
        await _audioRecorder.start(const RecordConfig(), path: path);
        setState(() {
          _isRecording = true;
          _recordedAudioPath = null;
        });
      }
    } catch (e) {
      debugPrint('Audio recording error: $e');
    }
  }

  Future<void> _playRecordedAudio() async {
    if (_recordedAudioPath == null) return;
    try {
      if (_isPlaying) {
        await _audioPlayer.stop();
        setState(() {
          _isPlaying = false;
        });
      } else {
        await _audioPlayer.play(DeviceFileSource(_recordedAudioPath!));
        setState(() {
          _isPlaying = true;
        });
        _audioPlayer.onPlayerComplete.listen((_) {
          if (mounted) {
            setState(() {
              _isPlaying = false;
            });
          }
        });
      }
    } catch (e) {
      debugPrint('Audio playback error: $e');
    }
  }

  // ── Operations ────────────────────────────────────────────────────────
  Future<void> _saveMeasurement() async {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    if (!_formKey.currentState!.validate()) return;

    final data = {
      'length': double.tryParse(_lengthController.text) ?? 0.0,
      'width': double.tryParse(_widthController.text) ?? 0.0,
      'frame_type': _selectedColor != null ? _selectedColor!['name'].toString() : '',
      'opening_system': _openingSystem,
      'shutter_exists': _shutterExists ? 1 : 0,
      'shutter_side': _shutterSide,
      'shutter_type': _shutterType,
      'shutter_motor_maneuver': _shutterMotorManeuver ? 1 : 0,
      'glass_type': _glassType,
      'glass_decoration': 0,
      'handle_height': 0.0,
      'reinforced_lateral': 0,
      'reinforced_center': 0,
      'bottom_frame_exists': _bottomFrameExists ? 1 : 0,
      'window_location': _locationController.text.trim().isEmpty ? 'المطبخ' : _locationController.text.trim(),
      'media_path': _imageFile?.path ?? '',
      'audio_path': _recordedAudioPath ?? '',
      'video_path': _videoFile?.path ?? '',
      'note': _noteController.text.trim(),
    };

    try {
      await widget.db.insertMeasurement(data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Localization.translate('تم حفظ ورقة القياسات بنجاح', lang))),
        );
      }
      _clearForm();
      _loadSavedMeasurements();
    } catch (e) {
      debugPrint('Error saving measurement: $e');
    }
  }

  void _clearForm() {
    _lengthController.clear();
    _widthController.clear();
    _locationController.text = 'المطبخ';
    _noteController.clear();
    setState(() {
      _imageFile = null;
      _videoFile = null;
      _recordedAudioPath = null;
      _shutterExists = false;
      _shutterMotorManeuver = false;
      _bottomFrameExists = true;
    });
  }

  // ── ZIP Export / Import ───────────────────────────────────────────────
  Future<void> _exportToZip(Map<String, dynamic> item) async {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    try {
      final archive = Archive();

      final jsonBytes = utf8.encode(jsonEncode(item));
      archive.addFile(ArchiveFile('metadata.json', jsonBytes.length, jsonBytes));

      final imgPath = item['media_path']?.toString() ?? '';
      if (imgPath.isNotEmpty && File(imgPath).existsSync()) {
        final bytes = await File(imgPath).readAsBytes();
        archive.addFile(ArchiveFile('image${p.extension(imgPath)}', bytes.length, bytes));
      }

      final vidPath = item['video_path']?.toString() ?? '';
      if (vidPath.isNotEmpty && File(vidPath).existsSync()) {
        final bytes = await File(vidPath).readAsBytes();
        archive.addFile(ArchiveFile('video${p.extension(vidPath)}', bytes.length, bytes));
      }

      final audPath = item['audio_path']?.toString() ?? '';
      if (audPath.isNotEmpty && File(audPath).existsSync()) {
        final bytes = await File(audPath).readAsBytes();
        archive.addFile(ArchiveFile('audio${p.extension(audPath)}', bytes.length, bytes));
      }

      final zipEncoder = ZipEncoder();
      final zipData = zipEncoder.encode(archive);
      if (zipData == null) return;

      final tempDir = await getTemporaryDirectory();
      final cleanLocation = (item['window_location'] ?? 'قياس').toString().replaceAll(' ', '_');
      final zipFile = File(p.join(tempDir.path, '${cleanLocation}_${item['length']}x${item['width']}.zip'));
      await zipFile.writeAsBytes(zipData);

      await Share.shareXFiles([XFile(zipFile.path)], text: Localization.translate('مشاركة ملف القياسات المضغوط', lang));
    } catch (e) {
      debugPrint('Export ZIP error: $e');
    }
  }

  Future<void> _importFromZip() async {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (result == null || result.files.single.path == null) return;

      final zipFile = File(result.files.single.path!);
      final bytes = await zipFile.readAsBytes();

      final archive = ZipDecoder().decodeBytes(bytes);
      final metadataFile = archive.findFile('metadata.json');
      if (metadataFile == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(Localization.translate('خطأ: لم يتم العثور على ملف البيانات الأساسي داخل الـ ZIP', lang))),
          );
        }
        return;
      }

      final metadataJson = utf8.decode(metadataFile.content as List<int>);
      final Map<String, dynamic> item = jsonDecode(metadataJson);

      final appDir = await getApplicationDocumentsDirectory();
      final targetFolder = Directory(p.join(appDir.path, 'measurements_media'));
      if (!await targetFolder.exists()) {
        await targetFolder.create(recursive: true);
      }

      String localImgPath = '';
      String localVidPath = '';
      String localAudPath = '';

      for (final file in archive.files) {
        if (file.name.startsWith('image')) {
          final target = File(p.join(targetFolder.path, 'img_imported_${DateTime.now().millisecondsSinceEpoch}${p.extension(file.name)}'));
          await target.writeAsBytes(file.content as List<int>);
          localImgPath = target.path;
        } else if (file.name.startsWith('video')) {
          final target = File(p.join(targetFolder.path, 'vid_imported_${DateTime.now().millisecondsSinceEpoch}${p.extension(file.name)}'));
          await target.writeAsBytes(file.content as List<int>);
          localVidPath = target.path;
        } else if (file.name.startsWith('audio')) {
          final target = File(p.join(targetFolder.path, 'rec_imported_${DateTime.now().millisecondsSinceEpoch}${p.extension(file.name)}'));
          await target.writeAsBytes(file.content as List<int>);
          localAudPath = target.path;
        }
      }

      final restoredItem = {
        'length': item['length'],
        'width': item['width'],
        'frame_type': item['frame_type'] ?? '',
        'opening_system': item['opening_system'] ?? '',
        'shutter_exists': item['shutter_exists'] ?? 0,
        'shutter_side': item['shutter_side'] ?? '',
        'shutter_type': item['shutter_type'] ?? '',
        'shutter_motor_maneuver': item['shutter_motor_maneuver'] ?? 0,
        'glass_type': item['glass_type'] ?? '',
        'glass_decoration': 0,
        'handle_height': 0.0,
        'reinforced_lateral': 0,
        'reinforced_center': 0,
        'bottom_frame_exists': item['bottom_frame_exists'] ?? 1,
        'window_location': item['window_location'] ?? '',
        'media_path': localImgPath,
        'audio_path': localAudPath,
        'video_path': localVidPath,
        'note': item['note'] ?? '',
      };

      await widget.db.insertMeasurement(restoredItem);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Localization.translate('تم استيراد واسترجاع ورقة القياس بجميع مرفقاتها بنجاح!', lang))),
        );
      }
      _loadSavedMeasurements();
    } catch (e) {
      debugPrint('Import ZIP error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${Localization.translate('خطأ أثناء استيراد الـ ZIP', lang)}: $e')),
        );
      }
    }
  }

  // ── UI Helpers ────────────────────────────────────────────────────────
  Widget _buildToggleChip(String label, bool isSelected, VoidCallback onTap, {bool isNegative = false}) {
    Color selectedColor = isNegative ? Colors.red : Colors.blue;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? selectedColor.withOpacity(0.12) : Theme.of(context).cardColor,
          border: Border.all(
            color: isSelected ? selectedColor : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected)
              Icon(
                isNegative ? Icons.close_rounded : Icons.check_circle_outline,
                size: 18,
                color: selectedColor,
              ),
            if (isSelected) const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? selectedColor : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionRow({
    required String title,
    required String yesLabel,
    required String noLabel,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildToggleChip(yesLabel, value == true, () => onChanged(true)),
            const SizedBox(width: 10),
            _buildToggleChip(noLabel, value == false, () => onChanged(false), isNegative: true),
          ],
        ),
        const Divider(height: 24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final locationOptions = [
      Localization.translate('المطبخ', lang),
      Localization.translate('الصالون', lang),
      Localization.translate('غرفة النوم', lang),
      Localization.translate('الحمام', lang),
      Localization.translate('المرحاض', lang),
      Localization.translate('الشرفة', lang),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          Localization.translate('ورقة رفع القياسات الذكية', lang),
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blue,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.unarchive_outlined),
            tooltip: Localization.translate('استيراد قياس ZIP', lang),
            onPressed: _importFromZip,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Form(
                key: _formKey,
                child: Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // الطول والعرض
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _lengthController,
                                focusNode: _lengthFocus,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  labelText: Localization.translate('الطول (مم)', lang),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                validator: (val) => val == null || val.isEmpty ? Localization.translate('مطلوب', lang) : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _widthController,
                                focusNode: _widthFocus,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  labelText: Localization.translate('العرض (مم)', lang),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                validator: (val) => val == null || val.isEmpty ? Localization.translate('مطلوب', lang) : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // موقع النافذة (أزرار الاختيار فقط)
                        Text(
                          Localization.translate('موقع النافذة', lang),
                          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: locationOptions.map((loc) {
                            final isSel = _locationController.text == loc;
                            return ChoiceChip(
                              label: Text(loc, style: const TextStyle(fontFamily: 'Cairo')),
                              selected: isSel,
                              selectedColor: Colors.blue.withOpacity(0.2),
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() {
                                    _locationController.text = loc;
                                  });
                                }
                              },
                            );
                          }).toList(),
                        ),
                        const Divider(height: 32),

                        // الألوان المتوفرة للبروفيلات (جميع الألوان متوفرة)
                        Text(
                          Localization.translate('لون البروفيل', lang),
                          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        _allColors.isEmpty
                            ? Text(Localization.translate('جاري تحميل الألوان...', lang))
                            : Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _allColors.map((col) {
                                  final isSel = _selectedColor?['id'] == col['id'];
                                  return ChoiceChip(
                                    label: Text(col['name'].toString(), style: const TextStyle(fontFamily: 'Cairo')),
                                    selected: isSel,
                                    selectedColor: Colors.blue.withOpacity(0.2),
                                    onSelected: (selected) {
                                      if (selected) {
                                        setState(() {
                                          _selectedColor = col;
                                        });
                                      }
                                    },
                                  );
                                }).toList(),
                              ),
                        const Divider(height: 32),

                        // نظام الفتح (فتح فرنسي أو منزلق)
                        Text(
                          Localization.translate('نظام الفتح', lang),
                          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _buildToggleChip(
                              Localization.translate('منزلق / Coulissant', lang),
                              _openingSystem == 'Sliding',
                              () => setState(() => _openingSystem = 'Sliding'),
                            ),
                            const SizedBox(width: 10),
                            _buildToggleChip(
                              Localization.translate('فتح فرنسي / Batteur (Français)', lang),
                              _openingSystem == 'French',
                              () => setState(() => _openingSystem = 'French'),
                            ),
                          ],
                        ),
                        const Divider(height: 32),

                        // خيارات الستار والزجاج
                        _buildSelectionRow(
                          title: Localization.translate('هل يوجد ستار؟ (Shutter)', lang),
                          yesLabel: Localization.translate('نعم يوجد', lang),
                          noLabel: Localization.translate('لا يوجد', lang),
                          value: _shutterExists,
                          onChanged: (val) => setState(() => _shutterExists = val),
                        ),

                        if (_shutterExists) ...[
                          _buildSelectionRow(
                            title: Localization.translate('جهة الستار', lang),
                            yesLabel: Localization.translate('داخل / Inside', lang),
                            noLabel: Localization.translate('خارج / Outside', lang),
                            value: _shutterSide == 'Inside',
                            onChanged: (val) => setState(() => _shutterSide = val ? 'Inside' : 'Outside'),
                          ),
                          _buildSelectionRow(
                            title: Localization.translate('نوع شفرة الستار', lang),
                            yesLabel: Localization.translate('ألمنيوم / Aluminium', lang),
                            noLabel: Localization.translate('بي في سي / PVC', lang),
                            value: _shutterType == 'Aluminium',
                            onChanged: (val) => setState(() => _shutterType = val ? 'Aluminium' : 'PVC'),
                          ),
                          _buildSelectionRow(
                            title: Localization.translate('هل المحرك بمناورة أمان (Maneuver Security)؟', lang),
                            yesLabel: Localization.translate('نعم / Yes', lang),
                            noLabel: Localization.translate('لا / No', lang),
                            value: _shutterMotorManeuver,
                            onChanged: (val) => setState(() => _shutterMotorManeuver = val),
                          ),
                        ],

                        _buildSelectionRow(
                          title: Localization.translate('نوع الزجاج', lang),
                          yesLabel: Localization.translate('مزدوج / Double', lang),
                          noLabel: Localization.translate('بسيط / Simple', lang),
                          value: _glassType == 'Double',
                          onChanged: (val) => setState(() => _glassType = val ? 'Double' : 'Simple'),
                        ),

                        _buildSelectionRow(
                          title: Localization.translate('هل الإطار السفلي موجود؟', lang),
                          yesLabel: Localization.translate('موجود', lang),
                          noLabel: Localization.translate('ملغي', lang),
                          value: _bottomFrameExists,
                          onChanged: (val) => setState(() => _bottomFrameExists = val),
                        ),

                        // الملاحظات
                        TextFormField(
                          controller: _noteController,
                          focusNode: _noteFocus,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: Localization.translate('ملاحظات إضافية', lang),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ── قسم الميديا وتسجيل الصوت (مصحح لتفادي الـ overflow) ──
                        Row(
                          children: [
                            const Icon(Icons.attach_file, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text(
                              Localization.translate('المرفقات والوسائط التوضيحية', lang),
                              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: isDark ? Colors.blue.shade300 : Colors.blue.shade800),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.start,
                          children: [
                            ElevatedButton.icon(
                              icon: const Icon(Icons.camera_alt),
                              label: Text(Localization.translate('صورة', lang), style: const TextStyle(fontFamily: 'Cairo')),
                              onPressed: _pickImage,
                            ),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.videocam),
                              label: Text(Localization.translate('فيديو', lang), style: const TextStyle(fontFamily: 'Cairo')),
                              onPressed: _pickVideo,
                            ),
                            ElevatedButton.icon(
                              icon: Icon(_isRecording ? Icons.stop : Icons.mic, color: _isRecording ? Colors.red : Colors.white),
                              label: Text(_isRecording ? Localization.translate('إيقاف', lang) : Localization.translate('تسجيل صوت', lang), style: const TextStyle(fontFamily: 'Cairo')),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isRecording ? Colors.red.shade100 : null,
                              ),
                              onPressed: _toggleAudioRecording,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // معاينة الميديا المرفقة
                        if (_imageFile != null || _videoFile != null || _recordedAudioPath != null) ...[
                          Text(Localization.translate('المرفقات المحملة حالياً:', lang), style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              if (_imageFile != null)
                                Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.file(_imageFile!, width: 70, height: 70, fit: BoxFit.cover),
                                    ),
                                    Positioned(
                                      right: 0,
                                      child: GestureDetector(
                                        onTap: () => setState(() => _imageFile = null),
                                        child: const CircleAvatar(radius: 10, backgroundColor: Colors.red, child: Icon(Icons.close, size: 12, color: Colors.white)),
                                      ),
                                    ),
                                  ],
                                ),
                              if (_videoFile != null)
                                Stack(
                                  children: [
                                    Container(
                                      width: 70,
                                      height: 70,
                                      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
                                      child: const Icon(Icons.play_circle_fill, color: Colors.white, size: 30),
                                    ),
                                    Positioned(
                                      right: 0,
                                      child: GestureDetector(
                                        onTap: () => setState(() => _videoFile = null),
                                        child: const CircleAvatar(radius: 10, backgroundColor: Colors.red, child: Icon(Icons.close, size: 12, color: Colors.white)),
                                      ),
                                    ),
                                  ],
                                ),
                              if (_recordedAudioPath != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green)),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow, color: Colors.green),
                                        onPressed: _playRecordedAudio,
                                      ),
                                      Text(Localization.translate('تسجيل صوتي', lang), style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: () => setState(() => _recordedAudioPath = null),
                                        child: const Icon(Icons.close, size: 16, color: Colors.red),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],

                        // زر الحفظ
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _saveMeasurement,
                            child: Text(
                              Localization.translate('حفظ القياس في الهاتف', lang),
                              style: const TextStyle(fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ── قائمة القياسات السابقة ──────────────────────────────
              Row(
                children: [
                  const Icon(Icons.history),
                  const SizedBox(width: 8),
                  Text(
                    '${Localization.translate('القياسات المسجلة سابقاً', lang)} (${_savedMeasurements.length})',
                    style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              _savedMeasurements.isEmpty
                  ? Text(Localization.translate('لا توجد قياسات مسجلة بعد.', lang))
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _savedMeasurements.length,
                      itemBuilder: (ctx, idx) {
                        final item = _savedMeasurements[idx];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            title: Text(
                              '${item['window_location']} - ${item['length']} × ${item['width']} ${Localization.translate('مم', lang)}',
                              style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              '${Localization.translate('نظام', lang)}: ${item['opening_system']} | ${Localization.translate('ستار', lang)}: ${item['shutter_exists'] == 1 ? Localization.translate('نعم', lang) : Localization.translate('لا', lang)}\n${Localization.translate('ملاحظة', lang)}: ${item['note'] ?? ''}',
                              style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.share, color: Colors.blue),
                                  tooltip: Localization.translate('مشاركة ورفع كـ ZIP', lang),
                                  onPressed: () => _exportToZip(item),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () async {
                                    await widget.db.deleteMeasurement(item['id'] as int);
                                    _loadSavedMeasurements();
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
