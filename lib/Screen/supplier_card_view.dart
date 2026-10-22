import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../settings/app_settings.dart';
import '../sql_database.dart';

/// The supplier card: how to reach it (call, WhatsApp, e-mail, its place on
/// Google Maps), what it sells (set by hand) and what was already bought
/// from it (from the purchase invoices).
class SupplierCardView extends StatefulWidget {
  const SupplierCardView({super.key, required this.db, required this.supplier});

  final SqlDatabase db;
  final Map<String, dynamic> supplier;

  @override
  State<SupplierCardView> createState() => _SupplierCardViewState();
}

class _SupplierCardViewState extends State<SupplierCardView> {
  bool _loading = true;
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _purchased = [];

  static const _types = ['series', 'accessory', 'glass', 'other'];

  AppLanguage get _lang => context.read<AppSettingsProvider>().language;

  String _tr(String ar, String fr, String en) => switch (_lang) {
    AppLanguage.french => fr,
    AppLanguage.arabic => ar,
    _ => en,
  };

  int get _supplierId => (widget.supplier['id'] as num).toInt();

  String _text(String key) => (widget.supplier[key] ?? '').toString().trim();

  double? _coordinate(String key) {
    final value = widget.supplier[key];
    return value is num ? value.toDouble() : double.tryParse('${value ?? ''}');
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final products = await widget.db.readSupplierProducts(_supplierId);
    final purchased = await widget.db.readSupplierPurchasedGoods(
      _supplierId,
      _text('name'),
    );
    if (!mounted) return;
    setState(() {
      _products = products;
      _purchased = purchased;
      _loading = false;
    });
  }

