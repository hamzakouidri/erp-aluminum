import 'dart:convert';

import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';

/// Columns kept out of the readable journal: ids, links, sync stamps and
/// stored drawings mean nothing to the reader.
const Set<String> _hiddenColumns = {
  'id',
  'id_commandes',
  'sale_id',
  'achat_id',
  'client_id',
  'supplier_id',
  'location_id',
  'item_id',
  'color_id',
  'project_id',
  'partitions_json',
  'instances_json',
  'drawing_image_path',
  'items_json',
  'updated_at',
  'inserted_at',
  'deleted_at',
  'is_deleted',
  'stock_deducted',
  'source_sale_id',
  'converted_to_sale_id',
  'sort_order',
  'tax_rate',
  'system_name',
  'series_name',
  'last_editor_uid',
  'last_editor_version',
  'is_pinned',
  'pinned_at',
  'is_stock_reserved',
  'stock_reserved_at',
};

/// Readable lines of an audit entry's details, in [lang]. A before/after
/// snapshot reads in order: the document as it was, what changed, then the
/// document as it became; any other JSON becomes "label: value" lines; plain
/// text stays. Pure and synchronous.
List<String> formatAuditDetails(String raw, AppLanguage lang) {
  String t(String key) => Localization.translate(key, lang);
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return raw.split('\n');
  }
  if (decoded is! Map) {
    return decoded is List
        ? [for (final e in decoded) '• ${_value(e, lang)}']
        : [_value(decoded, lang)];
  }
  final map = Map<String, dynamic>.from(decoded);
  final before = map['before'];
  final after = map['after'];
  if (before is! Map) return _fieldLines(map, lang, indent: '');

  final beforeHeader = _asMap(before['header']);
  final beforeItems = _asList(before['items']);
  final lines = <String>['— ${t('audit_d_before')} —'];
  lines.addAll(_documentLines(beforeHeader, beforeItems, lang));
  if (after is Map) {
    final afterHeader = after.containsKey('header')
        ? _asMap(after['header'])
        : null;
    final afterItems = after.containsKey('items')
        ? _asList(after['items'])
        : null;
    lines
      ..add('')
      ..add('— ${t('audit_d_changes')} —');
    final changes = <String>[
      if (afterHeader != null)
        ..._fieldChanges(beforeHeader, afterHeader, lang, '  '),
      if (afterItems != null) ..._lineChanges(beforeItems, afterItems, lang),
    ];
    lines.addAll(changes.isEmpty ? ['  ${t('audit_d_no_changes')}'] : changes);
    // An edit form sends only the fields it changes: the rest of the
    // document stays as it was.
    lines
      ..add('')
      ..add('— ${t('audit_d_after')} —')
      ..addAll(
        _documentLines(
          {...beforeHeader, ...?afterHeader},
          afterItems ?? beforeItems,
          lang,
        ),
      );
  }
  return lines;
}

/// The fields of a document, then its lines.
List<String> _documentLines(
  Map<String, dynamic> header,
  List<Map<String, dynamic>> items,
  AppLanguage lang,
) => [
  for (final entry in header.entries)
    if (_shown(entry.key, entry.value) && !_isEmpty(entry.value))
      '  ${_label(entry.key, lang)}: ${_value(entry.value, lang)}',
  if (items.isNotEmpty) ...[
    '  ${Localization.translate('audit_d_lines', lang)} (${items.length}):',
    for (final item in items) '    • ${_lineSummary(item, lang)}',
  ],
];

bool _isEmpty(Object? v) => v == null || (v is String && v.trim().isEmpty);

