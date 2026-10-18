import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/price_sync_service.dart';
import '../settings/app_settings.dart';

String _t(AppLanguage lang, String ar, String fr, String en) => switch (lang) {
  AppLanguage.french => fr,
  AppLanguage.english => en,
  _ => ar,
};

bool _promptOpen = false;

/// Shows the administrator's new price publications to a workshop manager
/// and lets them apply or ignore each one. Applied prices are written to
/// the manager's local tables and reach the workers through workshop sync.
///
/// Returns the number of applied publications. Does nothing for workers, the
/// application administrator, or when there is nothing pending.
Future<int> showPendingPricePublications(
  BuildContext context, {
  String? onlyCategory,
}) async {
  if (_promptOpen) return 0;
  List<PricePublication> pending;
  try {
    pending = await PriceSyncService.instance.fetchPendingPublications();
  } catch (error) {
    debugPrint('Pending price publications check failed: $error');
    return 0;
  }
  if (onlyCategory != null) {
    pending = pending.where((p) => p.category == onlyCategory).toList();
  }
  if (pending.isEmpty || !context.mounted) return 0;

  _promptOpen = true;
  try {
    final applied = await showDialog<int>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _PricePublicationDialog(publications: pending),
    );
    return applied ?? 0;
  } finally {
    _promptOpen = false;
  }
}

class _PricePublicationDialog extends StatefulWidget {
  const _PricePublicationDialog({required this.publications});

  final List<PricePublication> publications;

  @override
  State<_PricePublicationDialog> createState() =>
      _PricePublicationDialogState();
}

class _PricePublicationDialogState extends State<_PricePublicationDialog> {
  late final List<PricePublication> _remaining = [...widget.publications];
  final Set<int> _busy = {};
  int _applied = 0;
  int _kept = 0;
  bool _keepWorkshopPrices = true;
  String _error = '';

  Future<void> _decide(PricePublication publication, bool apply) async {
    setState(() {
      _busy.add(publication.id);
      _error = '';
    });
    try {
      if (apply) {
        final result = await PriceSyncService.instance.applyPublication(
          publication.id,
          keepWorkshopPrices: _keepWorkshopPrices,
        );
        _applied++;
        _kept += result.kept;
      } else {
        await PriceSyncService.instance.dismissPublication(publication.id);
      }
      if (!mounted) return;
      setState(() => _remaining.remove(publication));
      if (_remaining.isEmpty) _close();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy.remove(publication.id));
    }
  }

  void _close() {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    Navigator.of(context).pop(_applied);
    if (_kept > 0) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            _t(
              lang,
              'تم الاحتفاظ بـ $_kept سعراً خاصاً بورشتك (معدّل يدوياً أو من الشراء).',
              '$_kept prix propres à votre atelier ont été conservés (saisis ou issus des achats).',
              '$_kept of your workshop prices were kept (typed or from purchases).',
            ),
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    String date(DateTime d) {
      final l = d.toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
    }

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.price_change_rounded, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _t(
                lang,
                'أسعار جديدة متوفرة',
                'Nouveaux prix disponibles',
                'New prices available',
              ),
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _t(
                  lang,
                  'نشر مدير التطبيق أسعاراً جديدة. عند القبول تُحدَّث أسعار ورشتك على هذا الجهاز وعلى هواتف عمالك.',
                  "L'administrateur a publié de nouveaux prix. En acceptant, les prix de votre atelier sont mis à jour sur cet appareil et sur les téléphones de vos ouvriers.",
                  'The administrator published new prices. Accepting updates your workshop prices on this device and on your workers’ phones.',
                ),
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _keepWorkshopPrices,
                onChanged: _busy.isNotEmpty
                    ? null
                    : (value) =>
                          setState(() => _keepWorkshopPrices = value ?? true),
                title: Text(
                  _t(
                    lang,
                    'الاحتفاظ بأسعاري الخاصة',
                    'Conserver mes propres prix',
                    'Keep my own prices',
                  ),
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                ),
                subtitle: Text(
                  _t(
                    lang,
                    'الأسعار التي عدّلتها يدوياً أو حُسبت من فواتير الشراء لا تُستبدل.',
                    "Les prix saisis à la main ou calculés depuis vos achats ne sont pas remplacés.",
                    'Prices you typed or that come from your purchases are not replaced.',
                  ),
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 11),
                ),
              ),
              const SizedBox(height: 8),
              for (final publication in _remaining)
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              PriceSyncService.instance
                                  .categoryFor(publication.category)
                                  .icon,
                              color: Colors.green.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                PriceSyncService.instance.categoryTitle(
                                  publication.category,
                                  lang,
                                ),
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_t(lang, 'عدد الأسعار', 'Nombre de prix', 'Prices')}: '
                          '${publication.rowCount} • ${date(publication.publishedAt)}',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                          ),
                        ),
                        if (publication.note.trim().isNotEmpty)
                          Text(
                            publication.note,
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                            ),
                          ),
                        const SizedBox(height: 6),
                        if (_busy.contains(publication.id))
                          const Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else
                          Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: () => _decide(publication, false),
                                child: Text(
                                  _t(lang, 'تجاهل', 'Ignorer', 'Ignore'),
                                ),
                              ),
                              FilledButton.icon(
                                icon: const Icon(Icons.check_rounded),
                                onPressed: () => _decide(publication, true),
                                label: Text(
                                  _t(
                                    lang,
                                    'قبول وتحديث الأسعار',
                                    'Accepter et mettre à jour',
                                    'Accept and update',
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _close,
          child: Text(_t(lang, 'لاحقاً', 'Plus tard', 'Later')),
        ),
      ],
    );
  }
}