  Future<void> _open(Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr('تعذر الفتح', "Impossible d'ouvrir", 'Could not open'),
          ),
        ),
      );
    }
  }

  /// WhatsApp wants the international number: a local Algerian number
  /// (0XXXXXXXXX) becomes 213XXXXXXXXX.
  String _whatsappNumber(String phone) {
    var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (digits.startsWith('0')) digits = '213${digits.substring(1)}';
    return digits;
  }

  String _typeLabel(String type) => switch (type) {
    'series' => _tr('سلسلة / نظام', 'Série / système', 'Series / system'),
    'accessory' => _tr('أكسسوار', 'Accessoire', 'Accessory'),
    'glass' => _tr('زجاج', 'Verre', 'Glass'),
    _ => _tr('أخرى', 'Autre', 'Other'),
  };

  IconData _typeIcon(String type) => switch (type) {
    'series' => Icons.view_column_rounded,
    'accessory' => Icons.handyman_rounded,
    'glass' => Icons.window_rounded,
    _ => Icons.inventory_2_rounded,
  };

  Future<List<({int id, String label})>> _catalogue(String type) async {
    final myDb = await widget.db.db;
    if (myDb == null) return const [];
    final rows = switch (type) {
      'series' => await myDb.rawQuery(
        'SELECT s.id, s.name, p.name AS profile FROM Series s '
        'LEFT JOIN Profile p ON p.id = s.profile_id '
        'WHERE COALESCE(s.is_active, 1) = 1 ORDER BY p.name, s.name',
      ),
      'accessory' => await myDb.rawQuery(
        'SELECT id, name, type AS profile FROM Accessories '
        'WHERE COALESCE(is_active, 1) = 1 ORDER BY name',
      ),
      'glass' => await myDb.rawQuery(
        'SELECT id, name, type AS profile FROM Glass '
        'WHERE COALESCE(is_active, 1) = 1 ORDER BY name',
      ),
      _ => const <Map<String, Object?>>[],
    };
    return [
      for (final row in rows)
        if (row['id'] is num)
          (
            id: (row['id'] as num).toInt(),
            label: [
              (row['profile'] ?? '').toString().trim(),
              (row['name'] ?? '').toString().trim(),
            ].where((part) => part.isNotEmpty).join(' — '),
          ),
    ];
  }

  Future<void> _addProduct() async {
    var type = 'series';
    var options = await _catalogue(type);
    final search = TextEditingController();
    final freeText = TextEditingController();
    final notes = TextEditingController();
    final picked = <int>{};
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final query = search.text.trim().toLowerCase();
          final visible = options
              .where(
                (o) => query.isEmpty || o.label.toLowerCase().contains(query),
              )
              .toList();
          return AlertDialog(
            title: Text(
              _tr(
                'إضافة ما يبيعه',
                'Ajouter un article vendu',
                'Add what it sells',
              ),
            ),
            content: SizedBox(
              width: 560,
              height: 460,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final option in _types)
                        ChoiceChip(
                          avatar: Icon(_typeIcon(option), size: 16),
                          label: Text(_typeLabel(option)),
                          selected: type == option,
                          onSelected: (_) async {
                            final next = await _catalogue(option);
                            setDialogState(() {
                              type = option;
                              options = next;
                              picked.clear();
                              search.clear();
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (type == 'other')
                    TextField(
                      controller: freeText,
                      decoration: InputDecoration(
                        labelText: _tr('ما يبيعه', 'Article', 'Item'),
                        border: const OutlineInputBorder(),
                      ),
                    )
                  else ...[
                    TextField(
                      controller: search,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: _tr('بحث', 'Rechercher', 'Search'),
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final option in visible)
                            CheckboxListTile(
                              dense: true,
                              value: picked.contains(option.id),
                              title: Text(option.label),
                              onChanged: (checked) => setDialogState(() {
                                if (checked == true) {
                                  picked.add(option.id);
                                } else {
                                  picked.remove(option.id);
                                }
                              }),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    controller: notes,
                    decoration: InputDecoration(
                      labelText: _tr(
                        'ملاحظة (اختياري)',
                        'Note (facultatif)',
                        'Note (optional)',
                      ),
                      isDense: true,
                      border: const OutlineInputBorder(),
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
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(_tr('إضافة', 'Ajouter', 'Add')),
              ),
            ],
          );
        },
      ),
    );
    if (saved != true) return;
    if (type == 'other') {
      if (freeText.text.trim().isEmpty) return;
      await widget.db.insertSupplierProduct(
        supplierId: _supplierId,
        itemType: type,
        label: freeText.text,
        notes: notes.text,
      );
    } else {
      for (final option in options.where((o) => picked.contains(o.id))) {
        await widget.db.insertSupplierProduct(
          supplierId: _supplierId,
          itemType: type,
          itemId: option.id,
          label: option.label,
          notes: notes.text,
        );
      }
    }
    await _load();
  }

  Widget _section(
    String title,
    IconData icon,
    List<Widget> children, {
    Widget? action,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.indigo),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                ?action,
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _contactCard() {
    final phone = _text('phone');
    final email = _text('email');
    final address = _text('address');
    final notes = _text('notes');
    final lat = _coordinate('latitude');
    final lng = _coordinate('longitude');
    final hasPlace = lat != null && lng != null;

    return _section(
      _tr('معلومات المورد', 'Coordonnées', 'Contact'),
      Icons.badge_rounded,
      [
        Text(
          _text('name'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        if (phone.isNotEmpty) ...[
          Row(
            children: [
              const Icon(Icons.phone_rounded, size: 18, color: Colors.grey),
              const SizedBox(width: 6),
              SelectableText(phone, style: const TextStyle(fontSize: 15)),
              IconButton(
                tooltip: _tr('نسخ', 'Copier', 'Copy'),
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () => Clipboard.setData(ClipboardData(text: phone)),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.call_rounded),
                label: Text(_tr('اتصال', 'Appeler', 'Call')),
                onPressed: () => _open(Uri(scheme: 'tel', path: phone)),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                ),
                icon: const Icon(Icons.chat_rounded),
                label: const Text('WhatsApp'),
                onPressed: () =>
                    _open(Uri.parse('https://wa.me/${_whatsappNumber(phone)}')),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        if (email.isNotEmpty)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.email_rounded),
            title: Text(email),
            onTap: () => _open(Uri(scheme: 'mailto', path: email)),
          ),
        if (address.isNotEmpty)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.home_work_rounded),
            title: Text(address),
          ),
        if (notes.isNotEmpty)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.notes_rounded),
            title: Text(notes),
          ),
        const Divider(),
        if (hasPlace) ...[
          Text(
            '📍 ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.map_rounded),
                label: Text(
                  _tr(
                    'فتح في خرائط Google',
                    'Ouvrir dans Google Maps',
                    'Open in Google Maps',
                  ),
                ),
                onPressed: () => _open(
                  Uri.parse(
                    'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
                  ),
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.directions_rounded),
                label: Text(_tr('الطريق إليه', 'Itinéraire', 'Directions')),
                onPressed: () => _open(
                  Uri.parse(
                    'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
                  ),
                ),
              ),
            ],
          ),
        ] else
          Text(
            _tr(
              'لم يُحدَّد موقعه: عدّل المورد واختر موقعه على الخريطة.',
              "Emplacement non défini : modifiez le fournisseur et choisissez-le sur la carte.",
              'No location set: edit the supplier and pick it on the map.',
            ),
            style: TextStyle(color: Colors.grey.shade700),
          ),
      ],
    );
  }

  Widget _productsCard() {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final product in _products) {
      grouped
          .putIfAbsent(product['item_type']?.toString() ?? 'other', () => [])
          .add(product);
    }
    return _section(
      _tr('ما يبيعه', 'Ce qu\'il vend', 'What it sells'),
      Icons.storefront_rounded,
      [
        if (_products.isEmpty)
          Text(
            _tr(
              'لم تُضف بعد ما يبيعه هذا المورد.',
              "Rien n'est encore ajouté pour ce fournisseur.",
              'Nothing added for this supplier yet.',
            ),
            style: TextStyle(color: Colors.grey.shade700),
          ),
        for (final type in _types)
          if (grouped[type] case final items?) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Text(
                _typeLabel(type),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final item in items)
                  InputChip(
                    avatar: Icon(_typeIcon(type), size: 16),
                    label: Text(
                      [
                        item['label']?.toString() ?? '',
                        if ((item['notes'] ?? '').toString().isNotEmpty)
                          '(${item['notes']})',
                      ].join(' '),
                    ),
                    onDeleted: () async {
                      await widget.db.deleteSupplierProduct(
                        (item['id'] as num).toInt(),
                      );
                      await _load();
                    },
                  ),
              ],
            ),
          ],
      ],
      action: FilledButton.tonalIcon(
        icon: const Icon(Icons.add_rounded),
        label: Text(_tr('إضافة', 'Ajouter', 'Add')),
        onPressed: _addProduct,
      ),
    );
  }

  Widget _purchasedCard() {
    String number(Object? value) {
      final n = value is num
          ? value.toDouble()
          : double.tryParse('${value ?? ''}') ?? 0;
      return n == n.roundToDouble()
          ? n.toStringAsFixed(0)
          : n.toStringAsFixed(2);
    }

    String date(Object? value) {
      final parsed = DateTime.tryParse('${value ?? ''}');
      if (parsed == null) return '-';
      final local = parsed.toLocal();
      return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
    }

    return _section(
      _tr('ما اشتريته منه', 'Déjà acheté chez lui', 'Already bought from it'),
      Icons.receipt_long_rounded,
      [
        if (_purchased.isEmpty)
          Text(
            _tr(
              'لا توجد فواتير شراء من هذا المورد.',
              "Aucune facture d'achat chez ce fournisseur.",
              'No purchase invoice from this supplier.',
            ),
            style: TextStyle(color: Colors.grey.shade700),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 18,
              columns: [
                DataColumn(label: Text(_tr('السلعة', 'Article', 'Item'))),
                DataColumn(label: Text(_tr('الكود', 'Code', 'Code'))),
                DataColumn(
                  numeric: true,
                  label: Text(_tr('الكمية', 'Quantité', 'Quantity')),
                ),
                DataColumn(
                  numeric: true,
                  label: Text(_tr('آخر سعر', 'Dernier prix', 'Last price')),
                ),
                DataColumn(
                  label: Text(
                    _tr('آخر شراء', 'Dernier achat', 'Last purchase'),
                  ),
                ),
                DataColumn(
                  numeric: true,
                  label: Text(_tr('الفواتير', 'Factures', 'Invoices')),
                ),
              ],
              rows: [
                for (final row in _purchased)
                  DataRow(
                    cells: [
                      DataCell(Text(row['item_name']?.toString() ?? '')),
                      DataCell(Text(row['item_code']?.toString() ?? '')),
                      DataCell(Text(number(row['quantity']))),
                      DataCell(Text(number(row['last_price']))),
                      DataCell(Text(date(row['last_date']))),
                      DataCell(Text(number(row['invoices']))),
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppSettingsProvider>();
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _contactCard(),
          _productsCard(),
          _purchasedCard(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
