import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/profile_selector_dialog.dart';

/// What a profile row of the required-goods page replaces.
enum ProfileSwapKind { frame, sash, sideCover, other }

String _rowText(BomItem bom) =>
    '${bom.roleKey ?? ''} ${bom.selectorType ?? ''} ${bom.originalName}'
        .toLowerCase();

ProfileSwapKind profileSwapKind(BomItem bom) {
  final role = (bom.roleKey ?? '').trim().toLowerCase();
  final selector = (bom.selectorType ?? '').trim().toLowerCase();
  if (selector == 'frame' || role == 'frame') return ProfileSwapKind.frame;
  if (selector == 'sash' || role == 'sash') return ProfileSwapKind.sash;
  final text = _rowText(bom);
  if (selector == 'side_cover' ||
      role == 'side_cover' ||
      text.contains('غطاء جانبي') ||
      text.contains('الغطاء الجانبي') ||
      text.contains('side cover') ||
      text.contains('couvre')) {
    return ProfileSwapKind.sideCover;
  }
  return ProfileSwapKind.other;
}

/// The series roles whose profiles may replace [bom]: the same role only,
/// as in the drawing page (a sash row offers the sashes of the series, a
/// parclose row its parcloses). Empty when the role is unknown.
List<String> profileSwapRoleKeys(BomItem bom) {
  switch (profileSwapKind(bom)) {
    case ProfileSwapKind.frame:
      return const ['frame'];
    case ProfileSwapKind.sash:
      return const ['sash'];
    case ProfileSwapKind.sideCover:
      return const ['side_cover'];
    case ProfileSwapKind.other:
      break;
  }
  final role = (bom.roleKey ?? '').trim().toLowerCase();
  final text = _rowText(bom);
  if (text.contains('plinthe') || text.contains('بلانت') || role == 'plant') {
    return const ['plant'];
  }
  if (role == 'complement_haut_base' || text.contains('complément haut')) {
    return const ['complement_haut_base'];
  }
  if (role == 'montant_central_slim' || role == 'sash_central_slim') {
    return const ['montant_central_slim', 'sash_central_slim'];
  }
  // A montant can be changed in both directions (regular <-> reinforced).
  if (role.startsWith('sash_lateral') || role == 'lateral') {
    return const ['sash_lateral', 'sash_lateral_reinforced'];
  }
  if (role.startsWith('sash_central') || role == 'central') {
    return const ['sash_central', 'sash_central_reinforced'];
  }
  if (role.isNotEmpty) {
    final mapped = seriesRoleKeysForProfileSelectorType(role);
    return mapped.isNotEmpty ? mapped : [role];
  }
  return seriesRoleKeysForProfileSelectorType(
    (bom.selectorType ?? '').trim().isNotEmpty
        ? bom.selectorType!
        : bom.originalName,
  );
}

bool _isPvc(String value) => value == 'pvc' || value == 'upvc';

/// Whether [candidate] is made of the material of the drawing: a PVC
/// profile never replaces an aluminium one, nor the reverse.
bool profileSwapMaterialMatches(
  Map<String, dynamic> candidate,
  String? materialType,
) {
  final wanted = (materialType ?? '').trim().toLowerCase();
  final own = (candidate['material_type'] ?? '').toString().trim().toLowerCase();
  if (own.isEmpty || own == 'both' || wanted.isEmpty) return true;
  return _isPvc(wanted) == _isPvc(own);
}

bool? _optionalBool(Object? raw) {
  if (raw == null) return null;
  if (raw is bool) return raw;
  if (raw is num) return raw != 0;
  final normalized = raw.toString().trim().toLowerCase();
  if (normalized == '1' || normalized == 'true' || normalized == 'yes') {
    return true;
  }
  if (normalized == '0' || normalized == 'false' || normalized == 'no') {
    return false;
  }
  return null;
}

bool _frameHasIntegratedCover(Map<String, dynamic> frame) =>
    _optionalBool(
      frame['design_integrated_side_cover'] ?? frame['integrated_side_cover'],
    ) ??
    profileHasIntegratedSideCover(frame);

bool _frameTakesSeparateCover(Map<String, dynamic> frame) =>
    !_frameHasIntegratedCover(frame) &&
    _optionalBool(
          frame['design_allows_side_cover'] ?? frame['allows_side_cover'],
        ) !=
        false;

/// Whether the drawing shows side covers once its frame [oldFrame] is
/// replaced by [newFrame] from the required-goods page:
/// - a frame with a built-in cover always shows its cover;
/// - a frame that takes no separate cover removes the side cover;
/// - leaving a frame that took no cover for one that takes a separate
///   cover adds the side cover;
/// - otherwise the drawing keeps what it had.
bool sideCoversAfterFrameSwap({
  required bool hadSideCovers,
  required Map<String, dynamic>? oldFrame,
  required Map<String, dynamic> newFrame,
}) {
  if (_frameHasIntegratedCover(newFrame)) return true;
  if (!_frameTakesSeparateCover(newFrame)) return false;
  if (oldFrame != null &&
      !_frameHasIntegratedCover(oldFrame) &&
      !_frameTakesSeparateCover(oldFrame)) {
    return true;
  }
  return hadSideCovers;
}
