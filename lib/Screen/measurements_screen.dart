import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
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
  final _handleHeightController = TextEditingController();
  final _locationController = TextEditingController();
  final _noteController = TextEditingController();
  final _smartVoiceController = TextEditingController();

  // Focus Nodes for Voice navigation
  final _lengthFocus = FocusNode();
  final _widthFocus = FocusNode();
  final _handleHeightFocus = FocusNode();
  final _locationFocus = FocusNode();
  final _noteFocus = FocusNode();

  // Form State Values
  List<Map<String, dynamic>> _seriesList = [];
  Map<String, dynamic>? _selectedSeries;
  List<Map<String, dynamic>> _filteredColors = [];
  Map<String, dynamic>? _selectedColor;

  String _openingSystem = 'French'; // French (ouvrant) or Sliding (coulisse)
  bool _shutterExists = false;
  String _shutterSide = 'Inside'; // Inside or Outside
  String _shutterType = 'Aluminium'; // Aluminium or PVC
  bool _shutterMotorManeuver = false;
  String _glassType = 'Double'; // Simple, Double, StopSol, etc.
  bool _glassDecoration = false;
  bool _reinforcedLateral = false;
  bool _reinforcedCenter = false;
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

  // Speech to Text state
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _spokenText = '';
  String _voiceStatusText = 'اضغط على الميكروفون لبدء الإملاء الصوتي';

  // Measurements list
  List<Map<String, dynamic>> _savedMeasurements = [];

  @override
  void initState() {
    super.initState();
    _loadSeriesAndColors();
    _loadSavedMeasurements();
    _initSpeech();
  }

  @override
  void dispose() {
    _lengthController.dispose();
    _widthController.dispose();
    _handleHeightController.dispose();
    _locationController.dispose();
    _noteController.dispose();
    _smartVoiceController.dispose();
    _lengthFocus.dispose();
    _widthFocus.dispose();
    _handleHeightFocus.dispose();
    _locationFocus.dispose();
    _noteFocus.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // ── Database Loaders ──────────────────────────────────────────────────
  Future<void> _loadSeriesAndColors() async {
    try {
      final dbClient = await widget.db.db;
      if (dbClient != null) {
        final seriesData = await dbClient.query('Series', where: 'is_active = 1');
        setState(() {
          _seriesList = seriesData;
          if (_seriesList.isNotEmpty) {
            _selectedSeries = _seriesList.first;
            _updateColorsForSelectedSeries();
            final String type = _selectedSeries?['type']?.toString() ?? '';
            if (type == 'Coulissant' || type.toLowerCase().contains('sliding')) {
              _openingSystem = 'Sliding';
            } else if (type == 'Frappe' || type.toLowerCase().contains('french') || type.toLowerCase().contains('frappe')) {
              _openingSystem = 'French';
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading series: $e');
    }
  }

  Future<void> _updateColorsForSelectedSeries() async {
    if (_selectedSeries == null) return;
    try {
      final dbClient = await widget.db.db;
      if (dbClient != null) {
        // Query colors associated with this series
        final results = await dbClient.rawQuery('''
          SELECT c.* FROM Colors c
          JOIN SeriesColorPrices scp ON c.id = scp.color_id
          WHERE scp.series_id = ?
        ''', [_selectedSeries!['id']]);

        setState(() {
          _filteredColors = results;
          if (_filteredColors.isNotEmpty) {
            _selectedColor = _filteredColors.first;
          } else {
            _selectedColor = null;
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ التسجيل الصوتي بنجاح')),
        );
      } else {
        if (await Permission.microphone.request().isGranted) {
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

  // ── Speech to Text Tonal Engine ───────────────────────────────────────
  Future<void> _initSpeech() async {
    try {
      await _speech.initialize(
        onError: (val) => debugPrint('Speech error: $val'),
        onStatus: (val) => debugPrint('Speech status: $val'),
      );
    } catch (e) {
      debugPrint('STT init error: $e');
    }
  }

  void _toggleSpeechListening() async {
    if (_isListening) {
      await _speech.stop();
      setState(() {
        _isListening = false;
        _voiceStatusText = 'توقف الميكروفون.';
      });
    } else {
      bool available = await _speech.initialize();
      if (available) {
        setState(() {
          _isListening = true;
          _voiceStatusText = 'جاري الاستماع...';
        });
        _speech.listen(
          onResult: (result) {
            setState(() {
              _spokenText = result.recognizedWords;
              _smartVoiceController.text = _spokenText;
              _parseSmartVoiceText(_spokenText);
            });
          },
          localeId: 'ar-DZ',
          listenFor: const Duration(seconds: 45),
          pauseFor: const Duration(seconds: 8),
        );
      } else {
        setState(() {
          _voiceStatusText = 'التعرف الصوتي غير متاح حالياً.';
        });
      }
    }
  }

  void _parseSmartVoiceText(String text) {
    if (text.isEmpty) return;
    final lowerText = text.toLowerCase().trim();

    // 1. Check for Width (العرض) and Length (الطول)
    RegExp widthReg = RegExp(r'(?:عرض|العرض|لارش|لارج|لارجور|width)\s*[:=-]?\s*(\d+)');
    RegExp heightReg = RegExp(r'(?:طول|الطول|ارتفاع|الارتفاع|لارتفاع|height|longueur)\s*[:=-]?\s*(\d+)');

    var widthMatch = widthReg.firstMatch(lowerText);
    var heightMatch = heightReg.firstMatch(lowerText);

    if (widthMatch != null) {
      _widthController.text = widthMatch.group(1)!;
    }
    if (heightMatch != null) {
      _lengthController.text = heightMatch.group(1)!;
    }

    if (widthMatch == null && heightMatch == null) {
      RegExp dimensionsReg = RegExp(r'(\d+)\s*(?:على|في|x|X|/)\s*(\d+)');
      var dimMatch = dimensionsReg.firstMatch(lowerText);
      if (dimMatch != null) {
        _widthController.text = dimMatch.group(1)!;
        _lengthController.text = dimMatch.group(2)!;
      }
    }

    // 2. Location matching
    final locations = {
      'المطبخ': ['مطبخ', 'المطبخ', 'الكوزينة', 'cuisine'],
      'الصالون': ['صالون', 'الصالون', 'salon'],
      'غرفة النوم': ['غرفة', 'الغرفة', 'بيت', 'chambre'],
      'الحمام': ['حمام', 'الحمام', 'دوش', 'douche', 'bain'],
      'الشرفة': ['شرفة', 'الشرفة', 'بلكون', 'بلكونة', 'balcon'],
    };

    bool locationFound = false;
    for (var entry in locations.entries) {
      for (var kw in entry.value) {
        if (lowerText.contains(kw)) {
          setState(() {
            _locationController.text = entry.key;
          });
          locationFound = true;
          break;
        }
      }
      if (locationFound) break;
    }

    // 3. Shutter matching (الستار)
    final shutterYes = ['مع ستار', 'بستار', 'بالستار', 'فيها ستار', 'يوجد ستار', 'شتر', 'volet'];
    final shutterNo = ['بدون ستار', 'بلا ستار', 'مافيش ستار', 'sans volet'];

    for (var kw in shutterYes) {
      if (lowerText.contains(kw)) {
        setState(() => _shutterExists = true);
        break;
      }
    }
    for (var kw in shutterNo) {
      if (lowerText.contains(kw)) {
        setState(() => _shutterExists = false);
        break;
      }
    }

    // 4. Series matching
    for (var ser in _seriesList) {
      final name = ser['name'].toString().toLowerCase();
      final numberMatch = RegExp(r'\d+').firstMatch(name);
      if (numberMatch != null) {
        final numStr = numberMatch.group(0)!;
        if (lowerText.contains(numStr)) {
          setState(() {
            _selectedSeries = ser;
            _updateColorsForSelectedSeries();
            final String type = ser['type']?.toString() ?? '';
            if (type == 'Coulissant' || type.toLowerCase().contains('sliding')) {
              _openingSystem = 'Sliding';
            } else if (type == 'Frappe' || type.toLowerCase().contains('french') || type.toLowerCase().contains('frappe')) {
              _openingSystem = 'French';
            }
          });
          break;
        }
      }
    }

    // 5. Color matching (from filtered colors)
    for (var col in _filteredColors) {
      final name = col['name'].toString().toLowerCase();
      if (lowerText.contains(name)) {
        setState(() {
          _selectedColor = col;
        });
        break;
      }
    }

    // 6. Handle height
    RegExp handleReg = RegExp(r'(?:مقبض|المقبض|ارتفاع المقبض)\s*[:=-]?\s*(\d+)');
    var handleMatch = handleReg.firstMatch(lowerText);
    if (handleMatch != null) {
      _handleHeightController.text = handleMatch.group(1)!;
    }

    // 7. Store entire transcribed text in notes
    _noteController.text = text;
  }

  // ── Operations ────────────────────────────────────────────────────────
  Future<void> _saveMeasurement() async {
    if (!_formKey.currentState!.validate()) return;

    final data = {
      'length': double.tryParse(_lengthController.text) ?? 0.0,
      'width': double.tryParse(_widthController.text) ?? 0.0,
      'frame_type': _selectedSeries != null ? _selectedSeries!['name'].toString() : '',
      'opening_system': _openingSystem,
      'shutter_exists': _shutterExists ? 1 : 0,
      'shutter_side': _shutterSide,
      'shutter_type': _shutterType,
      'shutter_motor_maneuver': _shutterMotorManeuver ? 1 : 0,
      'glass_type': _glassType,
      'glass_decoration': _glassDecoration ? 1 : 0,
      'handle_height': double.tryParse(_handleHeightController.text) ?? 0.0,
      'reinforced_lateral': _reinforcedLateral ? 1 : 0,
      'reinforced_center': _reinforcedCenter ? 1 : 0,
      'bottom_frame_exists': _bottomFrameExists ? 1 : 0,
      'window_location': _locationController.text.trim(),
      'media_path': _imageFile?.path ?? '',
      'audio_path': _recordedAudioPath ?? '',
      'video_path': _videoFile?.path ?? '',
      'note': _noteController.text.trim(),
    };

    try {
      await widget.db.insertMeasurement(data);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ ورقة القياسات بنجاح')),
      );
      _clearForm();
      _loadSavedMeasurements();
    } catch (e) {
      debugPrint('Error saving measurement: $e');
    }
  }

  void _clearForm() {
    _lengthController.clear();
    _widthController.clear();
    _handleHeightController.clear();
    _locationController.clear();
    _noteController.clear();
    setState(() {
      _imageFile = null;
      _videoFile = null;
      _recordedAudioPath = null;
      _shutterExists = false;
      _shutterMotorManeuver = false;
      _reinforcedLateral = false;
      _reinforcedCenter = false;
      _bottomFrameExists = true;
    });
  }

  // ── ZIP Export / Import ───────────────────────────────────────────────
  Future<void> _exportToZip(Map<String, dynamic> item) async {
    try {
      final archive = Archive();

      // Write info json
      final jsonBytes = utf8.encode(jsonEncode(item));
      archive.addFile(ArchiveFile('metadata.json', jsonBytes.length, jsonBytes));

      // Add image if exists
      final imgPath = item['media_path']?.toString() ?? '';
      if (imgPath.isNotEmpty && File(imgPath).existsSync()) {
        final bytes = await File(imgPath).readAsBytes();
        archive.addFile(ArchiveFile('image${p.extension(imgPath)}', bytes.length, bytes));
      }

      // Add video if exists
      final vidPath = item['video_path']?.toString() ?? '';
      if (vidPath.isNotEmpty && File(vidPath).existsSync()) {
        final bytes = await File(vidPath).readAsBytes();
        archive.addFile(ArchiveFile('video${p.extension(vidPath)}', bytes.length, bytes));
      }

      // Add audio if exists
      final audPath = item['audio_path']?.toString() ?? '';
      if (audPath.isNotEmpty && File(audPath).existsSync()) {
        final bytes = await File(audPath).readAsBytes();
        archive.addFile(ArchiveFile('audio${p.extension(audPath)}', bytes.length, bytes));
      }

      // Encode ZIP
      final zipEncoder = ZipEncoder();
      final zipData = zipEncoder.encode(archive);
      if (zipData == null) return;

      final tempDir = await getTemporaryDirectory();
      final cleanLocation = (item['window_location'] ?? 'قياس').toString().replaceAll(' ', '_');
      final zipFile = File(p.join(tempDir.path, '${cleanLocation}_${item['length']}x${item['width']}.zip'));
      await zipFile.writeAsBytes(zipData);

      // Share ZIP (OneDrive/Google Drive upload path)
      await Share.shareXFiles([XFile(zipFile.path)], text: 'مشاركة ملف القياسات المضغوط');
    } catch (e) {
      debugPrint('Export ZIP error: $e');
    }
  }

  Future<void> _importFromZip() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (result == null || result.files.single.path == null) return;

      final zipFile = File(result.files.single.path!);
      final bytes = await zipFile.readAsBytes();

      // Decode ZIP
      final archive = ZipDecoder().decodeBytes(bytes);
      final metadataFile = archive.findFile('metadata.json');
      if (metadataFile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('خطأ: لم يتم العثور على ملف البيانات الأساسي داخل الـ ZIP')),
        );
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

      // Reconstruct item for database insertion
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
        'glass_decoration': item['glass_decoration'] ?? 0,
        'handle_height': item['handle_height'] ?? 0.0,
        'reinforced_lateral': item['reinforced_lateral'] ?? 0,
        'reinforced_center': item['reinforced_center'] ?? 0,
        'bottom_frame_exists': item['bottom_frame_exists'] ?? 1,
        'window_location': item['window_location'] ?? '',
        'media_path': localImgPath,
        'audio_path': localAudPath,
        'video_path': localVidPath,
        'note': item['note'] ?? '',
      };

      await widget.db.insertMeasurement(restoredItem);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم استيراد واسترجاع ورقة القياس بجميع مرفقاتها بنجاح!')),
      );
      _loadSavedMeasurements();
    } catch (e) {
      debugPrint('Import ZIP error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ أثناء استيراد الـ ZIP: $e')),
      );
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
          color: isSelected ? selectedColor.withOpacity(0.12) : Colors.white,
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
                color: isSelected ? selectedColor : Colors.black87,
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('ورقة رفع القياسات الذكية', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.unarchive_outlined),
            tooltip: 'استيراد قياس ZIP / Import',
            onPressed: _importFromZip,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // ── الجزء الصوتي الفعال ──────────────────────────────────
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 3,
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.mic, color: _isListening ? Colors.red : Colors.blue, size: 28),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _isListening ? 'جاري الاستماع... تحدث الآن' : 'المساعد الصوتي والإملاء الذكي',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                          if (_isListening)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _smartVoiceController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'مثال: "نافذة في المطبخ عرض 120 وطول 150 مع ستار أبيض سلسلة 67000"',
                          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13, fontFamily: 'Cairo'),
                          fillColor: Colors.white,
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.blue.shade200),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.blue, width: 1.5),
                          ),
                        ),
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                        onChanged: (text) {
                          _parseSmartVoiceText(text);
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _toggleSpeechListening,
                              icon: Icon(_isListening ? Icons.stop : Icons.mic, color: Colors.white),
                              label: Text(
                                _isListening ? 'إيقاف الاستماع' : 'ابدأ الإملاء الصوتي',
                                style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isListening ? Colors.red : Colors.blue,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            onPressed: () {
                              _parseSmartVoiceText(_smartVoiceController.text);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('تم تحليل وتطبيق البيانات في الحقول أدناه بنجاح!'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                            icon: const Icon(Icons.analytics, color: Colors.white),
                            label: const Text(
                              'تحليل وتطبيق',
                              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── استمارة القياسات ─────────────────────────────────────
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
                                  labelText: 'الطول (مم)',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                validator: (val) => val == null || val.isEmpty ? 'مطلوب' : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _widthController,
                                focusNode: _widthFocus,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  labelText: 'العرض (مم)',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                validator: (val) => val == null || val.isEmpty ? 'مطلوب' : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // موقع النافذة
                        TextFormField(
                          controller: _locationController,
                          focusNode: _locationFocus,
                          decoration: InputDecoration(
                            labelText: 'موقع النافذة (مثال: المطبخ، الصالون)',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          validator: (val) => val == null || val.isEmpty ? 'مطلوب' : null,
                        ),
                        const SizedBox(height: 12),

                        // اختيارات سريعة للمواقع المعتادة
                        Wrap(
                          spacing: 8,
                          children: ['المطبخ', 'الصالون', 'غرفة النوم', 'الحمام', 'الشرفة'].map((loc) {
                            return ChoiceChip(
                              label: Text(loc, style: const TextStyle(fontFamily: 'Cairo')),
                              selected: _locationController.text == loc,
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

                        // اختيار السلسلة ديناميكياً
                        const Text(
                          'نظام السلسلة (Series)',
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        _seriesList.isEmpty
                            ? const Text('جاري تحميل السلاسل...')
                            : Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _seriesList.map((ser) {
                                  final isSel = _selectedSeries?['id'] == ser['id'];
                                  return ChoiceChip(
                                    label: Text(ser['name'].toString(), style: const TextStyle(fontFamily: 'Cairo')),
                                    selected: isSel,
                                    onSelected: (selected) {
                                      if (selected) {
                                        setState(() {
                                          _selectedSeries = ser;
                                          _updateColorsForSelectedSeries();
                                          final String type = ser['type']?.toString() ?? '';
                                          if (type == 'Coulissant' || type.toLowerCase().contains('sliding')) {
                                            _openingSystem = 'Sliding';
                                          } else if (type == 'Frappe' || type.toLowerCase().contains('french') || type.toLowerCase().contains('frappe')) {
                                            _openingSystem = 'French';
                                          }
                                        });
                                      }
                                    },
                                  );
                                }).toList(),
                              ),
                        const Divider(height: 32),

                        // الألوان المفلترة
                        if (_selectedSeries != null) ...[
                          const Text(
                            'اللون المتوفر لهذه السلسلة',
                            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 8),
                          _filteredColors.isEmpty
                              ? const Text('لا توجد ألوان محددة لهذه السلسلة في قاعدة البيانات.')
                              : Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _filteredColors.map((col) {
                                    final isSel = _selectedColor?['id'] == col['id'];
                                    return ChoiceChip(
                                      label: Text(col['name'].toString(), style: const TextStyle(fontFamily: 'Cairo')),
                                      selected: isSel,
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
                        ],

                        if (_selectedSeries == null) ...[
                          // نظام الفتح
                          const Text(
                            'نظام الفتح',
                            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _buildToggleChip('منزلق / Sliding', _openingSystem == 'Sliding', () {
                                setState(() => _openingSystem = 'Sliding');
                              }),
                              const SizedBox(width: 10),
                              _buildToggleChip('فتحة / Ouvrant', _openingSystem == 'French', () {
                                setState(() => _openingSystem = 'French');
                              }),
                            ],
                          ),
                          const Divider(height: 32),
                        ],

                        // خيارات بنعم/لا ذكية
                        _buildSelectionRow(
                          title: 'هل يوجد ستار؟ (Shutter)',
                          yesLabel: 'نعم يوجد',
                          noLabel: 'لا يوجد',
                          value: _shutterExists,
                          onChanged: (val) => setState(() => _shutterExists = val),
                        ),

                        if (_shutterExists) ...[
                          _buildSelectionRow(
                            title: 'جهة الستار',
                            yesLabel: 'داخل / Inside',
                            noLabel: 'خارج / Outside',
                            value: _shutterSide == 'Inside',
                            onChanged: (val) => setState(() => _shutterSide = val ? 'Inside' : 'Outside'),
                          ),
                          _buildSelectionRow(
                            title: 'نوع شفرة الستار',
                            yesLabel: 'ألمنيوم / Aluminium',
                            noLabel: 'بي في سي / PVC',
                            value: _shutterType == 'Aluminium',
                            onChanged: (val) => setState(() => _shutterType = val ? 'Aluminium' : 'PVC'),
                          ),
                          _buildSelectionRow(
                            title: 'هل المحرك بمناورة أمان (Maneuver Security)؟',
                            yesLabel: 'نعم / Yes',
                            noLabel: 'لا / No',
                            value: _shutterMotorManeuver,
                            onChanged: (val) => setState(() => _shutterMotorManeuver = val),
                          ),
                        ],

                        _buildSelectionRow(
                          title: 'نوع الزجاج',
                          yesLabel: 'مزدوج / Double',
                          noLabel: 'بسيط / Simple',
                          value: _glassType == 'Double',
                          onChanged: (val) => setState(() => _glassType = val ? 'Double' : 'Simple'),
                        ),

                        _buildSelectionRow(
                          title: 'هل يوجد ديكور زجاج؟',
                          yesLabel: 'نعم يوجد',
                          noLabel: 'لا يوجد',
                          value: _glassDecoration,
                          onChanged: (val) => setState(() => _glassDecoration = val),
                        ),

                        _buildSelectionRow(
                          title: 'محل جانبي مدعم (Montant Latéral Renforcé)؟',
                          yesLabel: 'نعم مدعم',
                          noLabel: 'غير مدعم',
                          value: _reinforcedLateral,
                          onChanged: (val) => setState(() => _reinforcedLateral = val),
                        ),

                        _buildSelectionRow(
                          title: 'محل وسطي مدعم (Montant Central Renforcé)؟',
                          yesLabel: 'نعم مدعم',
                          noLabel: 'غير مدعم',
                          value: _reinforcedCenter,
                          onChanged: (val) => setState(() => _reinforcedCenter = val),
                        ),

                        _buildSelectionRow(
                          title: 'هل الإطار السفلي موجود؟',
                          yesLabel: 'موجود',
                          noLabel: 'ملغي',
                          value: _bottomFrameExists,
                          onChanged: (val) => setState(() => _bottomFrameExists = val),
                        ),

                        // ارتفاع المقبض
                        TextFormField(
                          controller: _handleHeightController,
                          focusNode: _handleHeightFocus,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'ارتفاع المقبض (مم) - اختياري',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // الملاحظات
                        TextFormField(
                          controller: _noteController,
                          focusNode: _noteFocus,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: 'ملاحظات إضافية',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ── قسم الميديا وتسجيل الصوت ────────────────────────
                        Row(
                          children: [
                            const Icon(Icons.attach_file, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text(
                              'المرفقات والوسائط التوضيحية',
                              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.blue[800]),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            ElevatedButton.icon(
                              icon: const Icon(Icons.camera_alt),
                              label: const Text('صورة', style: TextStyle(fontFamily: 'Cairo')),
                              onPressed: _pickImage,
                            ),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.videocam),
                              label: const Text('فيديو', style: TextStyle(fontFamily: 'Cairo')),
                              onPressed: _pickVideo,
                            ),
                            ElevatedButton.icon(
                              icon: Icon(_isRecording ? Icons.stop : Icons.mic, color: _isRecording ? Colors.red : Colors.white),
                              label: Text(_isRecording ? 'إيقاف' : 'تسجيل صوت', style: const TextStyle(fontFamily: 'Cairo')),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isRecording ? Colors.red[50] : null,
                              ),
                              onPressed: _toggleAudioRecording,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // معاينة الميديا المرفقة
                        if (_imageFile != null || _videoFile != null || _recordedAudioPath != null) ...[
                          const Text('المرفقات المحملة حالياً:', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
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
                                  decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green)),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow, color: Colors.green),
                                        onPressed: _playRecordedAudio,
                                      ),
                                      const Text('تسجيل صوتي', style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
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
                              backgroundColor: Colors.blue[700],
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _saveMeasurement,
                            child: const Text('حفظ القياس في الهاتف', style: TextStyle(fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
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
                  const Icon(Icons.history, color: Colors.black87),
                  const SizedBox(width: 8),
                  Text(
                    'القياسات المسجلة سابقاً (${_savedMeasurements.length})',
                    style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              _savedMeasurements.isEmpty
                  ? const Text('لا توجد قياسات مسجلة بعد.')
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
                              '${item['window_location']} - ${item['length']} × ${item['width']} مم',
                              style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              'نظام: ${item['opening_system']} | ستار: ${item['shutter_exists'] == 1 ? 'نعم' : 'لا'}\nملاحظة: ${item['note'] ?? ''}',
                              style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.share, color: Colors.blue),
                                  tooltip: 'مشاركة ورفع كـ ZIP',
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
