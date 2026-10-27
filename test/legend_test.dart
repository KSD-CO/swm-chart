import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/swm_chart.dart';

const _day = 86400;
const _t0 = 1704067200;

List<CandlestickData> _bars() => [
  for (var i = 0; i < 60; i++)
    CandlestickData(time: _t0 + i * _day, open: 100.0 + i, high: 103.0 + i, low: 99.0 + i, close: 101.0 + i),
];

void main() {
  percentLegendTests();
  test('rows: OHLC with change, indicators grouped, last bar without crosshair', () {
    final chart = ChartController();
    final candles = chart.addCandlestickSeries(const CandlestickSeriesOptions(title: 'BTC'))..setData(_bars());
    chart.addIndicator(Bollinger(), source: candles);
    chart.addIndicator(Rsi(14), source: candles);
    final legend = createLegend(chart);

    final main = legend.rowsOf(chart.panes()[0], null);
    expect(main.map((r) => r.name), ['BTC', 'BB 20 2']);
    expect(main[0].values.map((v) => v.label), ['O', 'H', 'L', 'C', null]);
    expect(main[0].values[3].text, '160.00');
    // Close 160 against the previous close 159.
    expect(main[0].values[4].text, '+${(1 / 159 * 100).toStringAsFixed(2)}%');
    expect(main[1].values, hasLength(3)); // basis, upper, lower

    final atTen = legend.rowsOf(chart.panes()[0], 10);
    expect(atTen[0].values[3].text, '111.00');

    // The RSI pane was created before the legend; panes added later get one too.
    expect(legend.rowsOf(chart.panes()[1], null).single.name, 'RSI 14');
    chart.addIndicator(Macd(), source: candles);
    expect(legend.rowsOf(chart.panes()[2], null).single.name, 'MACD 12 26 9');
    legend.dispose();
    chart.dispose();
  });

  testWidgets('legend and tooltip render with a moving crosshair', (tester) async {
    for (final mode in LegendMode.values) {
      final chart = ChartController();
      final candles = chart.addCandlestickSeries()..setData(_bars());
      chart.addIndicator(Ema(9), source: candles);
      createLegend(chart, LegendOptions(mode: mode, title: 'BTC/USD · 1D'));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 400, height: 300, child: SwmChart(controller: chart)),
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(200, 150));
      await mouse.moveTo(const Offset(210, 150));
      await tester.pump();
      await mouse.moveTo(const Offset(380, 40)); // near the right edge: the tooltip flips left
      await tester.pump();
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
      chart.dispose();
    }
  });
}

void percentLegendTests() {
  test('legend shows prices even on a percentage scale', () {
    final chart = ChartController();
    final candles = chart.addCandlestickSeries()..setData(_bars());
    chart.addComparison([for (final b in _bars()) LineData(time: b.time, value: b.close * 2)], title: 'ETH');
    final legend = createLegend(chart);
    final rows = legend.rowsOf(chart.panes()[0], null);
    expect(rows[0].values[3].text, '160.00');
    expect(rows[1].values.single.text, '320.00');
    expect(candles.priceScale().options.mode, PriceScaleMode.percentage);
    chart.dispose();
  });
}
