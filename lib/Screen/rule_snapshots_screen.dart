import 'package:database_data/widgets/app_material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/cloud_sync_service.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../sql_database.dart';
import '../widgets/rule_conflict_prompt.dart';

/// Manager screen listing the local copies of the workshop rule tables
/// (series roles, accessory rules...) with a restore action, and the remote
/// copy waiting for a decision when one was held back.
class RuleSnapshotsScreen extends StatefulWidget {
  const RuleSnapshotsScreen({super.key});

  @override
  State<RuleSnapshotsScreen> createState() => _RuleSnapshotsScreenState();
}

class _RuleSnapshotsScreenState extends State<RuleSnapshotsScreen> {
  final SqlDatabase _db = SqlDatabase();
  List<CatalogConfigSnapshot> _snapshots = const [];
  CatalogConfigConflict? _conflict;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final snapshots = await _db.readCatalogConfigSnapshots();
    final conflict = await _db.readPendingCatalogConfigConflict();
    if (!mounted) return;
    setState(() {
      _snapshots = snapshots;
      _conflict = conflict;
      _loading = false;
    });
  }

  AppLanguage get _lang =>
      Provider.of<AppSettingsProvider>(context, listen: false).language;

  String _t(String key) => Localization.translate(key, _lang);

  void _show(String message, {Color? color}) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  Future<void> _saveNow() async {
    setState(() => _busy = true);
    try {
      final id = await _db.saveCatalogConfigSnapshot(reason: 'manual');
      if (!mounted) return;
      _show(_t(id == null ? 'rule_snapshot_not_saved' : 'rule_snapshot_saved'));
      await _load();
    } catch (error) {
      if (mounted)
        _show('${_t('rule_snapshot_failed')}: $error', color: Colors.red);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(CatalogConfigSnapshot snapshot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('rule_snapshot_restore_confirm_title')),
        content: Text(_t('rule_snapshot_restore_confirm_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(Localization.translate('إلغاء', _lang)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_t('rule_snapshot_restore')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await _db.restoreCatalogConfigSnapshot(snapshot.id);
      try {
        await CloudSyncService().uploadWorkshopCatalogConfiguration();
        if (mounted) _show(_t('rule_snapshot_restored'), color: Colors.green);
      } catch (error) {
        // The pending flag stays set, so the upload is retried at the next
        // successful sync start.
        debugPrint('Rule upload after restore failed: $error');
        if (mounted) {
          _show(
            _t('rule_snapshot_restored_not_uploaded'),
            color: Colors.orange,
          );
        }
      }
      await _load();
    } catch (error) {
      if (mounted)
        _show('${_t('rule_snapshot_failed')}: $error', color: Colors.red);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openConflict() async {
    await showPendingRuleConflict(context);
    await _load();
  }

  String _reasonLabel(String reason) {
    final key = 'rule_snapshot_reason_$reason';
    final label = _t(key);
    return label == key ? reason : label;
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
    return Scaffold(
      appBar: AppBar(
        title: Text(Localization.translate('rule_snapshot_title', lang)),
        actions: [
          IconButton(
            tooltip: Localization.translate('rule_snapshot_save_now', lang),
            icon: const Icon(Icons.add_a_photo_outlined),
            onPressed: _busy ? null : _saveNow,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (_conflict != null)
                  Card(
                    color: Colors.orange.withValues(alpha: 0.12),
                    child: ListTile(
                      leading: const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.orange,
                      ),
                      title: Text(
                        Localization.translate(
                          'rule_snapshot_conflict_title',
                          lang,
                        ),
                      ),
                      subtitle: Text(dateFormat.format(_conflict!.detectedAt)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _busy ? null : _openConflict,
                    ),
                  ),
                if (_snapshots.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        Localization.translate('rule_snapshot_empty', lang),
                      ),
                    ),
                  ),
                for (final snapshot in _snapshots)
                  Card(
                    child: ExpansionTile(
                      leading: const Icon(Icons.history),
                      title: Text(dateFormat.format(snapshot.createdAt)),
                      subtitle: Text(
                        [
                          _reasonLabel(snapshot.reason),
                          if (snapshot.workshopCode.isNotEmpty)
                            '${Localization.translate('rule_snapshot_workshop', lang)}: ${snapshot.workshopCode}',
                          '${snapshot.totalRows} ${Localization.translate('rule_snapshot_rows', lang)}',
                        ].join(' • '),
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      children: [
                        for (final table
                            in SqlDatabase.workshopCatalogConfigurationTables)
                          if (snapshot.counts.containsKey(table))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(ruleTableLabel(table, lang)),
                                  ),
                                  Text(
                                    '${snapshot.counts[table]}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color:
                                          SqlDatabaseCatalogConfigGuard
                                              .guardedTables
                                              .contains(table)
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.restore),
                            label: Text(
                              Localization.translate(
                                'rule_snapshot_restore',
                                lang,
                              ),
                            ),
                            onPressed: _busy ? null : () => _restore(snapshot),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
