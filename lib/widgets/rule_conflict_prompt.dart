import 'package:database_data/widgets/app_material.dart';
import 'package:provider/provider.dart';

import '../services/cloud_sync_service.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../sql_database.dart';

bool _promptOpen = false;

/// Readable name of a workshop rule table, or the table name itself.
String ruleTableLabel(String table, AppLanguage lang) {
  final key = 'rule_table_$table';
  final label = Localization.translate(key, lang);
  return label == key ? table : label;
}

/// Asks a manager what to do with a remote rule copy that was held back
/// because it would remove many local rules. Workers keep their local rules
/// until a manager decides. Returns true when the manager decided.
Future<bool> showPendingRuleConflict(BuildContext context) async {
  if (_promptOpen) return false;
  final settings = Provider.of<AppSettingsProvider>(context, listen: false);
  if (!settings.isManager) return false;
  final db = SqlDatabase();
  CatalogConfigConflict? conflict;
  try {
    conflict = await db.readPendingCatalogConfigConflict();
  } catch (error) {
    debugPrint('Pending rule conflict check failed: $error');
    return false;
  }
  if (conflict == null || !context.mounted) return false;

  _promptOpen = true;
  try {
    final decided = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => RuleConflictDialog(conflict: conflict!),
    );
    return decided ?? false;
  } finally {
    _promptOpen = false;
  }
}

class RuleConflictDialog extends StatefulWidget {
  const RuleConflictDialog({super.key, required this.conflict});

  final CatalogConfigConflict conflict;

  @override
  State<RuleConflictDialog> createState() => _RuleConflictDialogState();
}

class _RuleConflictDialogState extends State<RuleConflictDialog> {
  bool _busy = false;
  String _error = '';

  Future<void> _decide({required bool applyRemote}) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _busy = true;
      _error = '';
    });
    final db = SqlDatabase();
    try {
      if (applyRemote) {
        await db.applyPendingCatalogConfigConflict();
        CloudSyncService().notifyWorkshopRulesChanged();
      } else {
        await db.discardPendingCatalogConfigConflict();
        // The local rules become the workshop's copy again; otherwise the
        // same remote copy is held back at every sync.
        await CloudSyncService().uploadWorkshopCatalogConfiguration();
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            Localization.translate(
              applyRemote
                  ? 'rule_snapshot_applied_remote'
                  : 'rule_snapshot_kept_local',
              lang,
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            '${Localization.translate('rule_snapshot_failed', lang)}: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    String t(String key) => Localization.translate(key, lang);
    final conflict = widget.conflict;
    final tables = SqlDatabaseCatalogConfigGuard.guardedTables;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(child: Text(t('rule_snapshot_conflict_title'))),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('rule_snapshot_conflict_body')),
            const SizedBox(height: 12),
            Table(
              columnWidths: const {0: FlexColumnWidth(2)},
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  children: [
                    const SizedBox.shrink(),
                    _header(t('rule_snapshot_conflict_local')),
                    _header(t('rule_snapshot_conflict_remote')),
                    _header(t('rule_snapshot_conflict_lost')),
                  ],
                ),
                for (final table in tables)
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(ruleTableLabel(table, lang)),
                      ),
                      _cell('${conflict.localCounts[table] ?? 0}'),
                      _cell('${conflict.remoteCounts[table] ?? 0}'),
                      _cell(
                        '${conflict.lostRows[table] ?? 0}',
                        color: (conflict.lostRows[table] ?? 0) > 0
                            ? Colors.red
                            : null,
                      ),
                    ],
                  ),
              ],
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_error, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(t('rule_snapshot_later')),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _decide(applyRemote: true),
          child: Text(t('rule_snapshot_apply_remote')),
        ),
        // The safe choice is the primary button, so Enter keeps the rules.
        ElevatedButton(
          onPressed: _busy ? null : () => _decide(applyRemote: false),
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(t('rule_snapshot_keep_local')),
        ),
      ],
    );
  }

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
    ),
  );

  Widget _cell(String text, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: color, fontWeight: FontWeight.w600),
    ),
  );
}
