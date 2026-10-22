part of '../show_system_francais.dart';

/// The catalogue parts that can be used for one drawing accessory ([slot]):
/// every part of its exact category fitting the drawing, with its free stock
/// in the drawing's accessory colour. Parts that cover [needed] come first.
/// Tapping a part makes it the choice shared with the cost table.
class _AccessoryPartsRow extends StatefulWidget {
  final WindowModel model;
  final DrawingAccessorySlot slot;
  final int needed;
  final VoidCallback onChanged;

  const _AccessoryPartsRow({
    super.key,
    required this.model,
    required this.slot,
    required this.needed,
    required this.onChanged,
  });

  @override
  State<_AccessoryPartsRow> createState() => _AccessoryPartsRowState();
}

class _AccessoryPartsRowState extends State<_AccessoryPartsRow> {
  late Future<List<({Map<String, dynamic> part, double free})>> _parts;
  String _loadedFor = '';

  String get _context =>
      '${widget.slot.bomKey}|${widget.slot.category}|'
      '${widget.model.activeSeries?.id}|${widget.model.isPVC}|'
      '${widget.model.selectedAccessoryColor?['id']}';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant _AccessoryPartsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_context != _loadedFor) _reload();
  }

  void _reload() {
    _loadedFor = _context;
    _parts = _load();
  }

  Future<List<({Map<String, dynamic> part, double free})>> _load() async {
    final parts = await widget.model.accessoryCandidates(widget.slot.category);
    final colorId = widget.model.selectedAccessoryColor?['id'];
    final stock = await widget.model.db.readFreeAccessoryStock(
      [
        for (final part in parts)
          if (part['id'] is num) (part['id'] as num).toInt(),
      ],
      colorId: colorId is num ? colorId.toInt() : int.tryParse('$colorId'),
    );
    final rows = [
      for (final part in parts)
        (part: part, free: stock[(part['id'] as num?)?.toInt()] ?? 0.0),
    ];
    // Enough stock first, then too little, then none; by name inside.
    int rank(double free) => free >= widget.needed ? 0 : (free > 0 ? 1 : 2);
    rows.sort((a, b) {
      final byStock = rank(a.free).compareTo(rank(b.free));
      if (byStock != 0) return byStock;
      return '${a.part['name']}'.compareTo('${b.part['name']}');
    });
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    String t(String key) => Localization.translate(key, lang);
    return FutureBuilder<List<({Map<String, dynamic> part, double free})>>(
      future: _parts,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }
        final rows = snapshot.data ?? const [];
        if (rows.isEmpty) {
          return Text(
            t('لا توجد قطع من هذا التصنيف تناسب السلسلة'),
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          );
        }
        final current = widget.model.componentOverrides[widget.slot.bomKey];
        final chosen = widget.model.isAccessoryChosen(widget.slot.bomKey);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final row in rows) ...[
              _AccessoryPartCard(
                part: row.part,
                free: row.free,
                needed: widget.needed,
                selected:
                    current != null &&
                    current['id']?.toString() == row.part['id']?.toString(),
                isDefault: !chosen,
                onPressed: () async {
                  await widget.model.setAccessoryChoice(
                    widget.slot.bomKey,
                    row.part,
                  );
                  if (mounted) setState(() {});
                  widget.onChanged();
                },
              ),
              const SizedBox(width: 8),
            ],
            if (chosen)
              TextButton.icon(
                onPressed: () async {
                  await widget.model.clearAccessoryChoice(widget.slot.bomKey);
                  if (mounted) setState(() {});
                  widget.onChanged();
                },
                icon: const Icon(Icons.restart_alt_rounded, size: 16),
                label: Text(t('الافتراضي'), style: const TextStyle(fontSize: 12)),
              ),
          ],
        );
      },
    );
  }
}

class _AccessoryPartCard extends StatelessWidget {
  final Map<String, dynamic> part;
  final double free;
  final int needed;
  final bool selected;
  final bool isDefault;
  final VoidCallback onPressed;

  const _AccessoryPartCard({
    required this.part,
    required this.free,
    required this.needed,
    required this.selected,
    required this.isDefault,
    required this.onPressed,
  });

  /// The products page appends the quality to the name, e.g. "X (جودة رفيعة)".
  static final _qualitySuffix = RegExp(r'\s*\(\s*جودة\s+[^)]*\)\s*$');

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    String t(String key) => Localization.translate(key, lang);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = '${part['name'] ?? ''}'.replaceAll(_qualitySuffix, '').trim();
    final quality = AccessoryCategory.qualityOf(part['type']);
    final amount = free == free.roundToDouble()
        ? free.toInt().toString()
        : free.toStringAsFixed(1);
    final (String stockLabel, Color stockColor) = free <= 0
        ? (t('غير متوفر'), Colors.grey)
        : free < needed
        ? ('${t('غير كافٍ')}: $amount', Colors.orange.shade800)
        : ('${t('متوفر')}: $amount', Colors.green.shade700);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? (isDark
                    ? Colors.blue.shade900.withValues(alpha: 0.3)
                    : Colors.blue.shade50)
              : (isDark ? const Color(0xFF2E2E3E) : Colors.white),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? Colors.blue
                : (isDark ? Colors.white24 : Colors.grey.shade300),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SectionImageWidget(
                name: name,
                imagePath: part['image_path']?.toString(),
                size: 24.0,
                fallbackIcon: Icons.image_not_supported_rounded,
                fallbackColor: selected
                    ? Colors.blue.shade600
                    : Colors.grey.shade400,
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: isDark
                        ? Colors.white
                        : (selected
                              ? Colors.blue.shade900
                              : Colors.grey.shade800),
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      stockLabel,
                      style: TextStyle(
                        color: stockColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (quality.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        t(quality),
                        style: TextStyle(
                          color: isDark ? Colors.white60 : Colors.grey.shade600,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    if (selected && isDefault) ...[
                      const SizedBox(width: 6),
                      Text(
                        t('افتراضي'),
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
