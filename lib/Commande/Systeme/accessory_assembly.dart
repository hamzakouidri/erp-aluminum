import 'model.dart';

const assemblyAccessoryRoles = <String>{
  'clam',
  'clamp', // legacy spelling
  'frame_clamp',
  'sash_clamp',
  'frame_clamp_support',
  'sash_clamp_support',
  'sliding_clamp',
  'assembly_screw',
};

class AssemblyDemand {
  const AssemblyDemand({
    required this.target,
    required this.sliding,
    required this.topCorners,
    required this.bottomCorners,
    this.topMiterCorners,
    this.bottomMiterCorners,
    this.sectionId,
  });

  final String target;
  final bool sliding;
  final int topCorners;
  final int bottomCorners;
  final int? topMiterCorners;
  final int? bottomMiterCorners;
  final int? sectionId;

  /// الزوايا المقطوعة بـ 45 درجة فقط المؤهلة لتركيب الكلام (Clam)
  int get effectiveTopMiterCorners => topMiterCorners ?? topCorners;

  int get effectiveBottomMiterCorners => bottomMiterCorners ?? bottomCorners;
}

int? assemblyInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse('${value ?? ''}');

Set<int> assemblySectionIds(Map<String, dynamic> rule) {
  final ids = <int>{};
  final raw = '${rule['assembly_section_ids'] ?? ''}'.trim();
  for (final token in raw.split(',')) {
    final id = int.tryParse(token.trim());
    if (id != null && id > 0) ids.add(id);
  }
  final legacyId = assemblyInt(rule['assembly_section_id']);
  if (legacyId != null && legacyId > 0) ids.add(legacyId);
  // Per-section quantities are themselves explicit section bindings.
  ids.addAll(assemblySectionSideQuantities(rule).keys);
  return ids;
}

Map<int, int> assemblySectionCornerQuantities(Map<String, dynamic> rule) {
  return {
    for (final entry in assemblySectionSideQuantities(rule).entries)
      entry.key: entry.value.$1,
  };
}

/// Per linked profile: screws/accessories used at its first and second end.
/// Legacy `section:quantity` values apply the same quantity to both ends.
Map<int, (int, int)> assemblySectionSideQuantities(Map<String, dynamic> rule) {
  final result = <int, (int, int)>{};
  final raw = '${rule['assembly_section_quantities'] ?? ''}'.trim();
  for (final token in raw.split(',')) {
    final parts = token.split(':');
    if (parts.length != 2 && parts.length != 3) continue;
    final sectionId = int.tryParse(parts[0].trim());
    final firstSide = int.tryParse(parts[1].trim());
    final secondSide = parts.length == 3
        ? int.tryParse(parts[2].trim())
        : firstSide;
    if (sectionId != null &&
        sectionId > 0 &&
        firstSide != null &&
        firstSide >= 0 &&
        secondSide != null &&
        secondSide >= 0) {
      result[sectionId] = (firstSide, secondSide);
    }
  }
  return result;
}

/// Every catalogue section that is physically selected in the drawing.
Set<int> drawingSectionIds(WindowModel window) {
  final ids = <int>{};
  void add(dynamic value) {
    if (value is! Map) return;
    final id = assemblyInt(value['id']);
    if (id != null && id > 0 && value.containsKey('code')) ids.add(id);
  }

  add(window.frameOverride);
  add(window.slidingFrameOverride);
  add(window.sashOverride);
  add(window.slidingSashOverride);
  add(window.sideCoverOverride);
  add(window.internalSlidingSideCoverOverride);
  for (final value in window.componentOverrides.values) {
    add(value);
  }
  for (final demand in assemblyDemands(window)) {
    final id = demand.sectionId;
    if (id != null && id > 0) ids.add(id);
  }
  return ids;
}

