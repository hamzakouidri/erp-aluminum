import 'package:database_data/widgets/app_material.dart';
import 'package:provider/provider.dart';

import '../settings/app_settings.dart';
import '../sql_database.dart';
import '../widgets/section_image.dart';

/// Compatibility groups of a series: sets of profiles that fit together
/// (frames with or without side cover, mullions...). The profiles offered
/// are the series' own and those shared with it from another series.
class ProfileCompatibilityGroupsView extends StatefulWidget {
  const ProfileCompatibilityGroupsView({
    super.key,
    required this.db,
    required this.seriesId,
    required this.seriesName,
    required this.canEdit,
    this.header = const [],
  });

  final SqlDatabase db;
  final int? seriesId;
  final String seriesName;
  final bool canEdit;

  /// Widgets shown above the groups (the profile and series selectors).
  final List<Widget> header;

  @override
  State<ProfileCompatibilityGroupsView> createState() =>
      _ProfileCompatibilityGroupsViewState();
}

class _ProfileCompatibilityGroupsViewState
    extends State<ProfileCompatibilityGroupsView> {
  bool _loading = false;
  List<Map<String, dynamic>> _sections = [];
  List<Map<String, dynamic>> _groups = [];

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
  void didUpdateWidget(covariant ProfileCompatibilityGroupsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seriesId != widget.seriesId) _load();
  }

  Future<void> _load() async {
    final seriesId = widget.seriesId;
    if (seriesId == null) {
      setState(() {
        _sections = [];
        _groups = [];
      });
      return;
    }
    setState(() => _loading = true);
    final sections = await widget.db.readAvailableSectionsBySeries(seriesId);
    final groups = await widget.db.readProfileCompatibilityGroups(seriesId);
    if (!mounted || widget.seriesId != seriesId) return;
    setState(() {
      _sections = sections;
      _groups = groups;
      _loading = false;
    });
  }

  int? _id(Map<String, dynamic> section) => (section['id'] as num?)?.toInt();

  bool _flag(Map<String, dynamic> section, String key) {
    final value = section[key];
    return value == true || value == 1 || value?.toString() == '1';
  }

  /// The kind of profile shown beside its name.
  String _kind(Map<String, dynamic> section) {
    final type = (section['type'] ?? '').toString().toLowerCase();
    if (_flag(section, 'is_frame') ||
        type == 'frame' ||
        type.contains('cadre') ||
        type.contains('dormant')) {
      return _tr('إطار', 'Dormant', 'Frame');
    }
    if (_flag(section, 'is_mullion') ||
        type.contains('mullion') ||
        type.contains('meneau')) {
      return _tr('تقسيم', 'Meneau', 'Mullion');
    }
    if (_flag(section, 'is_sash') ||
        type.contains('sash') ||
        type.contains('ouvrant')) {
      return _tr('ضلفة', 'Ouvrant', 'Sash');
    }
    return (section['type'] ?? '').toString();
  }

  String _label(Map<String, dynamic> section) {
    final code = (section['code'] ?? '').toString().trim();
    final name = (section['name'] ?? '').toString().trim();
    return code.isNotEmpty ? '$code — $name' : name;
  }

  String _details(Map<String, dynamic> section) {
    final width = (section['visible_width'] as num?)?.toDouble() ?? 0;
    final shared = _flag(section, 'is_shared');
    final source = (section['source_series_name'] ?? '').toString();
    return [
      _kind(section),
      if (width > 0)
        '${_tr('العرض الظاهر', 'Largeur visible', 'Visible width')}: '
            '${width.toStringAsFixed(width % 1 == 0 ? 0 : 1)} mm',
      if (shared)
        source.isEmpty
            ? _tr('مشترك', 'Partagé', 'Shared')
            : '${_tr('مشترك من', 'Partagé depuis', 'Shared from')} $source',
    ].where((part) => part.isNotEmpty).join(' • ');
  }

  String _groupName(Map<String, dynamic> group, int index) {
    final name = (group['name'] ?? '').toString().trim();
    return name.isNotEmpty
        ? name
        : '${_tr('المجموعة', 'Groupe', 'Group')} ${index + 1}';
  }

  Future<void> _editGroup({Map<String, dynamic>? group, int? index}) async {
    final seriesId = widget.seriesId;
    if (seriesId == null) return;
    final selected = <int>{
      ...((group?['members'] as Set<int>?) ?? const <int>{}),
    };
    final nameController = TextEditingController(
      text: (group?['name'] ?? '').toString(),
    );
    final searchController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final query = searchController.text.trim().toLowerCase();
          final visible = _sections.where((section) {
            if (query.isEmpty) return true;
            return '${_label(section)} ${_details(section)}'
                .toLowerCase()
                .contains(query);
          }).toList();
          return AlertDialog(
            title: Text(
              group == null
                  ? _tr('إضافة مجموعة', 'Ajouter un groupe', 'Add group')
                  : _groupName(group, index ?? 0),
            ),
            content: SizedBox(
              width: 620,
              height: 480,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: _tr(
                        'اسم المجموعة (اختياري)',
                        'Nom du groupe (facultatif)',
                        'Group name (optional)',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: _tr('بحث', 'Rechercher', 'Search'),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_tr('المحدد', 'Sélectionnés', 'Selected')}: ${selected.length}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, i) {
                        final section = visible[i];
                        final id = _id(section);
                        return CheckboxListTile(
                          dense: true,
                          value: id != null && selected.contains(id),
                          onChanged: id == null
                              ? null
                              : (value) => setDialogState(() {
                                  value == true
                                      ? selected.add(id)
                                      : selected.remove(id);
                                }),
                          secondary: SectionImageWidget(
                            code: section['code']?.toString(),
                            name: section['name']?.toString(),
                            imagePath: section['image_path']?.toString(),
                            size: 40,
                            fallbackIcon: Icons.crop_square_rounded,
                          ),
                          title: Text(_label(section)),
                          subtitle: Text(_details(section)),
                        );
                      },
                    ),
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
                onPressed: selected.length < 2
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                child: Text(_tr('حفظ', 'Enregistrer', 'Save')),
              ),
            ],
          );
        },
      ),
    );
    final name = nameController.text;
    nameController.dispose();
    searchController.dispose();
    if (saved != true) return;
    await widget.db.saveProfileCompatibilityGroup(
      id: (group?['id'] as num?)?.toInt(),
      seriesId: seriesId,
      name: name,
      memberIds: selected,
    );
    await _load();
  }

  Future<void> _deleteGroup(Map<String, dynamic> group, int index) async {
    final id = (group['id'] as num?)?.toInt();
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_tr('حذف المجموعة', 'Supprimer le groupe', 'Delete group')),
        content: Text(_groupName(group, index)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_tr('إلغاء', 'Annuler', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_tr('حذف', 'Supprimer', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.db.deleteProfileCompatibilityGroup(id);
    await _load();
  }

  Widget _groupCard(Map<String, dynamic> group, int index) {
    final members = (group['members'] as Set<int>?) ?? const <int>{};
    final byId = {for (final s in _sections) _id(s): s};
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.link_rounded, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _groupName(group, index),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (widget.canEdit) ...[
                  IconButton(
                    tooltip: _tr('تعديل', 'Modifier', 'Edit'),
                    icon: const Icon(Icons.edit_rounded),
                    onPressed: () => _editGroup(group: group, index: index),
                  ),
                  IconButton(
                    tooltip: _tr('حذف', 'Supprimer', 'Delete'),
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => _deleteGroup(group, index),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final id in members)
                  Chip(
                    avatar: byId[id] == null
                        ? const Icon(Icons.help_outline_rounded, size: 18)
                        : SectionImageWidget(
                            code: byId[id]!['code']?.toString(),
                            name: byId[id]!['name']?.toString(),
                            imagePath: byId[id]!['image_path']?.toString(),
                            size: 22,
                            fallbackIcon: Icons.crop_square_rounded,
                          ),
                    label: Text(
                      byId[id] == null
                          ? '#$id (${_tr('غير متاح في هذه السلسلة', 'indisponible dans cette série', 'not available in this series')})'
                          : '${_label(byId[id]!)} • ${_kind(byId[id]!)}',
                    ),
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
    context.watch<AppSettingsProvider>();
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        ...widget.header,
        if (widget.seriesId == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                _tr(
                  'اختر سلسلة لعرض مجموعات التوافق.',
                  'Choisissez une série pour voir ses groupes de compatibilité.',
                  'Choose a series to see its compatibility groups.',
                ),
              ),
            ),
          )
        else if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          const SizedBox(height: 8),
          Text(
            '${_tr('مجموعات التوافق', 'Groupes de compatibilité', 'Compatibility groups')} — ${widget.seriesName}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            _tr(
              'كل مجموعة تضم بروفيلات تتوافق مع بعضها: إطارات بغطاء جانبي أو بدونه، تقسيمات... من هذه السلسلة أو مما شورك معها من سلسلة أخرى. المجموعة تضم بروفيلين أو أكثر. عند تخصيص جهات الإطار لا تظهر إلا إطارات مجموعته.',
              'Chaque groupe réunit des profils compatibles entre eux : dormants avec ou sans couvre-joint, meneaux... de cette série ou partagés depuis une autre. Un groupe compte deux profils ou plus. Pour personnaliser les côtés d\'un dormant, seuls les dormants de son groupe sont proposés.',
              'Each group holds profiles that fit together: frames with or without side cover, mullions... from this series or shared with it from another. A group has two profiles or more. When customizing frame sides, only the frames of its group are offered.',
            ),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 10),
          if (widget.canEdit)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                onPressed: _sections.length < 2 ? null : () => _editGroup(),
                icon: const Icon(Icons.add_rounded),
                label: Text(
                  _tr('إضافة مجموعة', 'Ajouter un groupe', 'Add group'),
                ),
              ),
            ),
          const SizedBox(height: 10),
          if (_groups.isEmpty)
            Text(
              _tr(
                'لا توجد مجموعات بعد.',
                'Aucun groupe pour le moment.',
                'No groups yet.',
              ),
            )
          else
            for (var i = 0; i < _groups.length; i++) _groupCard(_groups[i], i),
        ],
      ],
    );
  }
}
