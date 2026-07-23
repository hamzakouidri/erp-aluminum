
import 'package:flutter/material.dart';
import '../../widgets/section_image.dart';
import '../../sql_database.dart';

class ProfileSelectorDialog extends StatefulWidget {
  final String profileType; // مثلاً 'Cadre'
  final String category; // 'profile', 'accessory', 'shutter'
  final int? seriesId;
  final String? materialType;
  final double? windowHeight;
  final double? targetSize;
  final int? bladeId;

  const ProfileSelectorDialog({
    super.key,
    required this.profileType,
    this.category = 'profile',
    this.seriesId,
    this.materialType,
    this.windowHeight,
    this.targetSize,
    this.bladeId,
  });

  @override
  _ProfileSelectorDialogState createState() => _ProfileSelectorDialogState();
}

class _ProfileSelectorDialogState extends State<ProfileSelectorDialog> {
  List<Map<String, dynamic>> profiles = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    final db = SqlDatabase();
    List<Map<String, dynamic>> data = [];

    // Fetch active series name first so it is available globally in _loadProfiles
    String activeSeriesName = '';
    final myDbInstance = await db.db;
    if (myDbInstance != null && widget.seriesId != null) {
      try {
        final sRes = await myDbInstance.query(
          'Series',
          columns: ['name'],
          where: 'id = ?',
          whereArgs: [widget.seriesId],
          limit: 1,
        );
        if (sRes.isNotEmpty) {
          activeSeriesName = (sRes.first['name'] ?? '').toString().toLowerCase();
        }
      } catch (_) {}
    }