/// Physical corners, independent of glazing cells and catalogue item names.
List<AssemblyDemand> assemblyDemands(WindowModel window) {
  if (window.isShutterOnly) return [];
  final demands = <AssemblyDemand>[];
  int? sectionId(bool sliding, bool frame) {
    final section = frame
        ? (sliding
              ? window.getSlidingBaseFrameSection()?.toMap() ??
                    window.slidingFrameOverride
              : window.frameOverride ??
                    window.getSectionByType('frame')?.toMap())
        : (sliding
              ? window.slidingSashOverride ??
                    window.getSlidingSectionByType('sash')?.toMap()
              : window.sashOverride ??
                    window.getSectionByType('sash')?.toMap());
    return assemblyInt(section?['id']);
  }

  for (final rect in window.getFrameRects()) {
    final zones = window.zones.where(
      (zone) => rect.contains(zone.boundary.center),
    );
    final sliding =
        window.usesSlidingPrimaryProfiles ||
        (zones.isNotEmpty &&
            zones.every((z) => z.content == ZoneContent.slidingSash));

    // زوايا الإطار 45° للكلام: إذا كانت هناك زاوية 90° (profileAngleMode) يُلغى الكلام منها
    int topMiter = 2;
    int bottomMiter = !window.hasBottomFrameForRect(rect) ? 0 : 2;
    if (window.profileAngleMode == 1 || window.profileAngleMode == 2) {
      topMiter = 1;
      if (bottomMiter > 0) bottomMiter = 1;
    } else if (window.profileAngleMode == 3) {
      topMiter = 0;
      bottomMiter = 0;
    }

    demands.add(
      AssemblyDemand(
        target: 'frame',
        sliding: sliding,
        topCorners: 2,
        bottomCorners: !window.hasBottomFrameForRect(rect) ? 0 : 2,
        topMiterCorners: topMiter,
        bottomMiterCorners: bottomMiter,
        sectionId: sectionId(sliding, true),
      ),
    );
  }

  void addSashes(int count, bool sliding, {int? miterTop, int? miterBottom}) {
    if (count <= 0) return;
    demands.add(
      AssemblyDemand(
        target: 'sash',
        sliding: sliding,
        topCorners: count * 2,
        bottomCorners: count * 2,
        topMiterCorners: miterTop ?? (count * 2),
        bottomMiterCorners: miterBottom ?? (count * 2),
        sectionId: sectionId(sliding, false),
      ),
    );
  }

  for (final zone in window.zones) {
    final sliding = zone.content == ZoneContent.slidingSash;
    if (sliding) {
      final sashes = zone.slidingSashesCount > 0 ? zone.slidingSashesCount : 2;
      int slidingTopMiter = 0;
      int slidingBottomMiter = 0;

      // فحص كل ظلفة: هل تتصل بمونتوسليم (MontoSlim) يلغي الكلام ببراغي التجميع؟
      for (int s = 0; s < sashes; s++) {
        final bool leftIsSlim =
            s > 0 &&
            (zone.slidingMontantSlim['central_${(s - 1) * 2 + 1}'] ?? false);
        final bool rightIsSlim =
            s < (sashes - 1) &&
            (zone.slidingMontantSlim['central_${s * 2}'] ?? false);

        // الجانب الذي ليس فيه مونتوسليم يكون 45° ويأخذ كلام
        if (!leftIsSlim) {
          slidingTopMiter += 1;
          slidingBottomMiter += 1;
        }
        if (!rightIsSlim) {
          slidingTopMiter += 1;
          slidingBottomMiter += 1;
        }
      }

      addSashes(
        sashes,
        true,
        miterTop: slidingTopMiter,
        miterBottom: slidingBottomMiter,
      );
    } else {
      final count = switch (zone.content) {
        ZoneContent.singleSash => 1,
        ZoneContent.doubleSash => 2,
        _ => 0,
      };
      addSashes(count, false);
      final nestedKeys = {
        ...zone.cellIsSash.keys,
        ...zone.cellIsDoubleSash.keys,
      };
      for (final key in nestedKeys) {
        addSashes(
          zone.cellIsDoubleSash[key] == true
              ? 2
              : zone.cellIsSash[key] == true
              ? 1
              : 0,
          false,
        );
      }
    }
  }
  return demands;
}

String defaultAssemblyTarget(String role) {
  if (role.startsWith('frame_')) return 'frame';
  if (role == 'clam' || role == 'clamp') return 'both';
  return 'sash';
}

int assemblyQuantity(
  Map<String, dynamic> rule,
  Iterable<AssemblyDemand> demands,
) {
  final role = '${rule['role_key'] ?? ''}'.trim().toLowerCase();
  final perCornerClamp =
      assemblyAccessoryRoles.contains(role) && role != 'assembly_screw';
  final isClam = const {
    'clam',
    'clamp',
    'sliding_clamp',
    'frame_clamp',
    'sash_clamp',
    'frame_clamp_support',
    'sash_clamp_support',
  }.contains(role);

  final configuredTarget = '${rule['assembly_target'] ?? ''}';
  final target = const {'frame', 'sash', 'both'}.contains(configuredTarget)
      ? configuredTarget
      : defaultAssemblyTarget(role);
  final linkedSections = assemblySectionIds(rule);
  final sectionSideQuantities = assemblySectionSideQuantities(rule);
  final top = (assemblyInt(rule['top_corner_qty']) ?? 1).clamp(0, 100000);
  final bottom = (assemblyInt(rule['bottom_corner_qty']) ?? 1).clamp(0, 100000);
  var quantity = 0;
  for (final demand in demands) {
    if (perCornerClamp && demand.target != 'frame' && demand.target != 'sash') {
      continue;
    }
    if (linkedSections.isNotEmpty) {
      if (!linkedSections.contains(demand.sectionId)) continue;
    } else {
      if (target != 'both' && target != demand.target) continue;
    }

    // إذا كان العنصر هو الكلام (Clam)، نستخدم حصراً زوايا الـ 45°
    // زوايا الـ 90° والمونتوسليم التي بها براغي تجميع تلغي الكلام تماماً
    final topCorners = isClam
        ? demand.effectiveTopMiterCorners
        : demand.topCorners;
    final bottomCorners = isClam
        ? demand.effectiveBottomMiterCorners
        : demand.bottomCorners;

    final sectionQuantities = demand.sectionId == null
        ? null
        : sectionSideQuantities[demand.sectionId];

    if (perCornerClamp &&
        sectionQuantities != null &&
        (demand.target == 'frame' || demand.target == 'sash')) {
      final perCorner = sectionQuantities.$1;
      quantity += (topCorners + bottomCorners) * perCorner;
    } else if (sectionQuantities != null) {
      quantity +=
          topCorners * sectionQuantities.$1 +
          bottomCorners * sectionQuantities.$2;
    } else {
      quantity += topCorners * top + bottomCorners * bottom;
    }
  }
  return quantity;
}
