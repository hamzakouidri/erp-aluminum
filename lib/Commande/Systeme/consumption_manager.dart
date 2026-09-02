import 'dart:convert';

import 'package:database_data/Commande/Systeme/bom_engine_v2.dart';
import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/consumption_item.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter/foundation.dart';

class ConsumptionReport {
  final List<CuttingItem> aluminumItems;
  final List<CuttingItem> glassItems;
  final List<CuttingItem> accessoryItems;
  final double totalSellingPrice;
  final double exactCost;
  final double fullBarCost;
  final int totalScrewsCount;

  ConsumptionReport({
    required this.aluminumItems,
    required this.glassItems,
    required this.accessoryItems,
    required this.totalSellingPrice,
    required this.exactCost,
    required this.fullBarCost,
    required this.totalScrewsCount,
  });
}

/// Keeps the old report API while using the rule-first BOM as its only source.
class ConsumptionManager {
  ConsumptionManager(this.db);

  final SqlDatabase db;

  Future<ConsumptionReport> generateReport(int commandeId) async {
    final details = await db.readCommandeDetails(commandeId);
    final reports = <ConsumptionReport>[];
    for (final detail in details) {
      final rawJson = detail['partitions_json']?.toString() ?? '';
      if (rawJson.trim().isEmpty) continue;
      try {
        final data = jsonDecode(rawJson);
        if (data is! Map) continue;
        final window = WindowModel(db: db);
        applyWindowModelFromMap(window, Map<String, dynamic>.from(data));
        final rawQuantity = detail['quantite'];
        final quantity = rawQuantity is num
            ? rawQuantity.toInt()
            : int.tryParse('$rawQuantity') ?? 1;
        reports.add(
          await _reportForWindow(window, quantity < 1 ? 1 : quantity),
        );
      } catch (error) {
        debugPrint('Error building catalogue consumption report: $error');
      }
    }
    return _mergeReports(reports);
  }

  Future<ConsumptionReport> generateReportFromLiveModel(
    WindowModel window,
    int quantity,
  ) {
    return _reportForWindow(window, quantity < 1 ? 1 : quantity);
  }

  Future<ConsumptionReport> _reportForWindow(
    WindowModel window,
    int quantity,
  ) async {
    final engine = BomEngineV2(database: db);
    var bom = ComponentCalculator.generateBom(window, const {});
    await engine.stabilizeSelections(window: window, items: bom);
    bom = ComponentCalculator.generateBom(window, const {});
    await engine.stabilizeSelections(window: window, items: bom);
    bom = await engine.filterItemsByAvailableCandidates(
      window: window,
      items: ComponentCalculator.generateBom(window, const {}),
    );

    final items = <CuttingItem>[];
    var exactCost = 0.0;
    var fullBarCost = 0.0;
    for (final item in bom.where((item) => item.isActive)) {
      final scaledRequired = item.requiredQuantity * quantity;
      final scaledPurchase = item.purchaseQuantity * quantity;
      if (scaledRequired <= 0 || item.catalogItemId == null) continue;
      exactCost += scaledRequired * item.unitPrice;
      fullBarCost += scaledPurchase * item.unitPrice;
      items.add(_toCuttingItem(item, quantity));
    }

    final aggregated = _aggregateItems(items);
    return ConsumptionReport(
      aluminumItems: aggregated
          .where(
            (item) =>
                item.type == CuttingItemType.profileFrame ||
                item.type == CuttingItemType.profileSash,
          )
          .toList(),
      glassItems: aggregated
          .where((item) => item.type == CuttingItemType.glass)
          .toList(),
      accessoryItems: aggregated
          .where((item) => item.type == CuttingItemType.accessory)
          .toList(),
      // This report has no independent selling-price catalogue. Do not invent
      // a mark-up when the only authoritative value is the catalogue price.
      totalSellingPrice: exactCost,
      exactCost: exactCost,
      fullBarCost: fullBarCost,
      totalScrewsCount: 0,
    );
  }

  CuttingItem _toCuttingItem(BomItem item, int multiplier) {
    final role = (item.roleKey ?? item.selectorType ?? '').trim().toLowerCase();
    final type = item.category == 'profile'
        ? (role == 'frame' || role == 'frame_extension'
              ? CuttingItemType.profileFrame
              : CuttingItemType.profileSash)
        : item.category == 'glass' || item.category == 'panneau'
        ? CuttingItemType.glass
        : CuttingItemType.accessory;
    final length = item.length ?? 0.0;
    final normalizedUnit = item.unit.toLowerCase();
    final isLinear =
        normalizedUnit == 'متر' ||
        normalizedUnit == 'm' ||
        normalizedUnit == 'ml';
    final width = isLinear ? length * 1000.0 : length;
    final quantity = (item.purchaseQuantity * multiplier).ceil();
    final description = [
      if (item.profileCode?.trim().isNotEmpty == true) item.profileCode!.trim(),
      if (item.cuttingList?.trim().isNotEmpty == true) item.cuttingList!.trim(),
      item.unit,
    ].join(' | ');
    return CuttingItem(
      name: item.name,
      description: description,
      width: width,
      height: item.glassHeight ?? 0.0,
      quantity: quantity,
      type: type,
      isMissing: item.isMissing || item.unitPrice <= 0,
      price: item.unitPrice,
    );
  }

  ConsumptionReport _mergeReports(List<ConsumptionReport> reports) {
    final aluminum = <CuttingItem>[];
    final glass = <CuttingItem>[];
    final accessories = <CuttingItem>[];
    var selling = 0.0;
    var exact = 0.0;
    var full = 0.0;
    var screws = 0;
    for (final report in reports) {
      aluminum.addAll(report.aluminumItems);
      glass.addAll(report.glassItems);
      accessories.addAll(report.accessoryItems);
      selling += report.totalSellingPrice;
      exact += report.exactCost;
      full += report.fullBarCost;
      screws += report.totalScrewsCount;
    }
    return ConsumptionReport(
      aluminumItems: _aggregateItems(aluminum),
      glassItems: _aggregateItems(glass),
      accessoryItems: _aggregateItems(accessories),
      totalSellingPrice: selling,
      exactCost: exact,
      fullBarCost: full,
      totalScrewsCount: screws,
    );
  }

  List<CuttingItem> _aggregateItems(List<CuttingItem> items) {
    final grouped = <String, CuttingItem>{};
    for (final item in items) {
      final key = [
        item.name,
        item.width.toStringAsFixed(2),
        item.height.toStringAsFixed(2),
        item.price.toStringAsFixed(4),
      ].join('|');
      final existing = grouped[key];
      if (existing == null) {
        grouped[key] = item;
        continue;
      }
      grouped[key] = CuttingItem(
        name: existing.name,
        description: existing.description,
        width: existing.width,
        height: existing.height,
        quantity: existing.quantity + item.quantity,
        type: existing.type,
        isMissing: existing.isMissing || item.isMissing,
        price: existing.price,
      );
    }
    return grouped.values.toList();
  }
}
