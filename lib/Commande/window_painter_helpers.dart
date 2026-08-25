part of 'window_painter.dart';

class _MergedCell {
  final int row;
  final int col;
  final int hSpan;
  final int wSpan;
  final Rect rect;
  final String key;

  _MergedCell({
    required this.row,
    required this.col,
    required this.hSpan,
    required this.wSpan,
    required this.rect,
    required this.key,
  });
}

class _MullionSegment {
  final double position;
  final double start;
  final double end;

  _MullionSegment({
    required this.position,
    required this.start,
    required this.end,
  });
}

class _MullionVisual {
  final Rect rect;
  final bool isHorizontal;
  final double position;

  const _MullionVisual({
    required this.rect,
    required this.isHorizontal,
    required this.position,
  });
}

List<_MullionSegment> _mergeMullionSegments(
  List<_MullionSegment> segments,
  double thickness,
) {
  if (segments.isEmpty) return [];

  final sorted = List<_MullionSegment>.from(segments);
  sorted.sort((a, b) {
    final cmp = a.position.compareTo(b.position);
    if (cmp != 0) return cmp;
    return a.start.compareTo(b.start);
  });

  final merged = <_MullionSegment>[];
  var current = sorted[0];

  for (var i = 1; i < sorted.length; i++) {
    final next = sorted[i];

    if ((next.position - current.position).abs() < 2.0 &&
        next.start <= current.end + thickness + 5.0) {
      current = _MullionSegment(
        position: current.position,
        start: current.start,
        end: math.max(current.end, next.end),
      );
    } else {
      merged.add(current);
      current = next;
    }
  }
  merged.add(current);
  return merged;
}
