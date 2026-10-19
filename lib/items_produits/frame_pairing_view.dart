import 'package:database_data/widgets/app_material.dart';
import 'package:provider/provider.dart';

import '../settings/app_settings.dart';
import '../sql_database.dart';
import '../widgets/section_image.dart';

/// Frame pairing of a series, set by hand: for each frame, the frame cut on
/// its sides without a cover, the frame cut against a corner profile and the
/// frames it may be joined to. The drawing and the quantity tables follow
/// only these choices; nothing is guessed.
class FramePairingView extends StatefulWidget {
  const FramePairingView({
    super.key,
    required this.db,
    required this.seriesId,
    required this.canEdit,
    this.header = const [],
  });

  final SqlDatabase db;
  final int? seriesId;
  final bool canEdit;

  /// Widgets shown above the frames (the profile and series selectors).
  final List<Widget> header;

  @override
  State<FramePairingView> createState() => _FramePairingViewState();
}

class _FramePairingViewState extends State<FramePairingView> {
  bool _loading = false;
  List<Map<String, dynamic>> _frames = [];
  Map<int, Map<String, dynamic>> _pairings = {};

  String _tr(String ar, String fr, String en) =>
      switch (context.read<AppSettingsProvider>().language) {
        AppLanguage.french => fr,
        AppLanguage.english => en,
        AppLanguage.arabic => ar,
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FramePairingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seriesId != widget.seriesId) _load();
  }

  static int? _int(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

  bool _isFrame(Map<String, dynamic> section) {
    final type = (section['type'] ?? '').toString().toLowerCase();
    final flag = section['is_frame'];
    return flag == true ||
        flag == 1 ||
        type == 'frame' ||
        type.contains('cadre') ||
        type.contains('dormant');
  }

  Future<void> _load() async {
    final seriesId = widget.seriesId;
    if (seriesId == null) {
      setState(() {
        _frames = [];
        _pairings = {};
      });
      return;
    }
    setState(() => _loading = true);
    final sections = await widget.db.readAvailableSectionsBySeries(seriesId);
    final pairings = await widget.db.readFramePairings();
    if (!mounted || widget.seriesId != seriesId) return;
    setState(() {
      _frames = sections.where(_isFrame).toList();
      _pairings = pairings;
      _loading = false;
    });
  }

  Map<String, dynamic>? _frameById(int? id) {
    if (id == null) return null;
    for (final frame in _frames) {
      if (_int(frame['id']) == id) return frame;
    }
    return null;
  }

  bool _hasIntegratedCover(Map<String, dynamic> frame) {
    final width = (frame['couvre_joint_width'] as num?)?.toDouble() ?? 0;
    return width > 0;
  }

  String _label(Map<String, dynamic> frame) {
    final code = (frame['code'] ?? '').toString().trim();
    final name = (frame['name'] ?? '').toString().trim();
    return code.isNotEmpty ? '$code — $name' : name;
  }

  String _details(Map<String, dynamic> frame) {
    final width = (frame['visible_width'] as num?)?.toDouble() ?? 0;
    final source = (frame['source_series_name'] ?? '').toString();
    final shared = frame['is_shared'] == 1 || frame['is_shared'] == true;
    return [
      _hasIntegratedCover(frame)
          ? _tr('بغطاء مدمج', 'Avec couvre-joint', 'Integrated cover')
          : _tr('بدون غطاء مدمج', 'Sans couvre-joint', 'No integrated cover'),
      if (width > 0)
        '${_tr('العرض الظاهر', 'Largeur visible', 'Visible width')}: '
            '${width.toStringAsFixed(width % 1 == 0 ? 0 : 1)} mm',
      if (shared && source.isNotEmpty)
        '${_tr('مشترك من', 'Partagé depuis', 'Shared from')} $source',
    ].join(' • ');
  }

  Set<int> _joins(int frameId) => (_pairings[frameId]?['join_ids'] ?? '')
      .toString()
      .split(',')
      .map((part) => int.tryParse(part.trim()))
      .whereType<int>()
      .toSet();

  Future<void> _save(
    int frameId, {
    int? noCover,
    int? corner,
    Set<int>? joins,
    bool clearNoCover = false,
    bool clearCorner = false,
  }) async {
    final current = _pairings[frameId] ?? const <String, dynamic>{};
    final nextNoCover = clearNoCover
        ? null
        : (noCover ?? _int(current['no_cover_frame_id']));
    final nextCorner = clearCorner
        ? null
        : (corner ?? _int(current['corner_frame_id']));
    final nextJoins = joins ?? _joins(frameId);
    await widget.db.saveFramePairing(
      sectionId: frameId,
      noCoverFrameId: nextNoCover,
      cornerFrameId: nextCorner,
      joinIds: nextJoins,
    );
    if (!mounted) return;
    setState(() {
      _pairings[frameId] = {
        'section_id': frameId,
        'no_cover_frame_id': nextNoCover,
        'corner_frame_id': nextCorner,
        'join_ids': nextJoins.join(','),
      };
    });
  }

  Widget _framePicker({
    required String label,
    required int? value,
    required List<Map<String, dynamic>> options,
    required ValueChanged<int?> onChanged,
  }) {
    final known = value != null && options.any((o) => _int(o['id']) == value);
    return DropdownButtonFormField<int?>(
      initialValue: known ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        DropdownMenuItem<int?>(
          value: null,
          child: Text(
            _tr('غير محدد', 'Non défini', 'Not set'),
            style: const TextStyle(color: Colors.grey),
          ),
        ),
        for (final option in options)
          DropdownMenuItem<int?>(
            value: _int(option['id']),
            child: Text(_label(option), overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: widget.canEdit ? onChanged : null,
    );
  }

  Future<void> _editJoins(Map<String, dynamic> frame) async {
    final frameId = _int(frame['id']);
    if (frameId == null) return;
    final selected = {..._joins(frameId)};
    final others = _frames.where((f) => _int(f['id']) != frameId).toList();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            '${_tr('الإطارات التي يلتصق بها', 'Dormants accolables', 'Frames it joins')}: ${_label(frame)}',
          ),
          content: SizedBox(
            width: 560,
            height: 420,
            child: others.isEmpty
                ? Center(
                    child: Text(
                      _tr(
                        'لا توجد إطارات أخرى في هذه السلسلة',
                        'Aucun autre dormant dans cette série',
                        'No other frame in this series',
                      ),
                    ),
                  )
                : ListView(
                    children: [
                      for (final other in others)
                        CheckboxListTile(
                          value: selected.contains(_int(other['id'])),
                          title: Text(_label(other)),
                          subtitle: Text(_details(other)),
                          onChanged: (checked) => setDialogState(() {
                            final id = _int(other['id']);
                            if (id == null) return;
                            if (checked == true) {
                              selected.add(id);
                            } else {
                              selected.remove(id);
                            }
                          }),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_tr('إلغاء', 'Annuler', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(_tr('حفظ', 'Enregistrer', 'Save')),
            ),
          ],
        ),
      ),
    );
    if (saved == true) await _save(frameId, joins: selected);
  }

  Widget _frameCard(Map<String, dynamic> frame) {
    final frameId = _int(frame['id'])!;
    final pairing = _pairings[frameId];
    final noCoverId = _int(pairing?['no_cover_frame_id']);
    final cornerId = _int(pairing?['corner_frame_id']);
    final joins = _joins(frameId);
    final hasCover = _hasIntegratedCover(frame);
    final noCoverOptions = _frames
        .where((f) => _int(f['id']) != frameId && !_hasIntegratedCover(f))
        .toList();
    final cornerOptions = _frames.where((f) => !_hasIntegratedCover(f)).toList();
    final missingCorner = cornerId == null;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SectionImageWidget(
                  code: (frame['code'] ?? '').toString(),
                  name: (frame['name'] ?? '').toString(),
                  imagePath: frame['image_path']?.toString(),
                  size: 40,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _label(frame),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        _details(frame),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (missingCorner)
                  Tooltip(
                    message: _tr(
                      'بدون إطار جهة بروفيل الزاوية لا يمكن تفعيل بروفيل الزاوية مع هذا الإطار',
                      "Sans dormant côté profil d'angle, le profil d'angle ne peut pas être activé avec ce dormant",
                      'Without a frame against the corner profile, the corner profile cannot be switched on with this frame',
                    ),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange.shade700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final noCoverPicker = hasCover
                    ? _framePicker(
                        label: _tr(
                          'إطار الجهات بدون غطاء',
                          'Dormant des côtés sans couvre-joint',
                          'Frame for sides without cover',
                        ),
                        value: noCoverId,
                        options: noCoverOptions,
                        onChanged: (id) => _save(
                          frameId,
                          noCover: id,
                          clearNoCover: id == null,
                        ),
                      )
                    : Text(
                        _tr(
                          'إطار بدون غطاء مدمج: لا يحتاج إطاراً للجهات بدون غطاء',
                          'Dormant sans couvre-joint : pas de dormant pour les côtés sans couvre-joint',
                          'Frame without integrated cover: no frame needed for sides without cover',
                        ),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      );
                final cornerPicker = _framePicker(
                  label: _tr(
                    'إطار جهة بروفيل الزاوية',
                    "Dormant côté profil d'angle",
                    'Frame against the corner profile',
                  ),
                  value: cornerId,
                  options: cornerOptions,
                  onChanged: (id) =>
                      _save(frameId, corner: id, clearCorner: id == null),
                );
                if (constraints.maxWidth < 560) {
                  return Column(
                    children: [
                      noCoverPicker,
                      const SizedBox(height: 10),
                      cornerPicker,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: noCoverPicker),
                    const SizedBox(width: 12),
                    Expanded(child: cornerPicker),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${_tr('يلتصق بـ', 'Accolable à', 'Joins')}:',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (joins.isEmpty)
                        Text(
                          _tr(
                            'نفسه فقط',
                            'Lui-même seulement',
                            'Itself only',
                          ),
                          style: const TextStyle(color: Colors.grey),
                        ),
                      for (final id in joins)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            _frameById(id) == null
                                ? '#$id'
                                : _label(_frameById(id)!),
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                ),
                if (widget.canEdit)
                  TextButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(_tr('تعديل', 'Modifier', 'Edit')),
                    onPressed: () => _editJoins(frame),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ...widget.header,
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
          ),
          child: Text(
            _tr(
              'حدد لكل إطار: الإطار الذي يُقطع في جهاته بدون غطاء، والإطار الذي يُقطع بجانب بروفيل الزاوية، والإطارات التي يلتصق بها. التطبيق يتبع هذه الاختيارات فقط ولا يخمّن.',
              "Pour chaque dormant, choisissez le dormant coupé sur ses côtés sans couvre-joint, celui coupé contre le profil d'angle, et les dormants auxquels il s'accole. L'application suit uniquement ces choix, sans rien deviner.",
              'For each frame, choose the frame cut on its sides without cover, the frame cut against the corner profile, and the frames it joins. The app follows only these choices and guesses nothing.',
            ),
            style: const TextStyle(fontSize: 12.5),
          ),
        ),
        const SizedBox(height: 8),
        if (widget.seriesId == null)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                _tr('اختر سلسلة', 'Choisissez une série', 'Choose a series'),
              ),
            ),
          )
        else if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_frames.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                _tr(
                  'لا توجد إطارات في هذه السلسلة',
                  'Aucun dormant dans cette série',
                  'No frame in this series',
                ),
              ),
            ),
          )
        else
          for (final frame in _frames)
            if (_int(frame['id']) != null) _frameCard(frame),
      ],
    );
  }
}
