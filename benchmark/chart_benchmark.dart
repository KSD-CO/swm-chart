// Frame cost of a busy chart while it's panned: 10 000 candles, 300 text
// markers and 30 drawings with labels. Run by hand and compare numbers
// before and after a change (they depend on the machine, so they gate
// nothing):
//
//   flutter test benchmark/chart_benchmark.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/swm_chart.dart';

const _day = 86400;
const _t0 = 1704067200;
const _bars = 10000;

List<CandlestickData> _candles() => List.generate(_bars, (i) {
  final o = 100.0 + (i % 50) * 0.7;
  return CandlestickData(time: _t0 + i * _day, open: o, high: o + 3, low: o - 3, close: i.isEven ? o + 1 : o - 1);
});

List<SeriesMarker> _markers() => [
  for (var i = 0; i < 300; i++)
    SeriesMarker(
      time: _t0 + (_bars - 1 - i * 3) * _day,
      position: i.isEven ? SeriesMarkerPosition.belowBar : SeriesMarkerPosition.aboveBar,
      shape: i.isEven ? SeriesMarkerShape.arrowUp : SeriesMarkerShape.arrowDown,
      color: i.isEven ? const Color(0xFF26A69A) : const Color(0xFFEF5350),
      text: i.isEven ? 'Buy ${i % 7}' : 'Sell ${i % 5}',
    ),
];

List<Drawing> _drawings() => [
  for (var i = 0; i < 10; i++) ...[
    FibRetracementDrawing(
      id: 'fib$i',
      anchors: [DrawingAnchor(_bars - 200.0 + i * 15, 100), DrawingAnchor(_bars - 190.0 + i * 15, 130)],
    ),
    PositionDrawing(
      id: 'pos$i',
      anchors: [DrawingAnchor(_bars - 180.0 + i * 15, 110), DrawingAnchor(_bars - 170.0 + i * 15, 120)],
    )..completed(),
    MeasureDrawing(
      id: 'm$i',
      anchors: [DrawingAnchor(_bars - 160.0 + i * 15, 105), DrawingAnchor(_bars - 150.0 + i * 15, 125)],
    ),
  ],
];

void main() {
  testWidgets('pan a busy chart', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final chart = ChartController();
    addTearDown(chart.dispose);
    final candles = chart.addCandlestickSeries()..setData(_candles());
    candles.attachPrimitive(SeriesMarkersPrimitive(_markers()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SwmChart(controller: chart)),
      ),
    );
    final editor = DrawingEditor(chart);
    addTearDown(editor.dispose);
    for (final d in _drawings()) {
      editor.add(d);
    }
    await tester.pump();

    Future<List<int>> pan(int frames) async {
      final times = <int>[];
      for (var f = 0; f < frames; f++) {
        final to = _bars - 1.0 - (f % 40) * 2;
        chart.timeScale().setVisibleLogicalRange(LogicalRange(to - 150, to));
        final sw = Stopwatch()..start();
        await tester.pump();
        times.add(sw.elapsedMicroseconds);
      }
      return times;
    }

    await pan(30); // warm up
    final times = (await pan(120))..sort();
    double ms(int us) => us / 1000;
    final mean = times.reduce((a, b) => a + b) / times.length;
    // ignore: avoid_print
    print(
      'pan frame: mean ${(mean / 1000).toStringAsFixed(2)} ms, '
      'median ${ms(times[times.length ~/ 2]).toStringAsFixed(2)} ms, '
      'p90 ${ms(times[(times.length * 0.9).floor()]).toStringAsFixed(2)} ms',
    );
    expect(tester.takeException(), isNull);
  });
}
