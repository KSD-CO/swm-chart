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
    final rangeBefore = chart.priceScale().priceRange()!;
    await tester.dragFrom(Offset(axisX, 100), const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(chart.model.rightPriceScale.isAutoScale, isFalse);
    expect(chart.priceScale().priceRange()!.length, isNot(closeTo(rangeBefore.length, 1e-9)));
    await tester.tapAt(Offset(axisX, 100));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(Offset(axisX, 100));
    await tester.pumpAndSettle();
    expect(chart.model.rightPriceScale.isAutoScale, isTrue);
  });
}
