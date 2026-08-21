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
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../sql_database.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../Commande/order_workspace_screen.dart';
import '../Commande/Systeme/model.dart';

class MeasurementsScreen extends StatefulWidget {
  final SqlDatabase db;
  const MeasurementsScreen({super.key, required this.db});

  @override
  State<MeasurementsScreen> createState() => _MeasurementsScreenState();
}

class _MeasurementsScreenState extends State<MeasurementsScreen> {
  final _formKey = GlobalKey<FormState>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = Provider.of<AppSettingsProvider>(context);
    if (!settings.isManager && !settings.canAccessMeasurements()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });
    }
  }

  // Controllers
  final _lengthController = TextEditingController();
  final _widthController = TextEditingController();
  final _locationController = TextEditingController(text: 'المطبخ');
  final _orderGroupController = TextEditingController();
  final _noteController = TextEditingController();

  // Focus Nodes
  final _lengthFocus = FocusNode();
  final _widthFocus = FocusNode();
  final _noteFocus = FocusNode();

  // Form State Values
  List<Map<String, dynamic>> _allColors = [];
  Map<String, dynamic>? _selectedColor;

  List<Map<String, dynamic>> _allProfiles = [];
  Map<String, dynamic>? _selectedProfile;

  String _openingSystem = 'French'; // French (Battante) or Sliding (Coulissante)
  bool _shutterExists = false;
  bool _shutterMotorManeuver = false;
  String _glassType = 'Double'; // Simple or Double
  bool _bottomFrameExists = true;

  String _normalizedColorName(Map<String, dynamic>? color) {
    return (color?['name'] ?? color?['color_name'] ?? '')
        .toString()
        .toLowerCase()
        .trim()
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه');
  }

  bool _isWhiteColor(Map<String, dynamic>? color) {
    final name = _normalizedColorName(color);
    final hex = (color?['hex_code'] ?? color?['hex'] ?? '')
        .toString()
        .replaceAll('#', '')
        .toLowerCase()
        .trim();
    return name.contains('white') ||
        name.contains('blanc') ||
        name.contains('ابيض') ||
        hex == 'ffffff' ||
        hex == 'fff';
  }

  Map<String, dynamic>? _defaultWhiteColor() {
    for (final color in _allColors) {
      if (_isWhiteColor(color)) return color;
    }
    return _allColors.isNotEmpty ? _allColors.first : null;
  }

  // Attached files
  File? _imageFile;
  File? _videoFile;
  String? _recordedAudioPath;

  // Voice recording state
  final _audioRecorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  bool _isPlaying = false;

  // Speech-to-text (continuous dictation) state
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  bool _isSpeechListening = false;
  bool _speechInitialized = false;
  String _textBeforeSpeech = '';

  // Measurements list & batch state
  List<Map<String, dynamic>> _savedMeasurements = [];
  final Set<int> _selectedMeasurementIds = {};
  bool _isMultiSelectMode = false;
  String _selectedGroupFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _loadAllColors();
    _loadAllProfiles();
    _loadSavedMeasurements();
  }

  @override
  void dispose() {
    _lengthController.dispose();
    _widthController.dispose();
    _locationController.dispose();
    _orderGroupController.dispose();
    _noteController.dispose();
    _lengthFocus.dispose();
    _widthFocus.dispose();
    _noteFocus.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _speechToText.stop();
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
            _selectedColor = _defaultWhiteColor();
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading colors: $e');
    }
  }

  Future<void> _loadAllProfiles() async {
    try {
      final profilesData = await widget.db.readAllProfiles();
      setState(() {
        _allProfiles = profilesData;
        if (_allProfiles.isNotEmpty && _selectedProfile == null) {
          _selectedProfile = _allProfiles.first;
        }
      });
    } catch (e) {
      debugPrint('Error loading profiles: $e');
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

  // ── Populating Form from Saved Measurement ────────────────────────────
  void _populateFormFromMeasurement(Map<String, dynamic> item) {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    setState(() {
      _lengthController.text = (item['length'] ?? '').toString();
      _widthController.text = (item['width'] ?? '').toString();
      _locationController.text = (item['window_location'] ?? '').toString();
      _orderGroupController.text = (item['order_group_name'] ?? '').toString();
      _openingSystem = (item['opening_system'] ?? 'French').toString();
      _shutterExists = (item['shutter_exists'] ?? 0) == 1;
      _shutterMotorManeuver = (item['shutter_motor_maneuver'] ?? 0) == 1;
      _glassType = (item['glass_type'] ?? 'Double').toString();
      _bottomFrameExists = (item['bottom_frame_exists'] ?? 1) == 1;
      _noteController.text = (item['note'] ?? '').toString();

      final pId = item['profile_id'];
      final pName = (item['profile_name'] ?? '').toString();
      if (_allProfiles.isNotEmpty) {
        try {
          _selectedProfile = _allProfiles.firstWhere(
            (p) => (pId != null && p['id'] == pId) || p['name'].toString().toLowerCase() == pName.toLowerCase(),
            orElse: () => _allProfiles.first,
          );
        } catch (_) {}
      }

      final frameType = (item['frame_type'] ?? '').toString();
      if (frameType.isNotEmpty && _allColors.isNotEmpty) {
        try {
          _selectedColor = _allColors.firstWhere(
            (c) => c['name'].toString().toLowerCase() == frameType.toLowerCase(),
            orElse: () => _defaultWhiteColor() ?? _allColors.first,
          );
        } catch (_) {}
      }

      final imgPath = (item['media_path'] ?? '').toString();
      final vidPath = (item['video_path'] ?? '').toString();
      final audPath = (item['audio_path'] ?? '').toString();

      _imageFile = imgPath.isNotEmpty && File(imgPath).existsSync() ? File(imgPath) : null;
      _videoFile = vidPath.isNotEmpty && File(vidPath).existsSync() ? File(vidPath) : null;
      _recordedAudioPath = audPath.isNotEmpty && File(audPath).existsSync() ? audPath : null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(Localization.translate('تم توظيف واسترجاع بيانات القياس في الشاشة بنجاح!', lang)),
        backgroundColor: Colors.blue,
      ),
    );
  }

  // ── Convert Measurement(s) to Order ──────────────────────────────────
  Future<WindowModel> _createWindowModelFromMeasurement(Map<String, dynamic> item) async {
    final double w = (item['width'] as num?)?.toDouble() ?? 0.0;
    final double h = (item['length'] as num?)?.toDouble() ?? 0.0;
    final String location = (item['window_location'] ?? '').toString();
    final bool shutterExists = (item['shutter_exists'] ?? 0) == 1;
    final bool bottomFrame = (item['bottom_frame_exists'] ?? 1) == 1;
    final String openingSystem = (item['opening_system'] ?? 'French').toString();
    final bool isSliding = openingSystem == 'Sliding';

    final model = WindowModel(
      width: w,
      height: h,
      db: widget.db,
      systemMode: isSliding ? 'sliding' : 'french',
    );
    model.position = location;
    model.hasShutter = shutterExists;
    model.hasBottomFrame = bottomFrame;

    final profileId = item['profile_id'] as int?;
    final profileName = (item['profile_name'] ?? '').toString();

    if (profileId != null) {
      try {
        final seriesData = await widget.db.readSeriesByProfile(profileId);
        if (seriesData.isNotEmpty) {
          Map<String, dynamic>? slidingSeries;
          Map<String, dynamic>? frenchSeries;

          for (var s in seriesData) {
            final type = (s['type'] ?? '').toString().toLowerCase();
            final name = (s['name'] ?? '').toString().toLowerCase();
            if (type.contains('couliss') || type.contains('sliding') || type.contains('منزلق') || name.contains('couliss') || name.contains('sliding')) {
              slidingSeries ??= s;
            } else {
              frenchSeries ??= s;
            }
          }

          slidingSeries ??= seriesData.first;
          frenchSeries ??= seriesData.first;

          if (isSliding) {
            model.loadedSlidingSeriesId = slidingSeries['id'] as int?;
            model.loadedSlidingSeriesName = slidingSeries['name'] as String?;
            model.loadedSeriesId = frenchSeries['id'] as int?;
            model.loadedSeriesName = frenchSeries['name'] as String?;
          } else {
            model.loadedSeriesId = frenchSeries['id'] as int?;
            model.loadedSeriesName = frenchSeries['name'] as String?;
            model.loadedSlidingSeriesId = slidingSeries['id'] as int?;
            model.loadedSlidingSeriesName = slidingSeries['name'] as String?;
          }
        }
      } catch (e) {
        debugPrint('Error matching series for profile: $e');
      }
    } else if (profileName.isNotEmpty && _allProfiles.isNotEmpty) {
      try {
        final pMatch = _allProfiles.firstWhere(
          (p) => p['name'].toString().toLowerCase() == profileName.toLowerCase(),
          orElse: () => <String, dynamic>{},
        );
        if (pMatch.isNotEmpty && pMatch['id'] != null) {
          final pId = pMatch['id'] as int;
          final seriesData = await widget.db.readSeriesByProfile(pId);
          if (seriesData.isNotEmpty) {
            Map<String, dynamic>? slidingSeries;
            Map<String, dynamic>? frenchSeries;
            for (var s in seriesData) {
              final type = (s['type'] ?? '').toString().toLowerCase();
              final name = (s['name'] ?? '').toString().toLowerCase();
              if (type.contains('couliss') || type.contains('sliding') || type.contains('منزلق') || name.contains('couliss') || name.contains('sliding')) {
                slidingSeries ??= s;
              } else {
                frenchSeries ??= s;
              }
            }
            slidingSeries ??= seriesData.first;
            frenchSeries ??= seriesData.first;

            if (isSliding) {
              model.loadedSlidingSeriesId = slidingSeries['id'] as int?;
              model.loadedSlidingSeriesName = slidingSeries['name'] as String?;
              model.loadedSeriesId = frenchSeries['id'] as int?;
              model.loadedSeriesName = frenchSeries['name'] as String?;
            } else {
              model.loadedSeriesId = frenchSeries['id'] as int?;
              model.loadedSeriesName = frenchSeries['name'] as String?;
              model.loadedSlidingSeriesId = slidingSeries['id'] as int?;
              model.loadedSlidingSeriesName = slidingSeries['name'] as String?;
            }
          }
        }
      } catch (_) {}
    }

    // Apply color if available
    final frameType = (item['frame_type'] ?? '').toString();
    if (frameType.isNotEmpty && _allColors.isNotEmpty) {
      try {
        final matched = _allColors.firstWhere(
          (c) => c['name'].toString().toLowerCase() == frameType.toLowerCase(),
          orElse: () => _defaultWhiteColor() ?? _allColors.first,
        );
        model.selectedDbColor = matched;
      } catch (_) {}
    }

    // Auto-draw 2-sash window zone
    if (w > 0 && h > 0) {
      final double profileT = model.profileThickness;
      final double shutterH = shutterExists ? 155.0 : 0.0;
      final double bottomOffset = bottomFrame ? profileT : 0.0;
      final Rect fullZone = Rect.fromLTRB(
        profileT,
        shutterH + profileT,
        w - profileT,
        h - bottomOffset,
      );

      if (isSliding) {
        model.zones.add(WindowZone(
          id: UniqueKey().toString(),
          boundary: fullZone,
          content: ZoneContent.slidingSash,
          slidingSashesCount: 2,
          sashThickness: model.profileThickness,
        ));
      } else {
        model.zones.add(WindowZone(
          id: UniqueKey().toString(),
          boundary: fullZone,
          content: ZoneContent.doubleSash,
          sashThickness: model.profileThickness,
        ));
      }
    }

    return model;
  }

  Future<void> _convertMeasurementToOrder(Map<String, dynamic> item) async {
    final model = await _createWindowModelFromMeasurement(item);
    if (!mounted) return;
    openOrderInWorkspaceTab(
      context,
      db: widget.db,
      initialProducts: [model],
    );
  }

  Future<void> _convertSelectedMeasurementsToOrder(List<Map<String, dynamic>> items) async {
    if (items.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final models = <WindowModel>[];
      for (final item in items) {
        final m = await _createWindowModelFromMeasurement(item);
        models.add(m);
      }
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      if (!mounted) return;
      openOrderInWorkspaceTab(
        context,
        db: widget.db,
        initialProducts: models,
      );
    } catch (e) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      debugPrint('Error converting measurements to order: $e');
    }
  }

  Future<void> _convertAllMeasurementsToOrder() async {
    await _convertSelectedMeasurementsToOrder(_savedMeasurements);
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

  // ── Speech-to-Text (Continuous dictation to notes) ──────────────────
  Future<void> _toggleSpeechToText() async {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;

    if (_isSpeechListening) {
      await _stopSpeechToText();
      return;
    }

    if (!_speechInitialized) {
      _speechInitialized = await _speechToText.initialize(
        onError: (val) {
          debugPrint('SpeechToText onError: $val');
          if (mounted && _isSpeechListening) {
            _startContinuousListening();
          }
        },
        onStatus: (val) {
          debugPrint('SpeechToText onStatus: $val');
          if ((val == 'done' || val == 'notListening') && _isSpeechListening && mounted) {
            _startContinuousListening();
          }
        },
      );
    }

    if (_speechInitialized) {
      setState(() {
        _isSpeechListening = true;
        _textBeforeSpeech = _noteController.text;
        if (_textBeforeSpeech.isNotEmpty && !_textBeforeSpeech.endsWith(' ')) {
          _textBeforeSpeech += ' ';
        }
      });
      await _startContinuousListening();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(Localization.translate('الميكروفون يستمع الآن بشكل مستمر... تحدث بصوت واضح', lang)),
            backgroundColor: Colors.teal,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(Localization.translate('عذراً، التعرف على الصوت غير متاح في جهازك أو يتطلب إذن الميكروفون', lang)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _startContinuousListening() async {
    if (!_isSpeechListening) return;
    try {
      await _speechToText.listen(
        onResult: (val) {
          if (mounted && val.recognizedWords.isNotEmpty) {
            setState(() {
              _noteController.text = _textBeforeSpeech + val.recognizedWords;
              _noteController.selection = TextSelection.fromPosition(
                TextPosition(offset: _noteController.text.length),
              );
            });
          }
        },
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          onDevice: false,
          cancelOnError: false,
        ),
      );
    } catch (e) {
      debugPrint('Continuous listen error: $e');
    }
  }

  Future<void> _stopSpeechToText() async {
    setState(() {
      _isSpeechListening = false;
    });
    try {
      await _speechToText.stop();
    } catch (_) {}
    if (mounted) {
      final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Localization.translate('تم إيقاف الاستماع الصوتي وتثبيت النص', lang)),
          backgroundColor: Colors.blue,
        ),
      );
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
      'profile_id': _selectedProfile?['id'],
      'profile_name': _selectedProfile?['name'] ?? '',
      'order_group_name': _orderGroupController.text.trim(),
      'opening_system': _openingSystem,
      'shutter_exists': _shutterExists ? 1 : 0,
      'shutter_side': 'Inside',
      'shutter_type': 'Aluminium',
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
        'profile_id': item['profile_id'],
        'profile_name': item['profile_name'] ?? '',
        'order_group_name': item['order_group_name'] ?? '',
        'opening_system': item['opening_system'] ?? '',
        'shutter_exists': item['shutter_exists'] ?? 0,
        'shutter_side': 'Inside',
        'shutter_type': 'Aluminium',
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
          color: isSelected ? selectedColor.withValues(alpha: 0.12) : Theme.of(context).cardColor,
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

    // Separate location choices
    final locationOptions = [
      Localization.translate('المطبخ', lang),
      Localization.translate('الصالون', lang),
      Localization.translate('غرفة النوم', lang),
      Localization.translate('الحمام', lang),
      Localization.translate('المرحاض', lang),
      Localization.translate('الشرفة', lang),
      Localization.translate('تيراس', lang),
    ];

    // Unique order group names for filtering
    final Set<String> groupNames = {};
    for (var m in _savedMeasurements) {
      final g = (m['order_group_name'] ?? '').toString().trim();
      if (g.isNotEmpty) groupNames.add(g);
    }
    final List<String> availableGroupFilters = ['ALL', ...groupNames];

    // Filtered measurements
    final List<Map<String, dynamic>> displayedMeasurements = _savedMeasurements.where((item) {
      if (_selectedGroupFilter == 'ALL') return true;
      final g = (item['order_group_name'] ?? '').toString().trim();
      return g == _selectedGroupFilter;
    }).toList();

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
                        // اسم الطلب / المشروع / الزبون (لتجميع القياسات)
                        TextFormField(
                          controller: _orderGroupController,
                          decoration: InputDecoration(
                            labelText: Localization.translate('اسم الطلب / المشروع (مثال: طلبية شقة الحاج علي)', lang),
                            hintText: Localization.translate('لتجميع القياسات وتحويلها كطلبية واحدة', lang),
                            prefixIcon: const Icon(Icons.folder_special_outlined, color: Colors.blue),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(height: 16),

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

                        // موقع النافذة
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
                              selectedColor: Colors.blue.withValues(alpha: 0.2),
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

                        // 🟢 اختيار نظام الألمنيوم / البروفيل (System Profile)
                        Row(
                          children: [
                            const Icon(Icons.settings_suggest_rounded, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text(
                              Localization.translate('نظام الألمنيوم / البروفيل (Profile System)', lang),
                              style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _allProfiles.isEmpty
                            ? Text(Localization.translate('جاري تحميل الأنظمة...', lang))
                            : Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _allProfiles.map((prof) {
                                  final isSel = _selectedProfile?['id'] == prof['id'];
                                  return ChoiceChip(
                                    avatar: isSel
                                        ? const Icon(Icons.check, size: 16, color: Colors.blue)
                                        : const Icon(Icons.dashboard_outlined, size: 16),
                                    label: Text(
                                      prof['name'].toString(),
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                    selected: isSel,
                                    selectedColor: Colors.blue.withValues(alpha: 0.2),
                                    onSelected: (selected) {
                                      if (selected) {
                                        setState(() {
                                          _selectedProfile = prof;
                                        });
                                      }
                                    },
                                  );
                                }).toList(),
                              ),
                        const Divider(height: 32),

                        // الألوان المتوفرة للبروفيلات
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
                                    selectedColor: Colors.blue.withValues(alpha: 0.2),
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

                        // نظام الفتح
                        Text(
                          Localization.translate('نظام الفتح', lang),
                          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildToggleChip(
                              Localization.translate('Coulissante (منزلق)', lang),
                              _openingSystem == 'Sliding',
                              () => setState(() => _openingSystem = 'Sliding'),
                            ),
                            _buildToggleChip(
                              Localization.translate('Battante (مفصلي/فتح)', lang),
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

                        // الملاحظات مع ميكروفون الإملاء الصوتي المستمر
                        TextFormField(
                          controller: _noteController,
                          focusNode: _noteFocus,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: Localization.translate('ملاحظات إضافية', lang),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _isSpeechListening ? Icons.mic : Icons.mic_none,
                                color: _isSpeechListening ? Colors.red : Colors.blue,
                                size: 28,
                              ),
                              tooltip: Localization.translate('تحويل الكلام إلى نص مستمر', lang),
                              onPressed: _toggleSpeechToText,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              icon: Icon(
                                _isSpeechListening ? Icons.mic : Icons.mic_none_outlined,
                                color: Colors.white,
                              ),
                              label: Text(
                                _isSpeechListening
                                    ? Localization.translate('إيقاف الاستماع المستمر', lang)
                                    : Localization.translate('تحدث لإملاء الملاحظات (مستمر بدون انقطاع)', lang),
                                style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isSpeechListening ? Colors.red : Colors.blue,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              onPressed: _toggleSpeechToText,
                            ),
                            if (_isSpeechListening) ...[
                              const SizedBox(width: 10),
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 20),

                        // ── قسم الميديا وتسجيل الصوت ──
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

              // ── قائمة القياسات السابقة وتعديل التحويل الجماعي ──────────────────────────────
              Row(
                children: [
                  const Icon(Icons.history_rounded, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${Localization.translate('القياسات المسجلة سابقاً', lang)} (${_savedMeasurements.length})',
                      style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  if (_savedMeasurements.isNotEmpty) ...[
                    IconButton(
                      tooltip: _isMultiSelectMode ? Localization.translate('إلغاء الوضع', lang) : Localization.translate('تحديد متعدد', lang),
                      icon: Icon(
                        _isMultiSelectMode ? Icons.check_box : Icons.check_box_outlined,
                        color: Colors.blue,
                      ),
                      onPressed: () {
                        setState(() {
                          _isMultiSelectMode = !_isMultiSelectMode;
                          if (!_isMultiSelectMode) _selectedMeasurementIds.clear();
                        });
                      },
                    ),
                    TextButton.icon(
                      onPressed: _convertAllMeasurementsToOrder,
                      icon: const Icon(Icons.add_shopping_cart, size: 18),
                      label: Text(
                        Localization.translate('تحويل الكل كطلبية', lang),
                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),

              // شريط تصفية بحسب "اسم الطلب / المشروع"
              if (availableGroupFilters.length > 2) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: availableGroupFilters.map((group) {
                      final isSel = _selectedGroupFilter == group;
                      final String label = group == 'ALL' ? Localization.translate('جميع الطلبيات', lang) : group;
                      return Padding(
                        padding: const EdgeInsets.only(left: 6.0),
                        child: FilterChip(
                          label: Text(label, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                          selected: isSel,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _selectedGroupFilter = group;
                              });
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // شريط إجراءات التحديد المتعدد
              if (_isMultiSelectMode && _selectedMeasurementIds.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade300),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${Localization.translate('محدد:', lang)} ${_selectedMeasurementIds.length}',
                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.blue),
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.shopping_cart_checkout_rounded, size: 18),
                        label: Text(
                          '${Localization.translate('تحويل المحددة كطلبية واحدة', lang)} (${_selectedMeasurementIds.length})',
                          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          final selectedItems = _savedMeasurements.where((item) {
                            final id = item['id'] as int?;
                            return id != null && _selectedMeasurementIds.contains(id);
                          }).toList();
                          _convertSelectedMeasurementsToOrder(selectedItems);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              displayedMeasurements.isEmpty
                  ? Text(Localization.translate('لا توجد قياسات مسجلة بعد.', lang))
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: displayedMeasurements.length,
                      itemBuilder: (ctx, idx) {
                        final item = displayedMeasurements[idx];
                        final itemId = item['id'] as int;
                        final isChecked = _selectedMeasurementIds.contains(itemId);

                        final String profileName = (item['profile_name'] ?? '').toString();
                        final String groupName = (item['order_group_name'] ?? '').toString();

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            onTap: () {
                              if (_isMultiSelectMode) {
                                setState(() {
                                  if (isChecked) {
                                    _selectedMeasurementIds.remove(itemId);
                                  } else {
                                    _selectedMeasurementIds.add(itemId);
                                  }
                                });
                              } else {
                                _populateFormFromMeasurement(item);
                              }
                            },
                            leading: _isMultiSelectMode
                                ? Checkbox(
                                    value: isChecked,
                                    onChanged: (val) {
                                      setState(() {
                                        if (val == true) {
                                          _selectedMeasurementIds.add(itemId);
                                        } else {
                                          _selectedMeasurementIds.remove(itemId);
                                        }
                                      });
                                    },
                                  )
                                : CircleAvatar(
                                    backgroundColor: Colors.blue.shade50,
                                    child: Icon(
                                      (item['opening_system'] == 'Sliding') ? Icons.view_column_rounded : Icons.sensor_door_rounded,
                                      color: Colors.blue,
                                    ),
                                  ),
                            title: Text(
                              '${Localization.translate((item['window_location'] ?? '').toString(), lang)} - ${item['length']} × ${item['width']} ${Localization.translate('مم', lang)}',
                              style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    if (profileName.isNotEmpty) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(6)),
                                        child: Text(
                                          profileName,
                                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    if (groupName.isNotEmpty) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(6)),
                                        child: Text(
                                          '📁 $groupName',
                                          style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    Text(
                                      '${Localization.translate('نظام', lang)}: ${Localization.translate((item['opening_system'] ?? '').toString(), lang)}',
                                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                                    ),
                                  ],
                                ),
                                Text(
                                  '${Localization.translate('ستار', lang)}: ${item['shutter_exists'] == 1 ? Localization.translate('نعم', lang) : Localization.translate('لا', lang)} | ${Localization.translate('ملاحظة', lang)}: ${item['note'] ?? ''}',
                                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.add_shopping_cart, color: Colors.green),
                                  tooltip: Localization.translate('تحويل إلى طلبية منفردة', lang),
                                  onPressed: () => _convertMeasurementToOrder(item),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.share, color: Colors.blue),
                                  tooltip: Localization.translate('مشاركة ورفع كـ ZIP', lang),
                                  onPressed: () => _exportToZip(item),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () async {
                                    await widget.db.deleteMeasurement(itemId);
                                    _selectedMeasurementIds.remove(itemId);
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
