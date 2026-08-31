import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../sql_database.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';

/// شاشة إدارة الإكسسوارات الخاصة بكل سلسلة
/// المسار: المنتجات ← إكسسوارات السلاسل
class SeriesAccessoriesScreen extends StatefulWidget {
  final SqlDatabase db;
  const SeriesAccessoriesScreen({super.key, required this.db});
  @override
  State<SeriesAccessoriesScreen> createState() => _SeriesAccessoriesScreenState();
}

class _SeriesAccessoriesScreenState extends State<SeriesAccessoriesScreen> {
  List<Map<String, dynamic>> _profiles = [];
  List<Map<String, dynamic>> _series = [];
  List<Map<String, dynamic>> _allAccessories = [];
  Map<String, dynamic>? _selectedProfile;
  Map<String, dynamic>? _selectedSeries;
  bool _loadingProfiles = true;
  bool _loadingSeries = false;
  bool _loadingAccessories = false;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  static const Color _primary = Color(0xFF1E3A5F);
  static const Color _accent = Color(0xFF2196F3);
  static const Color _linkedColor = Color(0xFF4CAF50);
  static const Color _globalColor = Color(0xFF9C27B0);

  String _withoutQualityLabel(String value) {
    return value
        .replaceAll(
          RegExp(
            r'\s*\(\s*(?:جودة\s+(?:رفيعة|قياسية|تجارية)|qualité\s+(?:haute|standard|commerciale)|(?:premium|standard|commercial)\s+quality)\s*\)',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  }

  String _visibleType(String value) {
    return _withoutQualityLabel(value.split('|').first.trim());
  }

  @override
  void initState() { super.initState(); _loadProfiles(); }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _loadProfiles() async {
    setState(() => _loadingProfiles = true);
    final p = await widget.db.readProfile();
    setState(() { _profiles = p; _loadingProfiles = false; });
  }

  Future<void> _selectProfile(Map<String, dynamic> profile) async {
    setState(() {
      _selectedProfile = profile; _selectedSeries = null;
      _series = []; _allAccessories = []; _loadingSeries = true;
    });
    final s = await widget.db.readSeriesByProfile(profile['id'] as int);
    setState(() { _series = s; _loadingSeries = false; });
  }

  Future<void> _selectSeries(Map<String, dynamic> series) async {
    setState(() { _selectedSeries = series; _allAccessories = []; _loadingAccessories = true; });
    final all = await widget.db.readAccessories();
    final allJoints = await widget.db.readJoints();

    final List<Map<String, dynamic>> combined = [];
    for (var a in all) {
      combined.add(Map<String, dynamic>.from(a)..['isJoint'] = false);
    }
    for (var j in allJoints) {
      combined.add(Map<String, dynamic>.from(j)
        ..['isJoint'] = true
        ..['price'] = j['price_per_meter']
        ..['material_type'] = j['type']);
    }

    final pt = (_selectedProfile?['type'] ?? 'Aluminium').toString().toLowerCase();
    final filtered = combined.where((a) {
      final mt = (a['material_type'] ?? 'Aluminium').toString().toLowerCase();
      return pt == 'pvc' ? mt == 'pvc' : (mt == 'aluminium' || mt == '' || mt == 'null' || mt == 'aluminum');
    }).toList();
    setState(() { _allAccessories = filtered; _loadingAccessories = false; });
  }

  bool _isGlobal(Map<String, dynamic> a) {
    if (a['isJoint'] == true) return false;
    return (a['scope'] ?? 'Global').toString() == 'Global';
  }

  bool _isLinked(Map<String, dynamic> a) {
    final sid = _selectedSeries?['id'] as int?;
    if (sid == null) return false;
    if (_isGlobal(a)) return true;
    final s = (a['series_ids'] ?? '').toString();
    if (s.isEmpty) return false;
    return s.split(',').map((e) => int.tryParse(e.trim())).contains(sid);
  }

  Future<void> _toggleLink(Map<String, dynamic> acc, AppLanguage lang) async {
    final sid = _selectedSeries?['id'] as int?;
    if (sid == null || _isGlobal(acc)) return;
    final idsStr = (acc['series_ids'] ?? '').toString();
    final ids = idsStr.isEmpty ? <int>[] : idsStr.split(',').map((e) => int.tryParse(e.trim())).whereType<int>().toList();
    final wasLinked = ids.contains(sid);
    wasLinked ? ids.remove(sid) : ids.add(sid);
    final newIds = ids.join(',');
    final newScope = newIds.isEmpty ? 'Global' : 'Unique';

    final isJ = acc['isJoint'] == true;
    if (isJ) {
      final dbInstance = await widget.db.db;
      await dbInstance!.update(
        'Joints',
        {
          'series_ids': newIds.isEmpty ? null : newIds,
          'scope': newScope,
        },
        where: 'id = ?',
        whereArgs: [acc['id'] as int],
      );
    } else {
      await widget.db.updateAccessory(acc['id'] as int, {
        'series_ids': newIds.isEmpty ? null : newIds,
        'scope': newScope,
      });
    }

    setState(() {
      final idx = _allAccessories.indexWhere((a) => a['id'] == acc['id'] && a['isJoint'] == isJ);
      if (idx != -1) {
        _allAccessories[idx] = Map<String, dynamic>.from(_allAccessories[idx])
          ..['series_ids'] = newIds.isEmpty ? null : newIds
          ..['scope'] = newScope;
      }
    });
    if (mounted) {
      final msg = wasLinked 
          ? '${Localization.translate('تم فك ربط', lang)} "${acc['name']}"' 
          : '${Localization.translate('تم ربط', lang)} "${acc['name']}" ${Localization.translate('بهذه السلسلة', lang)}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: GoogleFonts.cairo()),
        backgroundColor: wasLinked ? Colors.orange : _linkedColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_searchQuery.isEmpty) return _allAccessories;
    return _allAccessories.where((a) {
      return (a['name'] ?? '').toString().toLowerCase().contains(_searchQuery) ||
             (a['type'] ?? '').toString().toLowerCase().contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final isRtl = lang == AppLanguage.arabic;

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          backgroundColor: _primary, foregroundColor: Colors.white, elevation: 0,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(Localization.translate('إكسسوارات السلاسل', lang), style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white)),
            if (_selectedProfile != null && _selectedSeries != null)
              Text('${_selectedProfile!['name']} ← ${_selectedSeries!['name']}', style: GoogleFonts.cairo(fontSize: 11, color: Colors.white70)),
          ]),
          bottom: PreferredSize(preferredSize: const Size.fromHeight(3),
            child: Container(height: 3, decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_accent, Color(0x002196F3)])))),
        ),
        body: _loadingProfiles
            ? const Center(child: CircularProgressIndicator())
            : Column(children: [
                _profileBar(lang),
                if (_selectedProfile != null) _seriesBar(lang),
                if (_selectedSeries != null) _searchBar(lang),
                Expanded(child: _body(lang)),
              ]),
      ),
    );
  }

  Widget _profileBar(AppLanguage lang) {
    return Container(
      color: _primary,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(Localization.translate('اختر البروفيل', lang), style: GoogleFonts.cairo(color: Colors.white70, fontSize: 11)),
        const SizedBox(height: 8),
        SizedBox(height: 42, child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _profiles.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final p = _profiles[i];
            final sel = _selectedProfile?['id'] == p['id'];
            return GestureDetector(onTap: () => _selectProfile(p),
              child: AnimatedContainer(duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: sel ? Colors.white : Colors.white.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(21),
                  border: Border.all(color: sel ? Colors.white : Colors.white.withValues(alpha: 0.3))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.format_shapes_rounded, size: 14, color: sel ? _primary : Colors.white),
                  const SizedBox(width: 6),
                  Text(p['name'] ?? '', style: GoogleFonts.cairo(fontSize: 12, fontWeight: sel ? FontWeight.bold : FontWeight.normal, color: sel ? _primary : Colors.white)),
                  const SizedBox(width: 5),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: sel ? _primary.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(7)),
                    child: Text(p['type'] ?? '', style: GoogleFonts.cairo(fontSize: 9, color: sel ? _primary : Colors.white70))),
                ]),
              ),
            );
          },
        )),
      ]),
    );
  }

  Widget _seriesBar(AppLanguage lang) {
    if (_loadingSeries) return Container(height: 54, color: const Color(0xFFDCE7F3),
      child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _accent))));
    if (_series.isEmpty) return Container(height: 46, color: const Color(0xFFDCE7F3),
      child: Center(child: Text(Localization.translate('لا توجد سلاسل', lang), style: GoogleFonts.cairo(color: Colors.grey.shade600, fontSize: 12))));
    return Container(color: const Color(0xFFDCE7F3), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: SizedBox(height: 34, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _series.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final s = _series[i];
          final sel = _selectedSeries?['id'] == s['id'];
          return GestureDetector(onTap: () => _selectSeries(s),
            child: AnimatedContainer(duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
              decoration: BoxDecoration(
                color: sel ? _accent : Colors.white,
                borderRadius: BorderRadius.circular(17),
                boxShadow: sel ? [BoxShadow(color: _accent.withValues(alpha: 0.35), blurRadius: 5, offset: const Offset(0, 2))] : null,
                border: Border.all(color: sel ? _accent : Colors.grey.shade300)),
              child: Text(s['name'] ?? '', style: GoogleFonts.cairo(fontSize: 12, fontWeight: sel ? FontWeight.bold : FontWeight.normal, color: sel ? Colors.white : Colors.black87)),
            ),
          );
        },
      )),
    );
  }

  Widget _searchBar(AppLanguage lang) {
    return Container(color: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
        decoration: InputDecoration(
          hintText: Localization.translate('ابحث عن إكسسوار...', lang), hintStyle: GoogleFonts.cairo(fontSize: 13, color: Colors.grey),
          prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
          suffixIcon: _searchQuery.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 18),
            onPressed: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); }) : null,
          filled: true, fillColor: const Color(0xFFF5F7FA),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none)),
        style: GoogleFonts.cairo(fontSize: 13),
      ),
    );
  }

  Widget _body(AppLanguage lang) {
    if (_selectedProfile == null) return _empty(Icons.format_shapes_outlined, Localization.translate('اختر بروفيلاً', lang), Localization.translate('حدد البروفيل من الشريط العلوي', lang));
    if (_selectedSeries == null) return _empty(Icons.category_outlined, Localization.translate('اختر سلسلة', lang), '${Localization.translate('حدد إحدى سلاسل', lang)} "${_selectedProfile!['name']}"');
    if (_loadingAccessories) return const Center(child: CircularProgressIndicator(color: _accent));
    if (_allAccessories.isEmpty) return _empty(Icons.construction_outlined, Localization.translate('لا توجد إكسسوارات', lang), Localization.translate('لا توجد إكسسوارات مطابقة لنوع مادة هذا البروفيل', lang));

    final f = _filtered;
    final linked = f.where(_isLinked).toList();
    final unlinked = f.where((a) => !_isLinked(a)).toList();

    return ListView(padding: const EdgeInsets.all(16), children: [
      _banner(linked.length, unlinked.length, lang),
      const SizedBox(height: 16),
      if (linked.isNotEmpty) ...[
        _secHeader(Localization.translate('الإكسسوارات المرتبطة', lang), linked.length, _linkedColor, Icons.link_rounded),
        const SizedBox(height: 8),
        ...linked.map((a) => _card(a, lang)),
        const SizedBox(height: 18),
      ],
      if (unlinked.isNotEmpty) ...[
        _secHeader(Localization.translate('غير مرتبطة بهذه السلسلة', lang), unlinked.length, Colors.grey, Icons.link_off_rounded),
        const SizedBox(height: 8),
        ...unlinked.map((a) => _card(a, lang)),
      ],
      if (linked.isEmpty && unlinked.isEmpty) _empty(Icons.search_off_rounded, Localization.translate('لا نتائج', lang), Localization.translate('جرّب كلمة بحث أخرى', lang)),
      const SizedBox(height: 40),
    ]);
  }

  Widget _banner(int linkedCount, int unlinkedCount, AppLanguage lang) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1E3A5F), Color(0xFF1565C0)]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: const Color(0xFF1E3A5F).withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))]),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_selectedSeries?['name'] ?? '', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 3),
          Text('${_selectedProfile?['name'] ?? ''} · ${_selectedProfile?['type'] ?? ''}', style: GoogleFonts.cairo(color: Colors.white70, fontSize: 11)),
        ])),
        _badge(linkedCount, Localization.translate('مرتبط', lang), _linkedColor),
        const SizedBox(width: 10),
        _badge(unlinkedCount, Localization.translate('غير مرتبط', lang), Colors.white38),
      ]),
    );
  }

  Widget _badge(int n, String label, Color color) => Column(children: [
    Container(width: 44, height: 44,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.2), shape: BoxShape.circle, border: Border.all(color: color, width: 2)),
      child: Center(child: Text('$n', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)))),
    const SizedBox(height: 4),
    Text(label, style: GoogleFonts.cairo(color: Colors.white70, fontSize: 9)),
  ]);

  Widget _secHeader(String title, int count, Color color, IconData icon) {
    return Row(children: [
      Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 16)),
      const SizedBox(width: 8),
      Text(title, style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
      const SizedBox(width: 8),
      Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
        child: Text('$count', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: color))),
    ]);
  }

  Widget _card(Map<String, dynamic> acc, AppLanguage lang) {
    final linked = _isLinked(acc);
    final global = _isGlobal(acc);
    final type = (acc['type'] ?? '').toString();
    final price = (acc['price'] as num?)?.toDouble() ?? 0.0;
    final screwCount = (acc['screw_count'] as num?)?.toInt() ?? 0;
    final Color sc = global ? _globalColor : (linked ? _linkedColor : Colors.grey);

    return Container(margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13),
        border: Border.all(color: linked ? sc.withValues(alpha: 0.3) : Colors.grey.shade200, width: linked ? 1.5 : 1),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 7, offset: const Offset(0, 2))]),
      child: Padding(padding: const EdgeInsets.all(11), child: Row(children: [
        Container(width: 44, height: 44,
          decoration: BoxDecoration(color: sc.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(11)),
          child: Icon(_typeIcon(acc), color: sc, size: 21)),
        const SizedBox(width: 11),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_withoutQualityLabel('${acc['name'] ?? ''}'), style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
          const SizedBox(height: 4),
          Wrap(spacing: 5, runSpacing: 3, children: [
            if (acc['isJoint'] == true)
              _chip(Localization.translate('جوان', lang), Colors.purple.shade50, Colors.purple.shade700)
            else
              _chip(Localization.translate(_visibleType(type), lang), Colors.blue.shade50, Colors.blue.shade700),
            _chip('${price.toStringAsFixed(0)} دج', Colors.green.shade50, Colors.green.shade700),
            if (acc['isJoint'] == true && (acc['thickness'] as num?) != null && (acc['thickness'] as num) > 0)
              _chip('${acc['thickness']} مم', Colors.teal.shade50, Colors.teal.shade700),
            if (screwCount > 0) _chip('$screwCount ${Localization.translate('برغي', lang)}', Colors.orange.shade50, Colors.orange.shade700),
            _chip(global ? Localization.translate('عام', lang) : (linked ? Localization.translate('مرتبط', lang) : Localization.translate('غير مرتبط', lang)), sc.withValues(alpha: 0.1), sc,
              icon: global ? Icons.public_rounded : (linked ? Icons.link_rounded : Icons.link_off_rounded)),
          ]),
        ])),
        const SizedBox(width: 8),
        global ? _globalBadge(lang) : (isAdmin ? _toggleBtn(acc, linked, sc, lang) : const SizedBox()),
      ])),
    );
  }

  Widget _chip(String label, Color bg, Color fg, {IconData? icon}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(7)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[Icon(icon, size: 10, color: fg), const SizedBox(width: 2)],
      Text(label, style: GoogleFonts.cairo(fontSize: 10, color: fg, fontWeight: FontWeight.w600)),
    ]));

  Widget _globalBadge(AppLanguage lang) => Tooltip(message: Localization.translate('إكسسوار عام – يظهر في كل السلاسل تلقائياً', lang),
    child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: _globalColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _globalColor.withValues(alpha: 0.3), width: 1)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.public_rounded, color: _globalColor, size: 14),
        const SizedBox(width: 4),
        Text(Localization.translate('عام', lang), style: GoogleFonts.cairo(color: _globalColor, fontSize: 11, fontWeight: FontWeight.bold)),
      ])));

  Widget _toggleBtn(Map<String, dynamic> acc, bool linked, Color color, AppLanguage lang) => GestureDetector(
    onTap: () => _toggleLink(acc, lang),
    child: AnimatedContainer(duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(color: linked ? color : Colors.grey.shade100, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: linked ? color : Colors.grey.shade300, width: 1.2)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(linked ? Icons.link_off_rounded : Icons.add_link_rounded, size: 14, color: linked ? Colors.white : Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(linked ? Localization.translate('فك', lang) : Localization.translate('ربط', lang), style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: linked ? Colors.white : linked ? Colors.white : Colors.grey.shade700)),
      ])));

  Widget _empty(IconData icon, String title, String sub) => Center(child: Padding(padding: const EdgeInsets.all(32),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(width: 86, height: 86, decoration: BoxDecoration(color: _accent.withValues(alpha: 0.07), shape: BoxShape.circle),
        child: Icon(icon, size: 42, color: _accent.withValues(alpha: 0.5))),
      const SizedBox(height: 18),
      Text(title, textAlign: TextAlign.center, style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
      const SizedBox(height: 6),
      Text(sub, textAlign: TextAlign.center, style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade600)),
    ])));

  IconData _typeIcon(Map<String, dynamic> acc) {
    if (acc['isJoint'] == true) return Icons.blur_linear_rounded;
    final String type = (acc['type'] ?? '').toString();
    final t = type.toLowerCase();
    if (t.contains('serrure') || t.contains('lock') || t.contains('قفل')) return Icons.lock_rounded;
    if (t.contains('poignee') || t.contains('مقبض') || t.contains('handle')) return Icons.back_hand_rounded;
    if (t.contains('charniere') || t.contains('hinge') || t.contains('مفصل')) return Icons.pivot_table_chart_rounded;
    if (t.contains('joint')) return Icons.horizontal_rule_rounded;
    if (t.contains('vis') || t.contains('screw') || t.contains('برغي')) return Icons.hardware_rounded;
    if (t.contains('gache')) return Icons.settings_input_component_rounded;
    if (t.contains('fermeture') || t.contains('closure')) return Icons.close_fullscreen_rounded;
    return Icons.construction_rounded;
  }
}
