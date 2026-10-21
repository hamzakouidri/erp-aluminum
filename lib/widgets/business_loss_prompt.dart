import 'package:database_data/widgets/app_material.dart';
import 'package:provider/provider.dart';

import '../services/cloud_sync_service.dart';
import '../services/supabase_workshop_sync_service.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../sql_database.dart';

bool _promptOpen = false;

/// Asks a manager what to do with downloaded deletions that were held back
/// because they would remove many local clients, orders or treasury rows.
/// Workers keep their local rows until a manager decides. Returns true when
/// the manager decided.
Future<bool> showPendingBusinessDataLoss(BuildContext context) async {
  if (_promptOpen) return false;
  final settings = Provider.of<AppSettingsProvider>(context, listen: false);
  if (!settings.isManager) return false;
  BusinessDataLossConflict? conflict;
  try {
    conflict = await SqlDatabase().readPendingBusinessDataLoss();
  } catch (error) {
    debugPrint('Pending business data loss check failed: $error');
    return false;
  }
  if (conflict == null || !context.mounted) return false;

  _promptOpen = true;
  try {
    final decided = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => BusinessLossDialog(conflict: conflict!),
    );
    return decided ?? false;
  } finally {
    _promptOpen = false;
  }
}

class BusinessLossDialog extends StatefulWidget {
  const BusinessLossDialog({super.key, required this.conflict});

  final BusinessDataLossConflict conflict;

  @override
  State<BusinessLossDialog> createState() => _BusinessLossDialogState();
}

class _BusinessLossDialogState extends State<BusinessLossDialog> {
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
    try {
      if (applyRemote) {
        await SqlDatabase().applyPendingBusinessDataLoss();
      } else {
        // The local rows become the workshop's copy again; otherwise the
        // same deletions are held back at every full download.
        await SupabaseWorkshopSyncService().keepLocalBusinessRows();
      }
      CloudSyncService().notifyChange();
      if (!mounted) return;
      Navigator.of(context).pop(true);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            Localization.translate(
              applyRemote
                  ? 'business_loss_applied_remote'
                  : 'business_loss_kept_local',
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
            '${Localization.translate('business_loss_failed', lang)}: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    String t(String key) => Localization.translate(key, lang);
    final conflict = widget.conflict;
    const tables = SqlDatabaseBusinessDataGuard.guardedTables;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(child: Text(t('business_loss_title'))),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('business_loss_body')),
            const SizedBox(height: 12),
            Table(
              columnWidths: const {0: FlexColumnWidth(2)},
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  children: [
                    const SizedBox.shrink(),
                    _header(t('business_loss_local')),
                    _header(t('business_loss_lost')),
                  ],
                ),
                for (final table in tables)
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(t('business_loss_table_$table')),
                      ),
                      _cell('${conflict.localCounts[table] ?? 0}'),
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
          child: Text(t('business_loss_later')),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _decide(applyRemote: true),
          child: Text(t('business_loss_apply_remote')),
        ),
        // The safe choice is the primary button, so Enter keeps the data.
        ElevatedButton(
          onPressed: _busy ? null : () => _decide(applyRemote: false),
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(t('business_loss_keep_local')),
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

bool _uploadPromptOpen = false;

/// Asks a manager whether to send the deletions made on this device that
/// would remove many clients, orders or treasury rows from the workshop.
/// Until a manager answers they stay on this device. Returns true when the
/// manager decided.
Future<bool> showHeldDeletionUpload(BuildContext context) async {
  if (_uploadPromptOpen) return false;
  final settings = Provider.of<AppSettingsProvider>(context, listen: false);
  if (!settings.isManager) return false;
  final held = await SupabaseWorkshopSyncService().readHeldDeletionUpload();
  if (held == null || !context.mounted) return false;

  _uploadPromptOpen = true;
  try {
    final decided = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => HeldDeletionUploadDialog(
        deleted: held.deleted,
        remaining: held.remaining,
      ),
    );
    return decided ?? false;
  } finally {
    _uploadPromptOpen = false;
  }
}

class HeldDeletionUploadDialog extends StatefulWidget {
  const HeldDeletionUploadDialog({
    super.key,
    required this.deleted,
    required this.remaining,
  });

  final Map<String, int> deleted;
  final Map<String, int> remaining;

  @override
  State<HeldDeletionUploadDialog> createState() =>
      _HeldDeletionUploadDialogState();
}

class _HeldDeletionUploadDialogState extends State<HeldDeletionUploadDialog> {
  bool _busy = false;
  String _error = '';

  Future<void> _decide({required bool send}) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final sync = SupabaseWorkshopSyncService();
      if (send) {
        await sync.approveHeldDeletionUpload();
      } else {
        await sync.cancelHeldDeletionUpload();
      }
      CloudSyncService().notifyChange();
      if (!mounted) return;
      Navigator.of(context).pop(true);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            Localization.translate(
              send
                  ? 'business_loss_upload_sent'
                  : 'business_loss_upload_restored',
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
            '${Localization.translate('business_loss_failed', lang)}: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    String t(String key) => Localization.translate(key, lang);
    const tables = SqlDatabaseBusinessDataGuard.guardedTables;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(child: Text(t('business_loss_upload_title'))),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('business_loss_upload_body')),
            const SizedBox(height: 12),
            Table(
              columnWidths: const {0: FlexColumnWidth(2)},
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  children: [
                    const SizedBox.shrink(),
                    _header(t('business_loss_upload_deleted')),
                    _header(t('business_loss_upload_remaining')),
                  ],
                ),
                for (final table in tables)
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(t('business_loss_table_$table')),
                      ),
                      _cell(
                        '${widget.deleted[table] ?? 0}',
                        color: (widget.deleted[table] ?? 0) > 0
                            ? Colors.red
                            : null,
                      ),
                      _cell('${widget.remaining[table] ?? 0}'),
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
          child: Text(t('business_loss_later')),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _decide(send: true),
          child: Text(t('business_loss_upload_send')),
        ),
        // The safe choice is the primary button: nothing leaves the device.
        ElevatedButton(
          onPressed: _busy ? null : () => _decide(send: false),
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(t('business_loss_upload_restore')),
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
