import 'dart:async';

import 'package:database_data/widgets/app_material.dart';
import 'package:provider/provider.dart';

import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../services/price_sync_service.dart';

Future<T> _runWithPriceSyncProgress<T>(
  BuildContext context,
  Future<T> Function() action,
) async {
  BuildContext? progressContext;
  final dialogReady = Completer<void>();
  final dialogClosed = showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (dialogContext) {
      progressContext = dialogContext;
      if (!dialogReady.isCompleted) dialogReady.complete();
      return const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      );
    },
  );

  await dialogReady.future;
  try {
    return await action();
  } finally {
    final dialogContext = progressContext;
    if (dialogContext != null && dialogContext.mounted) {
      Navigator.of(dialogContext, rootNavigator: true).pop();
    }
    await dialogClosed;
  }
}

class PriceSyncBanner extends StatelessWidget {
  final String categoryKey;
  final VoidCallback? onPriceUpdated;

  const PriceSyncBanner({
    super.key,
    required this.categoryKey,
    this.onPriceUpdated,
  });

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final category = PriceSyncService.categories.firstWhere(
      (c) => c.key == categoryKey,
      orElse: () => PriceSyncService.categories.first,
    );

    final isEnabled = PriceSyncService.instance.isCategoryEnabled(
      settings,
      categoryKey,
    );

