import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/swm_chart.dart';

const _day = 86400;
const _t0 = 1704067200;

void main() {
  testWidgets('a fan reaches past the last bar and widens the price scale', (tester) async {
    final chart = ChartController();
    addTearDown(chart.dispose);
    final series = chart.addCandlestickSeries();
    series.setData([
      for (var i = 0; i < 100; i++) CandlestickData(time: _t0 + i * _day, open: 100, high: 101, low: 99, close: 100),
    ]);
    chart.timeScale().applyOptions(const TimeScaleOptions(rightOffset: 12));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 400, height: 300, child: SwmChart(controller: chart)),
        ),
      ),
    );
    final before = chart.priceScale().getVisibleRange()!;
    expect(before.max, lessThan(110));

    final fan = FanPrimitive(
      anchorTime: _t0 + 99 * _day,
      anchorValue: 100,
      steps: [
        for (var k = 1; k <= 10; k++)
          FanStep(mid: 100 + k.toDouble(), ranges: [(100.0 - k, 100.0 + 2 * k), (100.0 - 2 * k, 100.0 + 4 * k)]),
      ],
    );
    series.attachPrimitive(fan);
    // The first paint finds the anchor; the next layout counts the fan.
    await tester.pump();
    await tester.pump();

    final after = chart.priceScale().getVisibleRange()!;
    expect(after.max, greaterThanOrEqualTo(140));
    expect(after.min, lessThanOrEqualTo(80));
    expect(tester.takeException(), isNull);

    // Moving it re-anchors and still paints without error.
    fan.setData(
      steps: const [
        FanStep(mid: 100, ranges: [(95, 105)]),
      ],
    );
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
