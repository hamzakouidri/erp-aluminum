import 'dart:io';

void main() {
  String path = 'lib/Commande/Systeme/cost_summary_screen.dart';
  String content = File(path).readAsStringSync();
  
  // 1. Add lists to State class
  String stateVars = '''  double totalAlumLength = 0;
  double glassArea = 0;
  double shutterArea = 0;
  double jointPerimeter = 0;

  // Exact Cuts (in meters)
  List<double> frameCuts = [];
  List<double> sashCuts = [];
  List<double> mullionCuts = [];
''';
  if (!content.contains('List<double> frameCuts = [];')) {
    content = content.replaceFirst(
      '  double totalAlumLength = 0;\n  double glassArea = 0;\n  double shutterArea = 0;\n  double jointPerimeter = 0;',
      stateVars
    );
  }

  // 2. Rewrite _calculateDimensions
  String oldDimsStart = '  void _calculateDimensions() {';
  String oldDimsEnd = '    });\n  }';
  int startIdx = content.indexOf(oldDimsStart);
  int endIdx = content.indexOf(oldDimsEnd, startIdx) + oldDimsEnd.length;
  
  String newDims = '''  void _calculateDimensions() {
    double w = widget.model.width / 1000;
    double h = widget.model.height / 1000;

    // تصفير قوائم التقطيع الجديدة
    frameCuts.clear();
    sashCuts.clear();
    mullionCuts.clear();

    // حساب أطوال قطع الإطار (الكادر)
    frameCuts.add(h);
    frameCuts.add(h); // قطعتين للارتفاع
    frameCuts.add(w); // العرض العلوي
    if (widget.model.hasBottomFrame) {
      frameCuts.add(w); // العرض السفلي إذا كان موجوداً
    }

    // حساب أطوال قطع التقسيم (T / Mullion)
    for (var k in widget.model.mullionProfiles.keys) {
      if (k.startsWith('h')) {
         mullionCuts.add(w); // تقسيم أفقي يأخذ العرض (تقريباً)
      } else if (k.startsWith('v')) {
         mullionCuts.add(h); // تقسيم عمودي يأخذ الارتفاع (تقريباً)
      }
    }

    int sashes = 0;
    int hinges = 0;
    int handles = 0;
    int rollers = 0;

    double tempGlassArea = 0;
    double tempJointPerimeter = 0;

    for (var z in widget.model.zones) {
      double zw = z.boundary.width / 1000;
      double zh = z.boundary.height / 1000;

      if (z.content == ZoneContent.empty) continue;

      double zoneGlassArea = (zw - 0.12) * (zh - 0.12);
      if (zoneGlassArea > 0) tempGlassArea += zoneGlassArea;

      if (z.content == ZoneContent.singleSash) {
        sashes += 1;
        hinges += (zh > 1.5) ? 3 : 2;
        handles += 1;
        sashCuts.addAll([zh, zh, zw, zw]); // 4 قطع للضلفة
        tempJointPerimeter += (zw * 2) + (zh * 2);
      } else if (z.content == ZoneContent.doubleSash) {
        sashes += 2;
        hinges += (zh > 1.5) ? 6 : 4;
        handles += 1;
        sashCuts.addAll([zh, zh, zh, zh, (zw/2), (zw/2), (zw/2), (zw/2)]); // 8 قطع للضلفتين
        tempJointPerimeter += (zw * 2) + (zh * 4);
      } else if (z.content == ZoneContent.slidingSash) {
        int count = z.slidingSashesCount > 0 ? z.slidingSashesCount : 2;
        sashes += count;
        handles += count;
        rollers += count * 2;
        for (int i = 0; i < count; i++) {
           sashCuts.addAll([zh, zh, (zw/count), (zw/count)]); // 4 قطع لكل ضلفة سحابة
        }
        tempJointPerimeter += (zw * 2) + (zh * count * 2);
      } else if (z.content == ZoneContent.fixedGlass) {
        tempJointPerimeter += (zw * 2) + (zh * 2);
      }
    }

    double tempSashLength = sashCuts.fold(0.0, (a, b) => a + b);
    double tempFrameLength = frameCuts.fold(0.0, (a, b) => a + b);

    sashLength = tempSashLength;
    frameLength = tempFrameLength;
    glassArea = tempGlassArea;
    jointPerimeter = tempJointPerimeter + frameLength;
    totalAlumLength = frameLength + sashLength;
    shutterArea = widget.model.hasShutter ? (w * h) : 0;

    setState(() {
      exactSashesCount = sashes;
      exactHingesCount = hinges;
      exactHandlesCount = handles;
      exactRollersCount = rollers;
    });
  }''';

  content = content.replaceRange(startIdx, endIdx, newDims);

  // 3. Update the calculateCost part where bars are calculated
  String oldBarCalc = '''      // Calculate exact frames and sashes bars roughly
      double frameMeters =
          (widget.model.width * 2 + widget.model.height * 2) / 1000.0;
      double sashMeters = 0.0;
      for (var zone in widget.model.zones) {
        double zw = zone.boundary.width / 1000.0;
        double zh = zone.boundary.height / 1000.0;
        if (zone.content == ZoneContent.singleSash) {
          sashMeters += (zw * 2 + zh * 2);
        } else if (zone.content == ZoneContent.doubleSash) {
          sashMeters += ((zw / 2) * 4 + zh * 4);
        } else if (zone.content == ZoneContent.slidingSash) {
          int count = zone.slidingSashesCount;
          sashMeters += ((zw / count) * count * 2 + zh * count * 2);
        }
      }
      int hMullionCount = widget.model.mullionProfiles.keys
          .where((k) => k.startsWith('h'))
          .length;
      int vMullionCount = widget.model.mullionProfiles.keys
          .where((k) => k.startsWith('v'))
          .length;
      double mullionMeters =
          (hMullionCount * (widget.model.width / 1000.0)) +
          (vMullionCount * (widget.model.height / 1000.0));

      double frameBars = (frameMeters / 5.8).ceilToDouble();
      double sashBars = (sashMeters / 5.8).ceilToDouble();
      double mullionBars = (mullionMeters / 5.8).ceilToDouble();''';

  String newBarCalc = '''      // 1D Bin Packing الخوارزمية الدقيقة لحساب عدد البارات باستخدام
      int calculateBarsRequired(List<double> cuts, double barLen) {
        if (cuts.isEmpty) return 0;
        List<double> sortedCuts = List.from(cuts)..sort((a, b) => b.compareTo(a));
        List<double> bins = []; // كل bin يمثل بار
        
        for (double cut in sortedCuts) {
          bool placed = false;
          for (int i = 0; i < bins.length; i++) {
            if (bins[i] >= cut) {
              bins[i] -= cut;
              placed = true;
              break;
            }
          }
          if (!placed) {
             bins.add(barLen - cut); // بار جديد
          }
        }
        return bins.length;
      }

      // TODO: Fetch actual bar length from database based on selectedSeries!
      double barLength = 5.8; 

      double frameBars = calculateBarsRequired(frameCuts, barLength).toDouble();
      double sashBars = calculateBarsRequired(sashCuts, barLength).toDouble();
      double mullionBars = calculateBarsRequired(mullionCuts, barLength).toDouble();''';

  if (content.contains('double frameMeters =')) {
      content = content.replaceFirst(oldBarCalc, newBarCalc);
  }

  File(path).writeAsStringSync(content);
  print("Refactored cost summary calculation");
}
