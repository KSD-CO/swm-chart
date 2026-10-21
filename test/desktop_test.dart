import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/src/renderers/last_price_animation.dart';
import 'package:swm_chart/swm_chart.dart';

const _day = 86400;
const _t0 = 1704067200;

Future<ChartController> _pump(WidgetTester tester, {ChartOptions options = const ChartOptions()}) async {
  final chart = ChartController(options: options);
  chart.addCandlestickSeries().setData([
    for (var i = 0; i < 200; i++)
      CandlestickData(
        time: _t0 + i * _day,
        open: 100.0 + i % 9,
        high: 104.0 + i % 9,
        low: 96.0 + i % 9,
        close: 101.0 + i % 7,
      ),
  ]);
  chart.addLineSeries(const LineSeriesOptions(), 1).setData([
    for (var i = 0; i < 200; i++) LineData(time: _t0 + i * _day, value: (i % 30).toDouble()),
  ]);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 400, height: 500, child: SwmChart(controller: chart)),
      ),
    ),
  );
  addTearDown(chart.dispose);
  return chart;
}

MouseCursor? _activeCursor() => RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);

void main() {
  semanticsTests();
  testWidgets('mouse hover moves the crosshair, leaving hides it', (tester) async {
    final chart = await _pump(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(150, 100));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(const Offset(160, 100));
    await tester.pump();
    expect(chart.model.crosshair, isNotNull);
    expect(chart.model.crosshair!.paneIndex, 0);
    await mouse.moveTo(const Offset(160, 400)); // second pane
    await tester.pump();
    expect(chart.model.crosshair!.paneIndex, 1);
    await mouse.moveTo(const Offset(700, 700)); // outside the chart
    await tester.pump();
    expect(chart.model.crosshair, isNull);
  });

  testWidgets('cursors: separator, price axis, time axis', (tester) async {
    final chart = await _pump(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(150, 100));
    addTearDown(mouse.removePointer);
    await tester.pump();

    final pane0 = chart.panes()[0].getHeight();
    await mouse.moveTo(Offset(150, pane0 + 0.5));
    await tester.pump();
    expect(_activeCursor(), SystemMouseCursors.resizeRow);

    await mouse.moveTo(Offset(400 - chart.priceScale().width() / 2, 100));
    await tester.pump();
    expect(_activeCursor(), SystemMouseCursors.resizeUpDown);

    await mouse.moveTo(const Offset(150, 495));
    await tester.pump();
    expect(_activeCursor(), SystemMouseCursors.resizeLeftRight);

    await mouse.moveTo(const Offset(150, 100));
    await tester.pump();
    expect(_activeCursor(), SystemMouseCursors.basic);

    // Percentage scales can't be dragged, like upstream.
    chart.priceScale().applyOptions(const PriceScaleOptions(mode: PriceScaleMode.percentage));
    await tester.pump();
    await mouse.moveTo(Offset(400 - chart.priceScale().width() / 2, 110));
    await tester.pump();
    expect(_activeCursor(), SystemMouseCursors.basic);
  });

  testWidgets('a mouse click emits click without toggling the crosshair', (tester) async {
    final chart = await _pump(tester);
    ChartEventParams? clicked;
    chart.subscribeClick((p) => clicked = p);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(150, 100));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(const Offset(160, 100));
    await tester.pump();
    await mouse.down(const Offset(160, 100));
    await mouse.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(clicked, isNotNull);
    expect(chart.model.crosshair, isNotNull); // still following the mouse
  });

  testWidgets('primitive cursor is used while hovering it', (tester) async {
    final chart = await _pump(tester);
    chart.panes()[0].attachPrimitive(_Zone());
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(150, 300));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(const Offset(20, 20));
    await tester.pump();
    expect(_activeCursor(), SystemMouseCursors.click);
  });

  test('last price animation stages match upstream', () {
    const color = Color(0xFF2196F3);
    final (r0, fill0, stroke0) = lastPriceAnimationFrame(Duration.zero, color);
    expect(r0, 4);
    expect(fill0.a, closeTo(0.25, 1e-6));
    expect(stroke0.a, closeTo(0.4, 1e-6));
    // End of stage 1 (25% of 2600 ms): radius 10, ring at 0.8.
    final (r1, _, stroke1) = lastPriceAnimationFrame(const Duration(milliseconds: 650), color);
    expect(r1, closeTo(10, 1e-6));
    expect(stroke1.a, closeTo(0.8, 1e-6));
    // Resting stage.
    final (r3, fill3, stroke3) = lastPriceAnimationFrame(const Duration(milliseconds: 2500), color);
    expect(r3, 14);
    expect(fill3.a, 0);
    expect(stroke3.a, 0);
  });

  testWidgets('time labels at fixed edges are aligned inside the axis', (tester) async {
    final chart = ChartController(
      options: const ChartOptions(timeScale: TimeScaleOptions(fixLeftEdge: true, fixRightEdge: true, barSpacing: 3)),
    );
    chart.addLineSeries().setData([for (var i = 0; i < 60; i++) LineData(time: _t0 + i * _day, value: i.toDouble())]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 300, height: 300, child: SwmChart(controller: chart)),
        ),
      ),
    );
    final marks = chart.model.timeMarks();
    expect(marks.where((m) => m.needAlignCoordinate), isNotEmpty);
    chart.dispose();
  });
}

class _Zone extends ChartPrimitive {
  @override
  PrimitiveHitTestResult? hitTest(PrimitiveContext ctx, double x, double y) =>
      x < 50 && y < 50 ? const PrimitiveHitTestResult(externalId: 'zone', cursor: SystemMouseCursors.click) : null;
}

void semanticsTests() {
  testWidgets('semantics summarise the last values', (tester) async {
    final handle = tester.ensureSemantics();
    final chart = ChartController();
    final s = chart.addLineSeries(const LineSeriesOptions(title: 'RSI'))
      ..setData([for (var i = 0; i < 10; i++) LineData(time: _t0 + i * _day, value: i.toDouble())]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 300,
            child: SwmChart(controller: chart, semanticsLabel: 'Momentum'),
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Momentum'), findsOneWidget);
    expect(tester.getSemantics(find.byType(SwmChart)).value, 'RSI 9.00');
    s.update(LineData(time: _t0 + 9 * _day, value: 42));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.getSemantics(find.byType(SwmChart)).value, 'RSI 42.00');
    handle.dispose();
    chart.dispose();
  });
}