    if (widget.category == 'accessory' || widget.category == 'other') {
      final myDb = myDbInstance;
      if (myDb != null) {

        // دالة مساعدة للاستعلام الذكي عن الإكسسوارات
        // القاعدة: إذا حُدِّدت سلاسل لإكسسوار → يظهر فقط في تلك السلاسل
        //          إذا لم تُحدَّد أي سلسلة → يظهر في كل السلاسل (عام)
        Future<List<Map<String, dynamic>>> queryAccessories(String customWhere, List<dynamic> baseArgs) async {
          List<dynamic> args = List.from(baseArgs);
          String where = customWhere;

          if (widget.seriesId != null) {
            // يظهر إذا:
            // (أ) series_id = السلسلة الحالية
            // (ب) series_ids يحتوي السلسلة الحالية
            // (ج) لا توجد أي سلسلة محددة (series_id IS NULL أو 0) ولا series_ids محددة → عام حقيقي
            where += ' AND ('
                'series_id = ? '
                'OR (series_ids IS NOT NULL AND series_ids != \'\' AND \',\' || series_ids || \',\' LIKE ?) '
                'OR ((series_id IS NULL OR series_id = 0) AND (series_ids IS NULL OR series_ids = \'\'))'
                ')';
            args.add(widget.seriesId);
            args.add('%,' + widget.seriesId.toString() + ',%');
          }

          if (widget.materialType != null) {
            final mat = widget.materialType!.toLowerCase().trim();
            if (mat == 'pvc') {
              // PVC: يظهر فقط ما هو pvc أو both. الـ NULL/فارغ = ألمنيوم بالافتراضي → لا يظهر في PVC
              where += " AND (LOWER(material_type) = 'pvc' OR LOWER(material_type) = 'both')";
            } else {
              // Aluminium: يظهر ما هو aluminium أو both أو NULL/فارغ (الافتراضي = ألمنيوم)
              where += " AND (LOWER(material_type) = 'aluminium' OR LOWER(material_type) = 'aluminum' OR LOWER(material_type) = 'both' OR material_type IS NULL OR material_type = '')";
            }
          }

          String? orderBy;
          if (widget.seriesId != null) {
            final sid = widget.seriesId;
            orderBy = 'CASE WHEN series_id = $sid OR (series_ids IS NOT NULL AND series_ids != \'\' AND \',\' || series_ids || \',\' LIKE \'%,$sid,%\') THEN 0 ELSE 1 END ASC, id ASC';
          }

          final rawRows = await myDb.query('Accessories', where: where, whereArgs: args, orderBy: orderBy);

          return rawRows.where((a) {
            final n = a['name'].toString().toLowerCase();
            final ty = (a['type'] ?? '').toString().toLowerCase();

            // 1. Material Exclusions
            final mat = (widget.materialType ?? '').toLowerCase().trim();
            if (mat == 'pvc') {
              if (n.contains('aluminium') || n.contains('aluminum') || n.contains('alu') || n.contains('ألمنيوم') ||
                  ty.contains('aluminium') || ty.contains('aluminum') || ty.contains('alu') || ty.contains('ألمنيوم')) {
                return false;
              }
            } else { // Aluminium
              if (n.contains('pvc') || ty.contains('pvc') ||
                  n.contains('clan') || ty.contains('clan') ||
                  n.contains('clane') || ty.contains('clane') ||
                  n.contains('كلان') || ty.contains('كلان')) {
                return false;
              }
            }

            // 2. Series Name Exclusions
            if (activeSeriesName.isNotEmpty) {
              final sName = activeSeriesName;
              if (sName.contains('67000') || sName.contains('67')) {
                if (n.contains('76000') || n.contains('76') || ty.contains('76000') || ty.contains('76') ||
                    n.contains('60000') || n.contains('60') || ty.contains('60000') || ty.contains('60') ||
                    n.contains('52000') || n.contains('52') || ty.contains('52000') || ty.contains('52') ||
                    n.contains('45000') || n.contains('45') || ty.contains('45000') || ty.contains('45')) {
                  return false;
                }
              } else if (sName.contains('76000') || sName.contains('76')) {
                if (n.contains('67000') || n.contains('67') || ty.contains('67000') || ty.contains('67') ||
                    n.contains('60000') || n.contains('60') || ty.contains('60000') || ty.contains('60') ||
                    n.contains('52000') || n.contains('52') || ty.contains('52000') || ty.contains('52') ||
                    n.contains('45000') || n.contains('45') || ty.contains('45000') || ty.contains('45')) {
                  return false;
                }
              } else if (sName.contains('60000') || sName.contains('60')) {
                if (n.contains('67000') || n.contains('67') || ty.contains('67000') || ty.contains('67') ||
                    n.contains('76000') || n.contains('76') || ty.contains('76000') || ty.contains('76') ||
                    n.contains('52000') || n.contains('52') || ty.contains('52000') || ty.contains('52') ||
                    n.contains('45000') || n.contains('45') || ty.contains('45000') || ty.contains('45')) {
                  return false;
                }
              }

              // 3. System Mode (Sliding vs Opening) Exclusions
              final isSliding = sName.contains('67000') || sName.contains('76000') || sName.contains('67') || sName.contains('76');
              if (isSliding) {
                if (n.contains('paumelle') || ty.contains('paumelle') ||
                    n.contains('mifsal') || ty.contains('mifsal') ||
                    n.contains('مفاصل') || ty.contains('مفاصل') ||
                    n.contains('مفصل') || ty.contains('مفصل') ||
                    n.contains('system ob') || ty.contains('system ob') ||
                    n.contains('demi system ob') || ty.contains('demi system ob') ||
                    n.contains('verrou central') || ty.contains('verrou central') ||
                    n.contains('gache simple') || ty.contains('gache simple') ||
                    n.contains('gache double') || ty.contains('gache double') ||
                    n.contains('قاش دوبل') || ty.contains('قاش دوبل') ||
                    n.contains('قاش سامبل') || ty.contains('قاش سامبل') ||
                    n.contains('فتح') || ty.contains('فتح') ||
                    n.contains('ouvrant') || ty.contains('ouvrant')) {
                  return false;
                }
              } else {
                if (n.contains('couliss') || ty.contains('couliss') ||
                    n.contains('roulette') || ty.contains('roulette') ||
                    n.contains('عجلات') || ty.contains('عجلات') ||
                    n.contains('منزلق') || ty.contains('منزلق')) {
                  return false;
                }
              }
            }

            // 4. Kit Clamp/Clan Exclusions (Exclude clamp from kit matching, and vice versa)
            final isKitQuery = widget.profileType.toLowerCase().contains('kit') || widget.profileType.contains('كيت');
            final isClampQuery = widget.profileType.toLowerCase().contains('clamp') || widget.profileType.toLowerCase().contains('clam') || widget.profileType.contains('كلامب') || widget.profileType.contains('كلام') || widget.profileType.contains('كلان');

            final hasKitName = n.contains('kit') || ty.contains('kit') || n.contains('كيت') || ty.contains('كيت');
            final hasClampName = n.contains('clamp') || n.contains('clam') || ty.contains('clamp') || ty.contains('clam') || n.contains('كلامب') || n.contains('كلام') || n.contains('كلان') || ty.contains('كلامب') || ty.contains('كلام') || ty.contains('كلان') || n.contains('clan') || ty.contains('clan');

            if (isKitQuery && hasClampName) return false;
            if (isClampQuery && hasKitName) return false;

            return true;
          }).toList();
        }

        // Column-based filtering for Gache/Lock types
        const colMap = {
          'is_gache_simple': 'is_gache_simple',
          'is_gache_double': 'is_gache_double',
          'is_gache_porte': 'is_gache_porte',
          'is_lock_clef': 'is_lock_clef',
          'is_lock_condamnation': 'is_lock_condamnation',
          'is_moteur_screw': 'is_moteur_screw',
          'is_caisson_screw': 'is_caisson_screw',
          'is_batmo_screw': 'is_batmo_screw',
          'is_bouchon_batmo_screw': 'is_bouchon_batmo_screw',
          'is_renfort_screw': 'is_renfort_screw',
          'is_manivelle_screw': 'is_manivelle_screw',
          'is_tandem_screw': 'is_tandem_screw',
          'is_kit_screw': 'is_kit_screw',
          'is_assembly_screw': 'is_assembly_screw',
          'is_installation_screw': 'is_installation_screw',
          'is_accessory_screw': 'is_accessory_screw',
        };
        final t = widget.profileType;
        final customTypes = ['is_lock', 'is_canon', 'is_poign_clef', 'is_poign_condamnation'];
        if (t == 'is_lock') {
          final customWhere = '(is_lock_clef = 1 OR is_lock_condamnation = 1) AND (is_active = 1 OR is_active IS NULL)';
          data = await queryAccessories(customWhere, []);
        } else if (t == 'is_canon') {
          data = [];
        } else if (t == 'is_poign_clef') {
          data = [];
        } else if (t == 'is_poign_condamnation') {
          data = [];
        } else if (colMap.containsKey(t)) {
          // Use column-based query
          final customWhere = '${colMap[t]} = 1 AND (is_active = 1 OR is_active IS NULL)';
          data = await queryAccessories(customWhere, []);
        }

        if (customTypes.contains(t) || colMap.containsKey(t)) {
          // If the database doesn't have the column configured (empty result), fallback to text mapping
          if (data.isEmpty) {
            String kw = t
                .replaceAll('is_', '')
                .replaceAll('_screw', '')
                .replaceAll('_', ' ');
            if (t == 'is_gache_double')
              kw = ' دوبل قاش';
            else if (t == 'is_gache_simple')
              kw = 'قاش';
            else if (t == 'is_renfort_screw')
              kw = ' الحديد براغي';
            else if (kw.contains('screw'))
              kw = 'براغي';

            final allAcc = await queryAccessories('is_active = 1 OR is_active IS NULL', []);

            data = allAcc.where((a) {
              final n = a['name'].toString().toLowerCase();
              final ty = a['type'].toString().toLowerCase();

              if (t == 'is_batmo_screw') {
                return (n.contains('batmo') || n.contains('باتمو')) &&
                    (n.contains('screw') ||
                        n.contains('براغي') ||
                        n.contains('vis'));
              }
              if (t == 'is_bouchon_batmo_screw') {
                return (n.contains('bouchon') ||
                        n.contains('بوشون') ||
                        n.contains('bochon')) &&
                    (n.contains('screw') ||
                        n.contains('براغي') ||
                        n.contains('vis'));
              }
              if (t == 'is_renfort_screw') {
                return (n.contains('renfort') ||
                        n.contains('حديد') ||
                        n.contains('رنفور')) &&
                    (n.contains('screw') ||
                        n.contains('براغي') ||
                        n.contains('vis'));
              }
              if (t == 'is_gache_porte') {
                final bool containsGache = n.contains('gache') || n.contains('gâche') || n.contains('قاش') || n.contains('كاش') || n.contains('gage') ||
                                           ty.contains('gache') || ty.contains('gâche') || ty.contains('قاش') || ty.contains('كاش') || ty.contains('gage');
                final bool isNotWindowGache = !n.contains('simple') && !n.contains('double') && !n.contains('سامبل') && !n.contains('دوبل') &&
                                              !ty.contains('simple') && !ty.contains('double') && !ty.contains('سامبل') && !ty.contains('دوبل');
                return containsGache && isNotWindowGache;
              }
              if (t == 'is_lock_clef') {
                final bool containsLock = n.contains('serrure') || n.contains('lock') || n.contains('قفل') ||
                                          ty.contains('serrure') || ty.contains('lock') || ty.contains('قفل');
                final bool containsKey = n.contains('clef') || n.contains('clé') || n.contains('مفتاح') ||
                                         ty.contains('clef') || ty.contains('clé') || ty.contains('مفتاح');
                final bool containsExcludes = n.contains('canon') || n.contains('أسطوانة') || n.contains('اسطوانة') || n.contains('poignée') || n.contains('مقبض') || n.contains('handle') ||
                                              ty.contains('canon') || ty.contains('أسطوانة') || ty.contains('اسطوانة') || ty.contains('poignée') || ty.contains('مقبض') || ty.contains('handle');
                return containsLock && containsKey && !containsExcludes;
              }
              if (t == 'is_lock_condamnation') {
                final bool containsLock = n.contains('serrure') || n.contains('lock') || n.contains('قفل') ||
                                          ty.contains('serrure') || ty.contains('lock') || ty.contains('قفل');
                final bool containsCond = n.contains('condamnation') || n.contains('حمام') || n.contains('بدون مفتاح') ||
                                          ty.contains('condamnation') || ty.contains('حمام') || ty.contains('بدون مفتاح');
                final bool containsExcludes = n.contains('poignée') || n.contains('مقبض') || n.contains('handle') ||
                                              ty.contains('poignée') || ty.contains('مقبض') || ty.contains('handle');
                return containsLock && containsCond && !containsExcludes;
              }
              if (t == 'is_lock') {
                final bool containsLock = n.contains('serrure') || n.contains('lock') || n.contains('قفل') ||
                                          ty.contains('serrure') || ty.contains('lock') || ty.contains('قفل');
                final bool containsExcludes = n.contains('canon') || n.contains('أسطوانة') || n.contains('اسطوانة') || n.contains('poignée') || n.contains('مقبض') || n.contains('handle') ||
                                              ty.contains('canon') || ty.contains('أسطوانة') || ty.contains('اسطوانة') || ty.contains('poignée') || ty.contains('مقبض') || ty.contains('handle');
                return containsLock && !containsExcludes;
              }
              if (t == 'is_canon') {
                return n.contains('canon') || n.contains('cylinder') || n.contains('أسطوانة') || n.contains('اسطوانة') || n.contains('barillet') ||
                       ty.contains('canon') || ty.contains('cylinder') || ty.contains('أسطوانة') || ty.contains('اسطوانة') || ty.contains('barillet');
              }
              if (t == 'is_poign_clef') {
                final bool containsHandle = n.contains('poignée') || n.contains('مقبض') || n.contains('handle') ||
                                            ty.contains('poignée') || ty.contains('مقبض') || ty.contains('handle');
                final bool containsKey = n.contains('clef') || n.contains('clé') || n.contains('مفتاح') ||
                                         ty.contains('clef') || ty.contains('clé') || ty.contains('مفتاح');
                return containsHandle && containsKey;
              }
              if (t == 'is_poign_condamnation') {
                final bool containsHandle = n.contains('poignée') || n.contains('مقبض') || n.contains('handle') ||
                                            ty.contains('poignée') || ty.contains('مقبض') || ty.contains('handle');
                final bool containsCond = n.contains('condamnation') || n.contains('حمام') || n.contains('بدون مفتاح') ||
                                          ty.contains('condamnation') || ty.contains('حمام') || ty.contains('بدون مفتاح');
                return containsHandle && containsCond;
              }

              return n.contains(kw) || ty.contains(kw);
            }).toList();
          }
        } else {
          // Fall back to name/type text matching
          final allAcc = await queryAccessories('is_active = 1 OR is_active IS NULL', []);
          final tLower = t.toLowerCase();
          data = allAcc.where((a) {
            final n = a['name'].toString().toLowerCase();
            final ty = (a['type'] ?? '').toString().toLowerCase();

            if (tLower == 'اسبانيوليت' || tLower == 'espagnolette' || tLower.contains('اسبانيول') || tLower.contains('إسبانيول')) {
              return n.contains('espagnol') ||
                  ty.contains('espagnol') ||
                  n.contains('اسبانيول') ||
                  ty.contains('اسبانيول') ||
                  n.contains('سبانيول') ||
                  ty.contains('سبانيول');
            }
            if (tLower == 'kit' || tLower.contains('كيت')) {
              final isKit = n.contains('kit') || ty.contains('kit') || n.contains('كيت') || ty.contains('كيت');
              final isClamp = n.contains('clamp') || n.contains('clam') || ty.contains('clamp') || ty.contains('clam') || n.contains('كلامب') || n.contains('كلام') || ty.contains('كلامب') || ty.contains('كلام') || n.contains('كلان') || ty.contains('كلان') || n.contains('clan') || ty.contains('clan');
              return isKit && !isClamp;
            }
            if (tLower == 'كاش كوليسون' ||
                tLower == 'gache coulisse' ||
                tLower == 'gâche coulisse' ||
                tLower == 'gache coulissante' ||
                tLower == 'gâche coulissante' ||
                tLower == 'gache coulissant' ||
                tLower == 'gâche coulissant') {
              return n.contains('couliss') ||
                  ty.contains('couliss') ||
                  n.contains('كاش') ||
                  ty.contains('كاش') ||
                  n.contains('gache') ||
                  ty.contains('gache') ||
                  n.contains('gâche') ||
                  ty.contains('gâche');
            }
            if (tLower == 'tasso') {
              return n.contains('tasso') ||
                  n.contains('tasseau') ||
                  n.contains('طاسو') ||
                  n.contains('طاصو') ||
                  ty.contains('tasso') ||
                  ty.contains('tasseau') ||
                  ty.contains('طاسو') ||
                  ty.contains('طاصو');
            }
            if (tLower == 'batmo') {
              return (n.contains('batmo') || ty.contains('batmo')) &&
                  !n.contains('bouchon') &&
                  !ty.contains('bouchon') &&
                  !n.contains('bochon') &&
                  !ty.contains('bochon');
            }
            if (tLower == 'bouchon batmo' ||
                tLower == 'bouchon' ||
                tLower == 'bochon batment' ||
                tLower == 'bochon') {
              return n.contains('bouchon') ||
                  ty.contains('bouchon') ||
                  n.contains('bochon') ||
                  ty.contains('bochon') ||
                  n.contains('batment') ||
                  ty.contains('batment');
            }
            if (tLower == 'system ob') {
              return n.contains('system ob') ||
                  ty.contains('system ob') ||
                  n.contains('سيستم أو بي') ||
                  n.contains('سيستم او بي') ||
                  ty.contains('سيستم أو بي') ||
                  ty.contains('سيستم او بي');
            }
            if (tLower == 'entrematique') {
              return n.contains('entrematique') ||
                  n.contains('أونتروماتيك') ||
                  n.contains('انتراميتيك') ||
                  n.contains('intra') ||
                  ty.contains('entrematique') ||
                  ty.contains('أونتروماتيك') ||
                  ty.contains('انتراميتيك') ||
                  ty.contains('intra');
            }
            if (tLower == 'demi system ob' || tLower == 'demi ob') {
              return n.contains('demi') ||
                  ty.contains('demi') ||
                  n.contains('ديمي') ||
                  ty.contains('ديمي');
            }
            if (tLower == 'verrou central') {
              return n.contains('verrou central') ||
                  ty.contains('verrou central') ||
                  n.contains('فيرو سنترال') ||
                  ty.contains('فيرو سنترال') ||
                  n.contains('فيرو سونترال') ||
                  ty.contains('فيرو سونترال') ||
                  n.contains('central') ||
                  ty.contains('central') ||
                  n.contains('سنترال') ||
                  ty.contains('سنترال') ||
                  n.contains('سونترال') ||
                  ty.contains('سونترال');
            }

            if (tLower == 'مفاصل' ||
                tLower == 'hinges' ||
                tLower == 'paumelle' ||
                tLower == 'paumelles') {
              return n.contains('paumelle') ||
                  ty.contains('paumelle') ||
                  n.contains('paumelles') ||
                  ty.contains('paumelles') ||
                  n.contains('مفاصل') ||
                  ty.contains('مفاصل') ||
                  n.contains('مفصلة') ||
                  ty.contains('مفصلة');
            }
            if (tLower == 'مقبض' ||
                tLower == 'handle' ||
                tLower == 'poignée' ||
                tLower == 'poignée fenêtre' ||
                tLower == 'poignee fenetre' ||
                tLower == 'poignée tpr' ||
                tLower == 'poignee tpr' ||
                tLower == 'poignee') {
              return n.contains('poignée') ||
                  ty.contains('poignée') ||
                  n.contains('poignee') ||
                  ty.contains('poignee') ||
                  n.contains('handle') ||
                  ty.contains('handle') ||
                  n.contains('مقبض') ||
                  ty.contains('مقبض') ||
                  n.contains('بواني') ||
                  ty.contains('بواني') ||
                  n.contains('بوانيي') ||
                  ty.contains('بوانيي');
            }
            if (tLower == 'serrure' ||
                tLower == 'lock' ||
                tLower == 'قفل') {
              return n.contains('serrure') ||
                  ty.contains('serrure') ||
                  n.contains('lock') ||
                  ty.contains('lock') ||
                  n.contains('قفل') ||
                  ty.contains('قفل');
            }
            if (tLower == 'canon' ||
                tLower == 'cylinder' ||
                tLower == 'الأسطوانة' ||
                tLower == 'الاسطوانة' ||
                tLower == 'اسطوانة' ||
                tLower == 'أسطوانة') {
              return n.contains('canon') ||
                  ty.contains('canon') ||
                  n.contains('cylinder') ||
                  ty.contains('cylinder') ||
                  n.contains('اسطوانة') ||
                  ty.contains('اسطوانة') ||
                  n.contains('أسطوانة') ||
                  ty.contains('أسطوانة');
            }
            if (tLower == 'cache porte' ||
                tLower == 'gache porte' ||
                tLower == 'كاش بورت' ||
                tLower == 'كاش بورت (cache porte)') {
              return n.contains('cache') ||
                  ty.contains('cache') ||
                  n.contains('gache') ||
                  ty.contains('gache') ||
                  n.contains('كاش') ||
                  ty.contains('كاش');
            }
            if (tLower == 'roulette' || tLower == 'roulettes' || tLower == 'عجلات') {
              return n.contains('roulette') ||
                  ty.contains('roulette') ||
                  n.contains('رول') ||
                  ty.contains('رول') ||
                  n.contains('عجل') ||
                  ty.contains('عجل');
            }
            if (tLower == 'kit' || tLower.contains('كيت')) {
              final isKit = n.contains('kit') || ty.contains('kit') || n.contains('كيت') || ty.contains('كيت');
              final isClamp = n.contains('clamp') || n.contains('clam') || ty.contains('clamp') || ty.contains('clam') || n.contains('كلامب') || n.contains('كلام') || ty.contains('كلامب') || ty.contains('كلام') || n.contains('كلان') || ty.contains('كلان');
              return isKit && !isClamp;
            }

            final normN = normalizeArabic(n);
            final normTy = normalizeArabic(ty);
            final normTLower = normalizeArabic(tLower);
            bool match = normN.contains(normTLower) ||
                normTy.contains(normTLower) ||
                normTLower.contains(normN) ||
                normTLower.contains(normTy);
            
            // Defensive exclusion for generic matches
            if (match) {
              final searchHasKit = normTLower.contains('kit') || normTLower.contains('كيت');
              final searchHasClamp = normTLower.contains('clamp') || normTLower.contains('clam') || normTLower.contains('كلامب') || normTLower.contains('كلام') || normTLower.contains('كلان');
              final itemHasKit = normN.contains('kit') || normTy.contains('kit') || normN.contains('كيت') || normTy.contains('كيت');
              final itemHasClamp = normN.contains('clamp') || normN.contains('clam') || normTy.contains('clamp') || normTy.contains('clam') || normN.contains('كلامب') || normN.contains('كلام') || normN.contains('كلان') || normTy.contains('كلامب') || normTy.contains('كلام') || normTy.contains('كلان');
              
              if (searchHasKit && itemHasClamp) return false;
              if (searchHasClamp && itemHasKit) return false;
            }
            
            // For Central accessories (like Verrou Central), enforce that the matched db item also contains 'central'
            if (match && tLower.contains('central')) {
              if (!n.contains('central') && !ty.contains('central') && !n.contains('سنترال') && !ty.contains('سنترال') && !n.contains('سونترال') && !ty.contains('سونترال')) {
                return false;
              }
            }
            
            // For Espagnolettes, enforce exact number match if a number exists in both
            if (match && (tLower.contains('espagnolette') || tLower.contains('اسبانيوليت') || tLower.contains('إسبانيوليت') || tLower.contains('سبانيوليت'))) {
              final tMatch = RegExp(r'\d+').firstMatch(tLower);
              final nMatch = RegExp(r'\d+').firstMatch(n) ?? RegExp(r'\d+').firstMatch(ty);
              if (tMatch != null && nMatch != null) {
                 if (tMatch.group(0) != nMatch.group(0)) {
                    return false; // Numbers don't match!
                 }
              }
            }

            return match;
          }).toList();
        }
      }
    } else if (widget.category == 'joint') {
      final myDb = await db.db;
      if (myDb != null) {
        final allJoints = await myDb.query('Joints');
        final t = widget.profileType.toLowerCase();
        final isGlassGasket = t.contains('vitrage') || t.contains('زجاج');
        final isBrushGasket = t.contains('brosse') || t.contains('بروس');

        data = allJoints.where((a) {
          final n = a['name'].toString().toLowerCase();
          final ty = a['type'].toString().toLowerCase();
          final gType = a['gasket_type']?.toString().toLowerCase() ?? '';

          if (isGlassGasket) {
            return gType == 'جوان فيتراج' ||
                   gType == 'joint_vitrage' ||
                   n.contains('vitrage') ||
                   n.contains('زجاج');
          }
          if (isBrushGasket) {
            return gType == 'جوان بروس' ||
                   gType == 'joint_brosse' ||
                   n.contains('brosse') ||
                   n.contains('بروس') ||
                   n.contains('brush');
          }

          // Fallback to general keyword match
          List<String> keywords = [t];
          for (var kw in keywords) {
            if (n.contains(kw) ||
                ty.contains(kw) ||
                kw.contains(n) ||
                kw.contains(ty) ||
                gType.contains(kw))
              return true;
          }
          return false;
        }).toList();
      }
    } else if (widget.category == 'shutter') {
      final myDb = await db.db;
      if (myDb != null) {
        final t = widget.profileType.toLowerCase();

        // 1. Get the allowed box sizes from ShutterBoxLimits if available
        List<double> allowedBoxSizes = [];
        if (widget.windowHeight != null && widget.bladeId != null &&
            (t == 'صندوق' || t == 'كيت' || t.contains('caisson') || t.contains('kit'))) {
          try {
            final List<Map<String, dynamic>> limits = await myDb.query(
              'ShutterBoxLimits',
              where: 'blade_id = ?',
              whereArgs: [widget.bladeId],
            );
            if (limits.isNotEmpty) {
              for (var limit in limits) {
                final boxSize = (limit['box_size'] as num).toDouble();
                final maxHeight = (limit['max_height'] as num).toDouble();
                if (widget.windowHeight! <= maxHeight) {
                  allowedBoxSizes.add(boxSize);
                }
              }
              // If no box size is large enough, the largest box is the only one allowed
              if (allowedBoxSizes.isEmpty) {
                final sortedLimits = List<Map<String, dynamic>>.from(limits)
                  ..sort((a, b) => (a['box_size'] as num).compareTo(b['box_size'] as num));
                allowedBoxSizes.add((sortedLimits.last['box_size'] as num).toDouble());
              }
            }
          } catch (e) {
            print('Error loading shutter box limits in profile selector: $e');
          }
        }

        if (t.contains('كيت') || t.contains('kit')) {
          final allKits = await myDb.query(
            'KitBundles',
            where: 'is_active = 1 OR is_active IS NULL',
          );
          data = allKits.map((e) => {
            'id': e['id'],
            'name': e['name'],
            'price': 0.0,
            'price_dzd': 0.0,
            'component_type': 'كيت',
            'measurement': extractSizeDigits(e['name'].toString()),
          }).toList();

          // Filter kits list by material type and series name
          final activeSeriesNameLower = activeSeriesName.toLowerCase();
          final mat = (widget.materialType ?? '').toLowerCase().trim();

          data = data.where((e) {
            final n = e['name'].toString().toLowerCase();

            // 1. Material Exclusions
            if (mat == 'pvc') {
              if (n.contains('aluminium') || n.contains('aluminum') || n.contains('alu') || n.contains('ألمنيوم') || n.contains('tpr')) {
                return false;
              }
            } else { // Aluminium
              if (n.contains('pvc')) {
                return false;
              }
            }

            // 2. Series Name Exclusions
            if (activeSeriesNameLower.isNotEmpty) {
              if (activeSeriesNameLower.contains('67000') || activeSeriesNameLower.contains('67')) {
                if (n.contains('76000') || n.contains('76') || n.contains('60000') || n.contains('60') || n.contains('52000') || n.contains('52') || n.contains('45000') || n.contains('45')) {
                  return false;
                }
              } else if (activeSeriesNameLower.contains('76000') || activeSeriesNameLower.contains('76')) {
                if (n.contains('67000') || n.contains('67') || n.contains('60000') || n.contains('60') || n.contains('52000') || n.contains('52') || n.contains('45000') || n.contains('45')) {
                  return false;
                }
              } else if (activeSeriesNameLower.contains('60000') || activeSeriesNameLower.contains('60')) {
                if (n.contains('67000') || n.contains('67') || n.contains('76000') || n.contains('76') || n.contains('52000') || n.contains('52') || n.contains('45000') || n.contains('45')) {
                  return false;
                }
              }
            }
            return true;
          }).toList();

          if (widget.windowHeight != null) {
            data = data.where((a) {
              final sizeDigits = getComponentSize(a);
              if (sizeDigits != null) {
                double compSize = double.tryParse(sizeDigits) ?? 0.0;
                if (compSize == 15.5) compSize = 155.0;
                if (compSize == 18.5) compSize = 185.0;
                if (compSize == 20.5) compSize = 205.0;
                if (compSize == 15.0) compSize = 150.0;
                if (compSize == 18.0) compSize = 180.0;
                if (compSize == 20.0) compSize = 200.0;
                if (compSize < 100.0) {
                  compSize = compSize * 10.0;
                }

                if (allowedBoxSizes.isNotEmpty) {
                  bool isAllowed = false;
                  for (var allowed in allowedBoxSizes) {
                    if ((compSize - allowed).abs() < 5.0) {
                      isAllowed = true;
                      break;
                    }
                  }
                  if (!isAllowed) return false;
                } else {
                  double minAllowedSize = 155.0;
                  if (widget.windowHeight! > 1600 && widget.windowHeight! <= 2400) {
                    minAllowedSize = 185.0;
                  } else if (widget.windowHeight! > 2400) {
                    minAllowedSize = 205.0;
                  }
                  if (compSize < minAllowedSize) {
                    return false;
                  }
                }
              }
              return true;
            }).toList();
          }
        } else {
          String shutWhere = 'is_active = 1 OR is_active IS NULL';
          List<dynamic> shutArgs = [];
          if (widget.seriesId != null) {
            shutWhere += ' AND ('
                'series_id = ? '
                'OR (series_ids IS NOT NULL AND series_ids != \'\' AND \',\' || series_ids || \',\' LIKE ?) '
                'OR ((series_id IS NULL OR series_id = 0) AND (series_ids IS NULL OR series_ids = \'\'))'
                ')';
            shutArgs.add(widget.seriesId);
            shutArgs.add('%,' + widget.seriesId.toString() + ',%');
          }
          final allShut = await myDb.query(
            'ShutterComponents',
            where: shutWhere,
            whereArgs: shutArgs,
          );

          List<String> keywords = [t];
          if (t.contains('صندوق') || t.contains('caisson'))
            keywords.addAll(['box', 'صندوق', 'caisson']);
          else if (t.contains('شريحة نهائية') || t.contains('lame finale'))
            keywords.addAll(['final_blade', 'lame final', 'نهائي']);
          else if (t.contains('شريحة') || t.contains('lame'))
            keywords.addAll(['blade', 'شريح', 'lame']);
          else if (t.contains('سكك') || t.contains('coulisse'))
            keywords.addAll(['track', 'سك', 'coulisse']);
          else if (t.contains('محور') || t.contains('axe'))
            keywords.addAll(['laxe', 'axe', 'محور']);
          else if (t.contains('أطاش') || t.contains('attache'))
            keywords.addAll(['attache', 'أطاش']);
          else if (t.contains('سيبور موتور') || t.contains('support_moteur') || t.contains('support moteur'))
            keywords.addAll(['support_moteur', 'سيبور موتور']);
          else if (t.contains('الامبو') || t.contains('embout'))
            keywords.addAll(['embout', 'امبو']);
          else if (t.contains('سيبور رولمو') || t.contains('support_roulement') || t.contains('support roulement'))
            keywords.addAll(['support_roulement', 'سيبور رولمو']);
          else if (t.contains('طانديم') || t.contains('tandem'))
            keywords.addAll(['tandem', 'طانديم']);
          else if (t.contains('أغطية الشفرات') || t.contains('bouchon lame') || t.contains('bouchons lames'))
            keywords.addAll(['bouchon_lame', 'أغطية الشفرات', 'غطاء']);

          final initialFiltered = allShut.where((a) {
            final n = a['name'].toString().toLowerCase();
            final ty = (a['component_type'] ?? '').toString().toLowerCase();

            if (t.contains('نهائية') || t.contains('finale')) {
              if (!n.contains('final') && !n.contains('finale') && !n.contains('نهائي') &&
                  !ty.contains('final') && !ty.contains('finale') && !ty.contains('نهائي')) {
                return false;
              }
            }
            if (t == 'شريحة' || t == 'lame') {
              if (n.contains('final') || n.contains('finale') || n.contains('نهائي') ||
                  ty.contains('final') || ty.contains('finale') || ty.contains('نهائي')) {
                return false;
              }
            }

            // فلترة الأحجام بناءً على ارتفاع النافذة لمنع الاختيارات الخاطئة
            if ((t == 'صندوق' || t == 'كيت' || t.contains('caisson') || t.contains('kit')) && widget.windowHeight != null) {
              final sizeDigits = getComponentSize(a);
              if (sizeDigits != null) {
                double compSize = double.tryParse(sizeDigits) ?? 0.0;
                if (compSize == 15.5) compSize = 155.0;
                if (compSize == 18.5) compSize = 185.0;
                if (compSize == 20.5) compSize = 205.0;
                if (compSize == 15.0) compSize = 150.0;
                if (compSize == 18.0) compSize = 180.0;
                if (compSize == 20.0) compSize = 200.0;
                if (compSize < 100.0) {
                  compSize = compSize * 10.0;
                }

                if (allowedBoxSizes.isNotEmpty) {
                  bool isAllowed = false;
                  for (var allowed in allowedBoxSizes) {
                    if ((compSize - allowed).abs() < 5.0) {
                      isAllowed = true;
                      break;
                    }
                  }
                  if (!isAllowed) return false;
                } else {
                  double minAllowedSize = 155.0;
                  if (widget.windowHeight! > 1600 && widget.windowHeight! <= 2400) {
                    minAllowedSize = 185.0;
                  } else if (widget.windowHeight! > 2400) {
                    minAllowedSize = 205.0;
                  }
                  if (compSize < minAllowedSize) {
                    return false; // استبعاد الحجم غير المناسب
                  }
                }
              }
            }

            for (var kw in keywords) {
              if (n.contains(kw) || ty.contains(kw)) return true;
            }
            return false;
          }).toList();

        if (widget.targetSize != null) {
          final targetDigits = widget.targetSize!.toStringAsFixed(0);
          final matchedSizeData = initialFiltered.where((a) {
            final sizeDigits = extractSizeDigits(a['name'].toString());
            return sizeDigits == targetDigits;
          }).toList();
          if (matchedSizeData.isNotEmpty) {
            data = matchedSizeData;
          } else {
            data = initialFiltered;
          }
        } else {
          data = initialFiltered;
        }
        
        if (t.contains('صندوق') || t.contains('caisson')) {
          data = List<Map<String, dynamic>>.from(data);
          data.insert(0, {
            'id': -999,
            'name': 'صندوق نفق (Caisson Tunnel)',
            'price': 0.0,
            'price_dzd': 0.0,
            'component_type': 'صندوق',
            'measurement': 'tunnel',
          });
        }
      } // end else for ShutterComponents
    } // end if (myDb != null)
    } else {
      final myDb = await db.db;
      if (myDb != null) {
        String whereClause = '(is_active = 1 OR is_active IS NULL)';
        List<dynamic> whereArgs = [];
        if (widget.seriesId != null) {
          whereClause = 'series_id = ? AND ' + whereClause;
          whereArgs = [widget.seriesId];
        }
        final allSections = await myDb.query(
          'Sections',
          where: whereClause,
          whereArgs: whereArgs,
        );

        final t = widget.profileType.toLowerCase().trim();
        data = allSections.where((s) {
          final ty = s['type'].toString().toLowerCase().trim();
          final name = s['name'].toString().toLowerCase().trim();

          if (t == 'frame' || t == 'cadre' || t == 'إطار') {
            return ty.contains('frame') ||
                ty.contains('cadre') ||
                ty.contains('إطار') ||
                ty.contains('فريم');
          } else if (t == 'sash' || t == 'ouvrant' || t == 'ضلفة') {
            return ty.contains('sash') ||
                ty.contains('ouvrant') ||
                ty.contains('ضلفة') ||
                ty.contains('ساش');
          } else if (t.contains('lateral') || t.contains('جانبي')) {
            final lowerName = name.toLowerCase();
            final lowerType = ty.toLowerCase();
            final code = (s['code'] ?? '').toString().toLowerCase();
            return (code.contains('67108') || code.contains('67104') || code.endsWith('108') || code.endsWith('104') ||
                    lowerType.contains('lateral') || lowerName.contains('latéral') || lowerName.contains('lateral') || lowerName.contains('جانبي')) &&
                !lowerName.contains('central') && !lowerName.contains('وسطي') && !lowerName.contains('chicane') &&
                !code.contains('105') && !code.contains('107');
          } else if (t.contains('central') || t.contains('وسطي') || t.contains('chicane')) {
            final lowerName = name.toLowerCase();
            final lowerType = ty.toLowerCase();
            final code = (s['code'] ?? '').toString().toLowerCase();
            return (code.contains('67107') || code.contains('67105') || code.endsWith('107') || code.endsWith('105') ||
                    lowerType.contains('central') || lowerName.contains('central') || lowerName.contains('وسطي') || lowerName.contains('chicane')) &&
                !lowerName.contains('latéral') && !lowerName.contains('lateral') && !lowerName.contains('جانبي') &&
                !code.contains('104') && !code.contains('108');
          } else if (t.contains('couvre') || t.contains('side cover') || t.contains('غطاء جانبي') || t.contains('كافر')) {
            final lowerName = name.toLowerCase();
            final lowerType = ty.toLowerCase();
            final code = (s['code'] ?? '').toString().toLowerCase();
            return lowerType.contains('couvre') || lowerName.contains('couvre') || lowerName.contains('غطاء') || lowerType.contains('side_cover') || code.contains('couvre');
          } else if (t == 'renfort') {
            return ty.contains('renfort') ||
                ty.contains('رنفور') ||
                ty.contains('حديد');
          } else if (t == 'batmo') {
            return (ty.contains('batmo') || ty.contains('باتمو')) &&
                !ty.contains('bouchon') &&
                !ty.contains('بوشون');
          } else if (t == 'parclose') {
            return ty.contains('parclose') || ty.contains('باركلوز');
          } else if (t == 'mullion' || t == 'traverse') {
            return ty.contains('mullion') ||
                ty.contains('traverse') ||
                ty.contains('موليان') ||
                ty.contains('ترافيرس');
          } else if (t == 'bouchon batmo' ||
              t == 'bouchon batment' ||
              t == 'bouchon') {
            return ty.contains('bouchon') ||
                ty.contains('بوشون') ||
                ty.contains('bochon');
          }
          // البحث بالكود مباشرة (مثلاً 67114 للريديكتور)
          final code = (s['code'] ?? '').toString().toLowerCase().trim();
          if (RegExp(r'^\d+$').hasMatch(t)) {
            return code.contains(t) &&
                !ty.contains('rail') &&
                !name.contains('rail') &&
                !name.contains('سكة');
          }
          if (t.contains('reduct') || t.contains('67114') || t.contains('ريديك') || t.contains('مخفض')) {
            return (ty.contains('reduct') ||
                    name.contains('reduct') ||
                    name.contains('مخفض') ||
                    name.contains('ريديكتور') ||
                    code.contains('67114')) &&
                !ty.contains('rail') &&
                !ty.contains('cadre') &&
                !ty.contains('frame') &&
                !name.contains('rail') &&
                !name.contains('سكة') &&
                !name.contains('cadre') &&
                !name.contains('إطار');
          }
          if (t == 'rail' || t.contains('rail') || t.contains('الري') || t.contains('سكة')) {
            return (ty == 'rail' || ty.contains('rail') || name.contains('rail') || name.contains('سكة')) &&
                !ty.contains('frame') &&
                !ty.contains('cadre') &&
                !name.contains('cadre') &&
                !name.contains('إطار');
          }
          return ty.contains(t) || t.contains(ty) || name.contains(t) || t.contains(name);
        }).toList();
      } else {
        data = [];
      }
    }

