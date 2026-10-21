import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/show_system_francais.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/sql_database.dart';

WindowModel _framedWindow({ZoneContent content = ZoneContent.fixedGlass}) {
  final model = WindowModel(db: SqlDatabase(), width: 1200, height: 1000);
  final t = model.profileThickness;
  model.zones.add(
    WindowZone(
      id: 'z',
      boundary: Rect.fromLTRB(t, t, 1200 - t, 1000 - t),
      content: content,
    ),
  );
  return model;
}

void main() {
  group('frame selection modes', () {
    test('one tap shows the resize squares, a second the shape circles', () {
      final model = _framedWindow();

      // First tap on the frame.
      var before = model.selectedFrameKey;
      model.selectFrameByIndex(0);
      model.applyFrameTapMode(isDoubleTap: false, frameKeyBeforeTap: before);
      expect(model.selection.type, SelectionType.frame);
      expect(model.frameShapeMode, isFalse);

      // Quick second tap on the same frame.
      before = model.selectedFrameKey;
      model.selectFrameByIndex(0);
      model.applyFrameTapMode(isDoubleTap: true, frameKeyBeforeTap: before);
      expect(model.frameShapeMode, isTrue);
      expect(model.canShapeSelectedFrame, isTrue);

      // A later single tap goes back to the resize squares.
      before = model.selectedFrameKey;
      model.selectFrameByIndex(0);
      model.applyFrameTapMode(isDoubleTap: false, frameKeyBeforeTap: before);
      expect(model.frameShapeMode, isFalse);
    });

    test('a double tap that first selects the frame shows the squares', () {
      final model = _framedWindow();
      model.selectFrameByIndex(0);
      model.applyFrameTapMode(isDoubleTap: true, frameKeyBeforeTap: null);
      expect(model.frameShapeMode, isFalse);
    });

    test('clearing or selecting anything else leaves the shape mode', () {
      final model = _framedWindow();
      model.selectFrameByIndex(0);
      model.applyFrameTapMode(isDoubleTap: true, frameKeyBeforeTap: 'frame:0');
      expect(model.frameShapeMode, isTrue);

      model.clearSelection();
      expect(model.frameShapeMode, isFalse);

      model.selectFrameByIndex(0);
      model.applyFrameTapMode(isDoubleTap: true, frameKeyBeforeTap: 'frame:0');
      model.selection = const SelectionInfo(
        type: SelectionType.zone,
        zoneId: 'z',
      );
      model.applyFrameTapMode(isDoubleTap: true, frameKeyBeforeTap: 'frame:0');
      expect(model.frameShapeMode, isFalse);
    });

    test('a sliding window never offers the slant/arch circles', () {
      final model = _framedWindow(content: ZoneContent.slidingSash);
      model.selectFrameByIndex(0);
      model.applyFrameTapMode(isDoubleTap: true, frameKeyBeforeTap: 'frame:0');
      expect(model.canShapeSelectedFrame, isFalse);
    });
  });

  // The view passes a fixed working area above the bottom menu, so panels
  // never change the size the model fits into. Only a new drawing size or a
  // resized app window refits the drawing, and never during a drag.
  group('the camera refits only for a new drawing or window size', () {
    const viewport = Size(1200, 800);

    ({double scale, double dx, double dy}) camera(WindowModel m) =>
        (scale: m.canvasScale, dx: m.canvasDx, dy: m.canvasDy);

    test('the same drawing in the same area keeps zoom and place', () {
      final model = _framedWindow();
      model.updateLayoutMetrics(viewport);
      final fitted = camera(model);
      expect(fitted.scale, greaterThan(0));

      model.updateLayoutMetrics(viewport);
      model.notifyListeners();
      model.updateLayoutMetrics(viewport);
      expect(camera(model), fitted);
    });

    test('a new drawing size or app window size refits the drawing', () {
      final model = _framedWindow();
      model.updateLayoutMetrics(viewport);
      final fitted = camera(model);

      model.resizeWindow(3000, 2000);
      model.updateLayoutMetrics(viewport);
      expect(model.canvasScale, lessThan(fitted.scale));

      final bigDrawing = camera(model);
      model.updateLayoutMetrics(const Size(1600, 800));
      expect(camera(model), isNot(bigDrawing));
    });

    test('a drag holds the camera; the release refits', () {
      final model = _framedWindow();
      model.updateLayoutMetrics(viewport);
      final fitted = camera(model);

      model.holdCamera = true;
      model.resizeWindow(3000, 2000);
      model.updateLayoutMetrics(viewport);
      expect(camera(model), fitted);

      model.holdCamera = false;
      model.updateLayoutMetrics(viewport);
      expect(model.canvasScale, lessThan(fitted.scale));
    });

    test('the drawing is centred wherever the first frame was drawn', () {
      final model = _framedWindow();
      model.updateLayoutMetrics(viewport);
      final centred = camera(model);

      final moved = _framedWindow()
        ..drawnLeft = 300
        ..drawnTop = 150;
      moved.updateLayoutMetrics(viewport);
      expect(camera(moved), centred);

      // The centre action gives the same fit.
      moved.centerDrawingOnCanvas();
      moved.updateLayoutMetrics(viewport);
      expect(camera(moved), centred);
    });
  });

  group('drawing page clicks', () {
    FlutterExceptionHandler? previousOnError;

    tearDown(() => debugDefaultTargetPlatformOverride = null);

    Future<WindowModel> pumpPage(WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // The side drawers overflow in the small test window; not our concern.
      previousOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        previousOnError?.call(details);
      };
      final model = _framedWindow();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppSettingsProvider>.value(
              value: AppSettingsProvider(),
            ),
          ],
          child: MaterialApp(home: Scaffold(body: WindowView(model: model))),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      return model;
    }

    Future<void> closePage(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 15));
      FlutterError.onError = previousOnError;
      debugDefaultTargetPlatformOverride = null;
    }

    Offset leftProfile(WindowModel model) => Offset(
      model.canvasDx + model.profileThickness / 2 * model.canvasScale,
      model.canvasDy + 500 * model.canvasScale,
    );

    Future<void> click(
      WidgetTester tester,
      Offset at, {
      double jitter = 0,
    }) async {
      final gesture = await tester.startGesture(
        at,
        kind: PointerDeviceKind.mouse,
      );
      if (jitter > 0) await gesture.moveBy(Offset(jitter, jitter));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 60));
    }

    WorkspaceSelectionPainter selectionPainter(WidgetTester tester) =>
        tester
                .widgetList<CustomPaint>(find.byType(CustomPaint))
                .map((paint) => paint.painter)
                .firstWhere((painter) => painter is WorkspaceSelectionPainter)
            as WorkspaceSelectionPainter;

    testWidgets('a click that moves a pixel or two still selects the frame', (
      tester,
    ) async {
      final model = await pumpPage(tester);
      await click(tester, leftProfile(model), jitter: 2);
      expect(model.selection.type, SelectionType.frame);
      expect(model.frameShapeMode, isFalse);

      await click(tester, leftProfile(model), jitter: 2);
      expect(model.frameShapeMode, isTrue);
      // The click on the side's middle square did not resize the frame.
      expect(model.width, 1200);
      expect(model.height, 1000);
      await closePage(tester);
    });

    testWidgets('a double click on empty canvas leaves the view alone', (
      tester,
    ) async {
      final model = await pumpPage(tester);
      // Zoom in with the wheel.
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      final inside = leftProfile(model) + const Offset(200, 0);
      await tester.sendEventToBinding(pointer.hover(inside));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
      await tester.pump();
      final zoomed = selectionPainter(tester);
      expect(zoomed.userScale, greaterThan(1.0));
      final before = (
        zoomed.userScale,
        zoomed.userPan,
        model.canvasScale,
        model.canvasDx,
        model.canvasDy,
      );

      const empty = Offset(30, 400);
      await click(tester, empty);
      await click(tester, empty);
      final after = selectionPainter(tester);
      expect((
        after.userScale,
        after.userPan,
        model.canvasScale,
        model.canvasDx,
        model.canvasDy,
      ), before);
      await closePage(tester);
    });
  });
}
