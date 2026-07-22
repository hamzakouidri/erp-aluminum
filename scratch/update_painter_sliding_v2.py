import re

def main():
    file_path = r'lib\Commande\window_painter.dart'
    
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    new_func = """  void _drawSlidingSash(Canvas canvas, Rect r, WindowZone zone) {
    final bool is90Deg = _is90DegreeSystem();
    int count = zone.slidingSashesCount;
    if (count < 2) count = 2;

    final Map<String, bool> mRein = zone.slidingMontantReinforced;
    final double tLatLeft = _latT(mRein['lateral_left'] ?? false);
    final double tLatRight = _latT(mRein['lateral_right'] ?? false);
    final double tCenLeft = _cenT(mRein['central_left'] ?? false);
    final double tCenRight = _cenT(mRein['central_right'] ?? false);
    final double traverseT = 
        model.selectedSeriesName.contains('hps') ? 22 : 28;

    final double refT = [
      tLatLeft,
      tLatRight,
      tCenLeft,
      tCenRight,
    ].reduce((a, b) => a > b ? a : b);

    double sashWidth;
    if (count == 4) {
      sashWidth = (r.width + 2 * refT) / 4;
    } else {
      sashWidth = (r.width + (count - 1) * refT) / count;
    }

    List<int> tracks = [];
    if (count == 2)
      tracks = [0, 1];
    else if (count == 3)
      tracks = [0, 1, 0];
    else if (count == 4)
      tracks = [0, 1, 1, 0];
    else {
      for (int i = 0; i < count; i++) tracks.add(i % 2);
    }

    try {
      for (int currentTrack = 0; currentTrack <= 1; currentTrack++) {
        for (int i = 0; i < count; i++) {
          if (tracks[i] != currentTrack) continue;

          double left;
          if (count == 4) {
             if (i == 0) left = r.left;
             else if (i == 1) left = r.left + sashWidth - refT;
             else if (i == 2) left = r.left + 2 * sashWidth - refT;
             else left = r.left + 3 * sashWidth - 2 * refT;
          } else {
             left = r.left + i * (sashWidth - refT);
          }
          
          double right = left + sashWidth;
          Rect sashRect = Rect.fromLTRB(left, r.top, right, r.bottom);

          final double leftT = (i == 0) ? tLatLeft : tCenLeft;
          final double rightT = (i == count - 1) ? tLatRight : tCenRight;

          Rect glassRect;
          if (is90Deg) {
            glassRect = Rect.fromLTRB(
              sashRect.left + leftT,
              sashRect.top + traverseT,
              sashRect.right - rightT,
              sashRect.bottom - traverseT,
            );
            if (glassRect.width < 0 || glassRect.height < 0) {
               glassRect = sashRect.deflate(refT);
            }
          } else {
            glassRect = sashRect.deflate(refT);
          }

          bool isDimmed = currentTrack == 0;
          _drawSashFrameRect(
            canvas,
            sashRect,
            glassRect,
            zone.sashColor,
            dimmed: isDimmed,
            isSlidingSash: true,
          );
          _drawFixedGlass(canvas, glassRect, zone.glass);

          final cx = sashRect.center.dx, cy = sashRect.center.dy;
          final sz = (sashRect.width < sashRect.height ? sashRect.width : sashRect.height) * 0.10;
          
          if (sz > 0) {
            final p = Paint()
              ..color = const Color(0xFF42A5F5).withValues(alpha: 0.55)
              ..strokeWidth = 1.5
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round;

            if (i < count / 2) {
              canvas.drawLine(Offset(cx - sz * 0.2, cy), Offset(cx + sz, cy), p);
              canvas.drawLine(Offset(cx + sz * 0.6, cy - sz * 0.4), Offset(cx + sz, cy), p);
              canvas.drawLine(Offset(cx + sz * 0.6, cy + sz * 0.4), Offset(cx + sz, cy), p);
            } else {
              canvas.drawLine(Offset(cx + sz * 0.2, cy), Offset(cx - sz, cy), p);
              canvas.drawLine(Offset(cx - sz * 0.6, cy - sz * 0.4), Offset(cx - sz, cy), p);
              canvas.drawLine(Offset(cx - sz * 0.6, cy + sz * 0.4), Offset(cx - sz, cy), p);
            }
          }
        }
      }

      if (model.isInternalView) {
        double handleRatio = zone.handlePositionRatio ?? 0.5;
        _drawWindowDrawHandle(
          canvas,
          Rect.fromLTWH(r.left, r.top, sashWidth, r.height),
          OpenDirection.left,
          handleRatio,
          isSliding: true,
        );
        double lastSashLeft = count == 4 ? r.left + 3 * sashWidth - 2 * refT : r.left + (count - 1) * (sashWidth - refT);
        _drawWindowDrawHandle(
          canvas,
          Rect.fromLTWH(lastSashLeft, r.top, sashWidth, r.height),
          OpenDirection.right,
          handleRatio,
          isSliding: true,
        );
      }
    } catch (e) {
      print("Error in _drawSlidingSash: $e");
    }
  }

  double _latT(bool reinforced) {"""

    pattern = r'void _drawSlidingSash\(Canvas canvas, Rect r, WindowZone zone\) \{.*?\n  double _latT\(bool reinforced\) \{'
    
    match = re.search(pattern, content, re.DOTALL)
    if match:
        content = content[:match.start()] + new_func + content[match.end() - len('  double _latT(bool reinforced) {'):]
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)
        print("Updated _drawSlidingSash.")
    else:
        print("Could not find _drawSlidingSash to replace.")

if __name__ == '__main__':
    main()