    setState(() {
      profiles = data;
      isLoading = false;
    });
  }

  String searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final filtered = profiles.where((item) {
      if (searchQuery.isEmpty) return true;
      final q = searchQuery.toLowerCase().trim();
      final name = (item['name'] ?? '').toString().toLowerCase();
      final code = (item['code'] ?? '').toString().toLowerCase();
      final type = (item['type'] ?? '').toString().toLowerCase();
      return name.contains(q) || code.contains(q) || type.contains(q);
    }).toList();

    return AlertDialog(
      title: Text('اختر ${widget.profileType}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 450),
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: TextField(
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    hintText: 'بحث...',
                    hintStyle: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white54
                          : Colors.black38,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white70
                          : Colors.grey,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white30
                            : Colors.grey.shade300,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white24
                            : Colors.grey.shade300,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.blue.shade300
                            : Colors.blue,
                        width: 1.5,
                      ),
                    ),
                  ),
                  onChanged: (val) {
                    setState(() {
                      searchQuery = val;
                    });
                  },
                ),
              ),
              Expanded(
                child: isLoading
                    ? const SizedBox(
                        height: 100,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : filtered.isEmpty
                    ? const SizedBox(
                        height: 100,
                        child: Center(
                          child: Text('لا توجد نتائج مطابقة'),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final item = filtered[index];

                          // معالجة القيم الفارغة في الكود والاسم
                          final codeStr =
                              (item['code'] != null &&
                                  item['code'].toString().isNotEmpty)
                              ? '${item['code']} - '
                              : '';
                          final nameStr = (item['name'] ?? 'بدون اسم')
                              .toString()
                              .replaceAll(RegExp(r'\s*\(\s*جودة[^)]*\)'), '')
                              .trim();

                          return ListTile(
                            leading: SectionImageWidget(
                              code: item['code']?.toString(),
                              imagePath: item['image_path']?.toString(),
                              size: 40.0,
                            ),
                            title: Text('$codeStr$nameStr'),
                            onTap: () => Navigator.pop(context, item),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
      ],
    );
  }
}

String? extractSizeDigits(String name) {
  final regExp = RegExp(r'\d+(\.\d+)?');
  final match = regExp.firstMatch(name);
  if (match == null) return null;
  return match.group(0)!.replaceAll('.', '');
}

String? getComponentSize(Map<String, dynamic> component) {
  final meas = (component['measurement'] ?? '').toString().trim();
  if (meas.isNotEmpty) {
    return meas.replaceAll('.', '').replaceAll(',', '');
  }
  return extractSizeDigits(component['name'].toString());
}

String normalizeArabic(String str) {
  return str
      .replaceAll('إ', 'ا')
      .replaceAll('أ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي');
}
