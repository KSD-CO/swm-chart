import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/swm_chart.dart';

const _day = 86400;
const _t0 = 1704067200;

List<CandlestickData> _bars(int count) => List.generate(count, (i) {
      final o = 100.0 + (i % 20);
      return CandlestickData(time: _t0 + i * _day, open: o, high: o + 3, low: o - 3, close: i.isEven ? o + 1 : o - 1);
    });

Future<ChartController> _pump(WidgetTester tester) async {
  final chart = ChartController();
  chart.addCandlestickSeries().setData(_bars(500));
  chart.addLineSeries(const LineSeriesOptions(lineStyle: LineStyle.dashed)).setData([
    for (var i = 0; i < 500; i++) LineData(time: _t0 + i * _day, value: 100.0 + (i % 20)),
  ]);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 400, height: 300, child: SwmChart(controller: chart)))));
  addTearDown(chart.dispose);
  return chart;
}

void main() {
  testWidgets('renders and lays out axes', (tester) async {
    final chart = await _pump(tester);
    expect(tester.takeException(), isNull);
    expect(chart.priceScale().width(), greaterThan(30));
    expect(chart.timeScale().width(), 400 - chart.priceScale().width());
  });

  testWidgets('dragging the pane scrolls into history', (tester) async {
    final chart = await _pump(tester);
    final before = chart.timeScale().scrollPosition();
    await tester.dragFrom(const Offset(200, 150), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(chart.timeScale().scrollPosition(), lessThan(before));
  });

  testWidgets('long press shows the crosshair and reports data', (tester) async {
    final chart = await _pump(tester);
    ChartEventParams? event;
    chart.subscribeCrosshairMove((p) => event = p);
    final gesture = await tester.startGesture(const Offset(150, 100));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    expect(chart.model.crosshair, isNotNull);
    expect(event?.time, isNotNull);
    expect(event!.seriesData.length, 2);
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    final movedTime = event!.time;
    await gesture.up();
    await tester.pump();
    expect(movedTime, greaterThan(_t0));
    // Tap hides it.
    await tester.tapAt(const Offset(150, 100));
    await tester.pump(const Duration(milliseconds: 500));
    expect(chart.model.crosshair, isNull);
  });

  testWidgets('dragging the price axis disables autoscale, double tap restores it', (tester) async {
    final chart = await _pump(tester);
    final axisX = 400 - chart.priceScale().width() / 2;
    final rangeBefore = chart.priceScale().getVisibleRange()!;
    await tester.dragFrom(Offset(axisX, 100), const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(chart.model.panes.first.rightScale.isAutoScale, isFalse);
    expect(chart.priceScale().getVisibleRange()!.length, isNot(closeTo(rangeBefore.length, 1e-9)));
    await tester.tapAt(Offset(axisX, 100));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(Offset(axisX, 100));
    await tester.pumpAndSettle();
    expect(chart.model.panes.first.rightScale.isAutoScale, isTrue);
  });

  _allWidgetTests();
}

Future<ChartController> _pumpAll(WidgetTester tester) async {
  final chart = ChartController(options: const ChartOptions(leftPriceScale: PriceScaleOptions(visible: true)));
  final candles = chart.addCandlestickSeries()..setData(_bars(300));
  createSeriesMarkers(candles, [
    SeriesMarker(time: _t0 + 290 * _day, position: SeriesMarkerPosition.aboveBar, shape: SeriesMarkerShape.arrowDown, color: Colors.red, text: 'Sell'),
    SeriesMarker(time: _t0 + 295 * _day, position: SeriesMarkerPosition.belowBar, shape: SeriesMarkerShape.circle, color: Colors.green),
  ]);
  candles.createPriceLine(const PriceLineOptions(price: 110, title: 'TP'));
  chart.addBarSeries(const BarSeriesOptions(priceScaleId: 'left')).setData([
    for (var i = 0; i < 300; i++) BarData(time: _t0 + i * _day, open: 10, high: 12, low: 8, close: 11),
  ]);
  chart.addAreaSeries(const AreaSeriesOptions(lineType: LineType.curved, lastPriceAnimation: LastPriceAnimationMode.continuous), 1)
      .setData([for (var i = 0; i < 300; i++) AreaData(time: _t0 + i * _day, value: (i % 30).toDouble())]);
  chart.addBaselineSeries(const BaselineSeriesOptions(baseValue: 15, lineType: LineType.withSteps), 2)
      .setData([for (var i = 0; i < 300; i++) BaselineData(time: _t0 + i * _day, value: (i % 30).toDouble())]);
  createTextWatermark(chart.panes()[0], const TextWatermarkOptions(lines: [TextWatermarkLine(text: 'SWM')]));
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 400, height: 600, child: SwmChart(controller: chart)))));
  addTearDown(chart.dispose);
  return chart;
}

void _allWidgetTests() {
  testWidgets('renders every series type, markers and watermark across panes', (tester) async {
    final chart = await _pumpAll(tester);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(chart.panes(), hasLength(3));
    expect(chart.priceScale('left').width(), greaterThan(0));
  });

  testWidgets('dragging a separator resizes the panes', (tester) async {
    final chart = await _pumpAll(tester);
    final pane0 = chart.panes()[0];
    final before = pane0.getHeight();
    final sepY = before + 0.5;
    await tester.dragFrom(Offset(200, sepY), const Offset(0, 60));
    await tester.pump();
    expect(pane0.getHeight(), closeTo(before + 60, 2));
  });

  testWidgets('crosshair in the second pane and double tap', (tester) async {
    final chart = await _pumpAll(tester);
    ChartEventParams? moved;
    ChartEventParams? dbl;
    chart.subscribeCrosshairMove((p) => moved = p);
    chart.subscribeDblClick((p) => dbl = p);
    final pane1 = chart.panes()[1];
    final y = chart.panes()[0].getHeight() + 1 + pane1.getHeight() / 2;
    final gesture = await tester.startGesture(Offset(200, y));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.up();
    expect(moved!.paneIndex, 1);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tapAt(Offset(200, y));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(Offset(200, y));
    await tester.pump(const Duration(milliseconds: 500));
    expect(dbl?.paneIndex, 1);
  });

  testWidgets('takeScreenshot renders the chart', (tester) async {
    final chart = await _pumpAll(tester);
    final image = await tester.runAsync(chart.takeScreenshot);
    expect(image!.width, greaterThan(0));
    image.dispose();
  });
}
