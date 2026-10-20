/// Display order of the profile rows, shared by the required-goods page and
/// the quantity & cost table so both list the profiles the same way:
/// frame, its reinforcement, side covers, frame complement, sashes, their
/// reinforcement, sash complement, battement, parclose, division, its
/// reinforcement, plinthe and porte-joint, then everything else.
library;

const int profileRankFrame = 0;
const int profileRankFrameRenfort = 1;
const int profileRankSideCover = 2;
const int profileRankFrameComplement = 3;
const int profileRankSash = 4;
const int profileRankSashRenfort = 5;
const int profileRankSashComplement = 6;
const int profileRankBatmo = 7;
const int profileRankParclose = 8;
const int profileRankMullion = 9;
const int profileRankMullionRenfort = 10;
const int profileRankPlinthe = 11;
const int profileRankOther = 100;

const Map<String, int> _rankByRole = {
  'frame': profileRankFrame,
  'cadre': profileRankFrame,
  'dormant': profileRankFrame,
  'side_cover': profileRankSideCover,
  'frame_extension': profileRankFrameComplement,
  'sash': profileRankSash,
  'ouvrant': profileRankSash,
  'sash_lateral': profileRankSash,
  'sash_lateral_reinforced': profileRankSash,
  'sash_central': profileRankSash,
  'sash_central_reinforced': profileRankSash,
  'sash_central_slim': profileRankSash,
  'montant_central_slim': profileRankSash,
  'sash_traverse': profileRankSash,
  'chicane': profileRankSash,
  'chicane_renforcee': profileRankSash,
  'lateral': profileRankSash,
  'central': profileRankSash,
  'sash_extension': profileRankSashComplement,
  'complement_haut_base': profileRankSashComplement,
  'batmo': profileRankBatmo,
  'glazing_bead': profileRankParclose,
  'parclose': profileRankParclose,
  'mullion': profileRankMullion,
  'traverse': profileRankMullion,
  'plant': profileRankPlinthe,
  'porte_joint': profileRankPlinthe,
};

bool _hasAny(String text, List<String> terms) => terms.any(text.contains);

/// The display rank of a profile row, from its explicit role first and its
/// generated name otherwise.
int profileDisplayRank({
  String? roleKey,
  String? selectorType,
  String originalName = '',
}) {
  final role = (roleKey ?? '').trim().toLowerCase();
  final selector = (selectorType ?? '').trim().toLowerCase();
  final text = '$role $selector ${originalName.toLowerCase()}';

  // Covers, plugs and screws of a profile are not that profile.
  if (_hasAny(text, const [
    'cache_renfort',
    'cache renfort',
    'cache_dormant',
    'cache dormant',
    'renfort_screw',
    'bouchon',
    'بوشون',
    'screw',
    'براغي',
  ])) {
    return profileRankOther;
  }

  final isRenfort =
      role == 'renfort' ||
      role == 'independent_renfort' ||
      _hasAny(text, const ['renfort', 'حديد']);
  if (isRenfort) {
    if (_hasAny(text, const ['frame', 'cadre', 'dormant', 'الإطار', 'الاطار'])) {
      return profileRankFrameRenfort;
    }
    if (_hasAny(text, const [
      'mullion',
      'traverse',
      'montant',
      'meneau',
      'تقسيم',
    ])) {
      return profileRankMullionRenfort;
    }
    if (_hasAny(text, const [
      'sash',
      'ouvrant',
      'الظلفة',
      'الضلفة',
      'ظلفة',
      'ضلفة',
    ])) {
      return profileRankSashRenfort;
    }
    return profileRankOther;
  }

  final explicit = _rankByRole[role] ?? _rankByRole[selector];
  if (explicit != null) return explicit;

  if (_hasAny(text, const [
    'couvre',
    'side cover',
    'side_cover',
    'غطاء جانبي',
    'الغطاء الجانبي',
    'الأغطية الجانبية',
  ])) {
    return profileRankSideCover;
  }
  if (_hasAny(text, const [
    'complément dormant',
    'complement dormant',
    'complément cadre',
    'complement cadre',
    'كومبليمو دورمو',
  ])) {
    return profileRankFrameComplement;
  }
  if (_hasAny(text, const [
    'complément ouvrant',
    'complement ouvrant',
    'complément haut',
    'complement haut',
    'مكمل الضلفة',
  ])) {
    return profileRankSashComplement;
  }
  if (_hasAny(text, const ['batmo', 'battement', 'باتمو', 'باطمو'])) {
    return profileRankBatmo;
  }
  if (_hasAny(text, const [
    'parclose',
    'glazing',
    'باركلوز',
    'بركلوز',
    'بيركلوز',
  ])) {
    return profileRankParclose;
  }
  if (_hasAny(text, const ['mullion', 'meneau', 'تقسيم'])) {
    return profileRankMullion;
  }
  if (_hasAny(text, const [
    'plinthe',
    'بلانت',
    'porte joint',
    'porte-joint',
    'حامل الجوان',
    'bourgeois',
    'بورجوا',
  ])) {
    return profileRankPlinthe;
  }
  if (_hasAny(text, const [
    'sash',
    'ouvrant',
    'vantail',
    'ظلفة',
    'ضلفة',
    'دلفة',
    'قائم',
  ])) {
    return profileRankSash;
  }
  if (_hasAny(text, const ['frame', 'cadre', 'dormant', 'إطار', 'اطار'])) {
    return profileRankFrame;
  }
  return profileRankOther;
}

/// [items] sorted by [rankOf], keeping the original order of equal ranks.
List<T> sortedByProfileDisplayRank<T>(
  Iterable<T> items,
  int Function(T item) rankOf,
) {
  final indexed = [
    for (final (index, item) in items.indexed) (index, rankOf(item), item),
  ];
  indexed.sort((a, b) {
    final byRank = a.$2.compareTo(b.$2);
    return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
  });
  return [for (final entry in indexed) entry.$3];
}