    final title = lang == AppLanguage.arabic
        ? category.titleAr
        : category.titleFr;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isEnabled
              ? Colors.green.withValues(alpha: 0.35)
              : Colors.blueGrey.withValues(alpha: 0.25),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Icon(
            category.icon,
            size: 26,
            color: isEnabled ? Colors.green.shade600 : Colors.blueGrey.shade400,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isEnabled
                            ? Colors.green.withValues(alpha: 0.15)
                            : Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isEnabled
                            ? (lang == AppLanguage.arabic
                                ? 'متزامنة'
                                : 'Synchronisé')
                            : (lang == AppLanguage.arabic
                                ? 'مستقلة'
                                : 'Indépendant'),
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isEnabled
                              ? Colors.green.shade700
                              : Colors.orange.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  isEnabled
                      ? (lang == AppLanguage.arabic
                          ? 'يتم قبول وتطبيق الأسعار من مدير التطبيق'
                          : 'Prix reçus de l\'administrateur central')
                      : (lang == AppLanguage.arabic
                          ? 'يتم الاعتماد على أسعار ورشتك الخاصة دون تعديل'
                          : 'Les prix propres de votre atelier sont conservés'),
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FutureBuilder<bool>(
            future: PriceSyncService.instance.isCurrentUserAdmin(),
            builder: (context, snapshot) {
              final isAdmin = snapshot.data ?? false;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      isAdmin
                          ? Icons.cloud_upload_outlined
                          : Icons.cloud_download_outlined,
                      size: 22,
                    ),
                    tooltip: isAdmin
                        ? (lang == AppLanguage.arabic
                            ? 'نشر وتعميم السعر'
                            : 'Publier les prix')
                        : (lang == AppLanguage.arabic
                            ? 'تحديث الأسعار الآن'
                            : 'Actualiser les prix'),
                    onPressed: () => _handleSyncAction(
                      context,
                      isAdmin,
                      categoryKey,
                    ),
                  ),
                  Switch.adaptive(
                    value: isEnabled,
                    activeTrackColor: Colors.green.shade600,
                    activeThumbColor: Colors.white,
                    onChanged: (val) async {
                      await PriceSyncService.instance.setCategoryEnabled(
                        settings,
                        categoryKey,
                        val,
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _handleSyncAction(
    BuildContext context,
    bool isAdmin,
    String categoryKey,
  ) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;

    try {
      if (isAdmin) {
        // Prices are workshop data and are not part of the global catalogue:
        // publish this category's price tables and notify every manager.
        final count = await _runWithPriceSyncProgress(
          context,
          () => PriceSyncService.instance.publishCategoryPrices(categoryKey),
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              lang == AppLanguage.arabic
                  ? 'تم نشر $count سعراً، وأُرسل إشعار لكل مدراء الورشات.'
                  : '$count prix publiés ; les responsables des ateliers ont été notifiés.',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        final result = await _runWithPriceSyncProgress(
          context,
          () => PriceSyncService.instance.syncCategoryPricesFromCloud(
            categoryKey,
          ),
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              lang == AppLanguage.arabic
                  ? 'تم تحديث ${result.updated} سعراً من أسعار مدير التطبيق'
                        '${result.kept > 0 ? '، واحتُفظ بـ ${result.kept} سعراً خاصاً بورشتك' : ''}.'
                  : '${result.updated} prix mis à jour'
                        '${result.kept > 0 ? ', ${result.kept} prix de votre atelier conservés' : ''}.',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.green,
          ),
        );
        onPriceUpdated?.call();
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'حدث خطأ: ${e.toString().replaceAll('Exception: ', '')}',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

/// نافذة مجمعة لكافة خيارات مزامنة الأسعار
Future<void> showPriceSyncSettingsDialog(
  BuildContext context, {
  VoidCallback? onPriceUpdated,
}) async {
  final settings = Provider.of<AppSettingsProvider>(context, listen: false);
  final lang = settings.language;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final isAdmin = await PriceSyncService.instance.isCurrentUserAdmin();

  if (!context.mounted) return;

  final requestedAction = await showDialog<String>(
    context: context,
    builder: (dialogCtx) {
      final mediaQuery = MediaQuery.of(dialogCtx);
      final isCompact = mediaQuery.size.width < 600;
      final availableHeight =
          mediaQuery.size.height -
          mediaQuery.padding.vertical -
          mediaQuery.viewInsets.vertical;
      final maxContentHeight = (availableHeight * 0.62)
          .clamp(220.0, 600.0)
          .toDouble();

      return StatefulBuilder(
        builder: (ctx, setStateDialog) {
          return AlertDialog(
            insetPadding: EdgeInsets.symmetric(
              horizontal: isCompact ? 16 : 40,
              vertical: 24,
            ),
            title: Row(
              children: [
                Icon(
                  Icons.sync_alt_rounded,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    Localization.translate('مزامنة الأسعار', lang),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 500,
                maxHeight: maxContentHeight,
              ),
              child: SizedBox(
                width: 500,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    Text(
                      lang == AppLanguage.arabic
                          ? 'حدد الأقسام التي ترغب في قبول واستلام أسعارها تلقائياً من مدير التطبيق. الأقسام المعطلة ستحافظ على أسعارها المستقلة داخل ورشتك.'
                          : 'Sélectionnez les rubriques dont vous acceptez les prix de l\'administrateur. Les rubriques désactivées conservent leurs propres prix.',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...PriceSyncService.categories.map((cat) {
                      final isEnabled = PriceSyncService.instance
                          .isCategoryEnabled(settings, cat.key);
                      final title = lang == AppLanguage.arabic
                          ? cat.titleAr
                          : cat.titleFr;
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isDark
                                ? Colors.white12
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: isCompact ? 12 : 16,
                            vertical: isCompact ? 4 : 0,
                          ),
                          isThreeLine: isCompact,
                          secondary: isCompact
                              ? null
                              : Icon(
                                  cat.icon,
                                  color: isEnabled ? Colors.green : Colors.grey,
                                ),
                          title: Text(
                            title,
                            maxLines: isCompact ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: isCompact ? 12 : 13,
                            ),
                          ),
                          subtitle: Text(
                            isEnabled
                                ? (lang == AppLanguage.arabic
                                      ? 'متزامنة مع الإدارة'
                                      : 'Synchronisé avec l\'admin')
                                : (lang == AppLanguage.arabic
                                      ? 'أسعار مستقلة خاصة بالورشة'
                                      : 'Prix indépendants de l\'atelier'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              color: isEnabled
                                  ? Colors.green.shade700
                                  : Colors.orange.shade800,
                            ),
                          ),
                          value: isEnabled,
                          activeTrackColor: Colors.green.shade600,
                          activeThumbColor: Colors.white,
                          onChanged: (val) async {
                            await PriceSyncService.instance.setCategoryEnabled(
                              settings,
                              cat.key,
                              val,
                            );
                            setStateDialog(() {});
                          },
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            actionsOverflowAlignment: isCompact
                ? OverflowBarAlignment.center
                : OverflowBarAlignment.end,
            actionsOverflowButtonSpacing: 8,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: Text(Localization.translate('إغلاق', lang)),
              ),
              if (isAdmin)
                ElevatedButton.icon(
                  icon: const Icon(Icons.cloud_upload),
                  label: Text(
                    isCompact
                        ? switch (lang) {
                            AppLanguage.arabic => 'نشر الأسعار',
                            AppLanguage.french => 'Publier les prix',
                            AppLanguage.english => 'Publish prices',
                          }
                        : Localization.translate(
                            'نشر وتحديث الأسعار لجميع الورشات',
                            lang,
                          ),
                  ),
                  onPressed: () => Navigator.pop(dialogCtx, 'upload'),
                )
              else
                ElevatedButton.icon(
                  icon: const Icon(Icons.cloud_download),
                  label: Text(
                    isCompact
                        ? switch (lang) {
                            AppLanguage.arabic => 'تحديث الأسعار',
                            AppLanguage.french => 'Actualiser les prix',
                            AppLanguage.english => 'Update prices',
                          }
                        : Localization.translate(
                            'تحديث الأسعار الآن من السحابة',
                            lang,
                          ),
                  ),
                  onPressed: () => Navigator.pop(dialogCtx, 'download'),
                ),
            ],
          );
        },
      );
    },
  );

  if (requestedAction == null || !context.mounted) return;

  try {
    if (requestedAction == 'upload') {
      final published = await _runWithPriceSyncProgress(context, () async {
        var total = 0;
        for (final cat in PriceSyncService.categories) {
          try {
            total += await PriceSyncService.instance.publishCategoryPrices(
              cat.key,
            );
          } catch (error) {
            // An empty category must not block the others.
            debugPrint('Price publication ${cat.key} skipped: $error');
          }
        }
        return total;
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            lang == AppLanguage.arabic
                ? 'تم نشر $published سعراً لجميع الورشات.'
                : '$published prix publiés pour tous les ateliers.',
          ),
          backgroundColor: published > 0 ? Colors.green : Colors.orange,
        ),
      );
      return;
    }

    final totalUpdated = await _runWithPriceSyncProgress(
      context,
      () async {
        var updated = PriceApplyResult.zero;
        for (final cat in PriceSyncService.categories) {
          if (PriceSyncService.instance.isCategoryEnabled(settings, cat.key)) {
            updated += await PriceSyncService.instance
                .syncCategoryPricesFromCloud(cat.key);
          }
        }
        return updated;
      },
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          lang == AppLanguage.arabic
              ? 'تم تحديث ${totalUpdated.updated} سعراً بنجاح'
                    '${totalUpdated.kept > 0 ? '، واحتُفظ بـ ${totalUpdated.kept} سعراً خاصاً بورشتك' : ''}.'
              : '${totalUpdated.updated} prix mis à jour avec succès'
                    '${totalUpdated.kept > 0 ? ', ${totalUpdated.kept} prix de votre atelier conservés' : ''}.',
        ),
        backgroundColor: Colors.green,
      ),
    );
    onPriceUpdated?.call();
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('خطأ: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}