Map<String, dynamic> _asMap(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> _asList(Object? v) => v is List
    ? [for (final e in v) _asMap(e)]
    : const <Map<String, dynamic>>[];

bool _shown(String key, Object? value) =>
    !_hiddenColumns.contains(key) &&
    value is! Map &&
    value is! List &&
    !(value is String && value.trim().startsWith('{'));

String _label(String key, AppLanguage lang) {
  final translated = Localization.translate('audit_f_$key', lang);
  return translated == 'audit_f_$key' ? key : translated;
}

String _value(Object? v, AppLanguage lang) {
  if (v == null || (v is String && v.trim().isEmpty)) {
    return Localization.translate('audit_d_empty_value', lang);
  }
  if (v is num) {
    return v == v.roundToDouble()
        ? v.toInt().toString()
        : v.toStringAsFixed(2);
  }
  final text = v.toString().trim();
  final date = RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(text)
      ? DateTime.tryParse(text)
      : null;
  if (date != null) {
    final d = date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
  if (v is Map || v is List) return jsonEncode(v);
  return Localization.translate(text, lang);
}

List<String> _fieldLines(
  Map<String, dynamic> map,
  AppLanguage lang, {
  required String indent,
}) => [
  for (final entry in map.entries)
    if (_shown(entry.key, entry.value))
      '$indent${_label(entry.key, lang)}: ${_value(entry.value, lang)}',
];

List<String> _fieldChanges(
  Map<String, dynamic> before,
  Map<String, dynamic> after,
  AppLanguage lang,
  String indent,
) {
  final out = <String>[];
  for (final key in {...before.keys, ...after.keys}) {
    if (!after.containsKey(key)) continue;
    final oldValue = before[key];
    final newValue = after[key];
    if (!_shown(key, oldValue) || !_shown(key, newValue)) continue;
    final oldText = _value(oldValue, lang);
    final newText = _value(newValue, lang);
    if (oldText == newText) continue;
    out.add('$indent${_label(key, lang)}: $oldText → $newText');
  }
  return out;
}

List<String> _lineChanges(
  List<Map<String, dynamic>> before,
  List<Map<String, dynamic>> after,
  AppLanguage lang,
) {
  String t(String key) => Localization.translate(key, lang);
  // Lines sent by an edit form may have no id yet: pair them by position.
  final byPosition = after.every((m) => m['id'] == null);
  final beforeKeys = [
    for (var i = 0; i < before.length; i++)
      byPosition ? '#$i' : before[i]['id']?.toString(),
  ];
  final afterKeys = [
    for (var i = 0; i < after.length; i++)
      byPosition ? '#$i' : after[i]['id']?.toString(),
  ];
  final beforeByKey = {
    for (var i = 0; i < before.length; i++)
      if (beforeKeys[i] != null) beforeKeys[i]!: before[i],
  };
  final out = <String>[];
  for (var i = 0; i < after.length; i++) {
    final line = after[i];
    final old = beforeByKey[afterKeys[i]];
    if (old == null) {
      out.add('  + ${t('audit_d_line_added')}: ${_lineSummary(line, lang)}');
      continue;
    }
    final fields = _fieldChanges(old, line, lang, '      ');
    if (fields.isNotEmpty) {
      out.add('  ~ ${t('audit_d_line_changed')}: ${_lineSummary(old, lang)}');
      out.addAll(fields);
    }
  }
  final kept = afterKeys.toSet();
  for (var i = 0; i < before.length; i++) {
    if (!kept.contains(beforeKeys[i])) {
      out.add(
        '  − ${t('audit_d_line_removed')}: ${_lineSummary(before[i], lang)}',
      );
    }
  }
  return out;
}

/// One order, sale or purchase line on one row: what, size, quantity, price.
String _lineSummary(Map<String, dynamic> line, AppLanguage lang) {
  String? text(String key) {
    final v = line[key];
    if (v == null || v.toString().trim().isEmpty) return null;
    return _value(v, lang);
  }

  final name =
      text('game') ??
      text('item_name') ??
      text('item_code') ??
      text('description') ??
      text('item_type') ??
      '';
  final parts = <String>[name];
  final w = text('largeur') ?? text('length_mm');
  final h = text('hauteur') ?? text('width_mm');
  if (w != null && h != null && w != '0' && h != '0') {
    parts.add('$w × $h mm');
  } else if (w != null && w != '0') {
    parts.add('$w mm');
  }
  final color = text('color') ?? text('color_name');
  if (color != null) parts.add(color);
  final qty = text('quantity');
  if (qty != null) parts.add('${_label('quantity', lang)} $qty');
  final price = text('total_price') ?? text('price') ?? text('unit_price');
  if (price != null) parts.add('$price DA');
  return parts.where((p) => p.isNotEmpty).join(' — ');
}
