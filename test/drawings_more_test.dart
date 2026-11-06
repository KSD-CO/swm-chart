import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/swm_chart.dart';

const _day = 86400;
const _t0 = 1704067200;

List<CandlestickData> _bars(int count) => List.generate(count, (i) {
  final o = 100.0 + (i % 20);
  return CandlestickData(time: _t0 + i * _day, open: o, high: o + 3, low: o - 3, close: i.isEven ? o + 1 : o - 1);
});

Future<(ChartController, CandlestickSeriesApi, DrawingEditor)> _pump(WidgetTester tester) async {
  final chart = ChartController();
  final candles = chart.addCandlestickSeries()..setData(_bars(200));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 400, height: 300, child: SwmChart(controller: chart)),
      ),
    ),
  );
  final editor = DrawingEditor(chart);
  addTearDown(() {
    editor.dispose();
    chart.dispose();
  });
  await tester.pump();
  return (chart, candles, editor);
}

void main() {
  group('position', () {
    test('target and stop keep to their sides; the stop starts at half the target', () {
      final long = PositionDrawing(id: 1, anchors: const [DrawingAnchor(10, 100), DrawingAnchor(30, 96)])..completed();
      // Dragged below the entry, a long's target still sits above it.
      expect(long.target, 104);
      expect(long.stop, 98);
      expect(long.anchors, hasLength(3));
      expect(long.riskReward, 2);
      expect(long.pricesAt(20), [100, 104, 98]);
      expect(long.pricesAt(40), isEmpty);

      final short = PositionDrawing(id: 2, short: true, anchors: const [DrawingAnchor(10, 100), DrawingAnchor(30, 110)])
        ..completed();
      expect(short.target, 90);
      expect(short.stop, 105);
      short.anchors[2] = const DrawingAnchor(30, 102);
      expect(short.stop, 102);
      expect(short.riskReward, 5);
    });

    test('placed on one bar it gets a default width and target', () {
      final p = PositionDrawing(id: 1, anchors: const [DrawingAnchor(10, 100), DrawingAnchor(10, 100)])..completed();
      expect(p.anchors[1].logical, 30);
      expect(p.target, closeTo(102, 1e-9));
      expect(p.stop, closeTo(99, 1e-9));
    });
  });

  test('Fibonacci extension projects the move from the third anchor', () {
    final f = FibExtensionDrawing(
      id: 1,
      anchors: const [DrawingAnchor(0, 100), DrawingAnchor(10, 120), DrawingAnchor(15, 110)],
    );
    expect(f.priceAt(0), 110);
    expect(f.priceAt(1), 130);
    expect(f.priceAt(1.618), closeTo(142.36, 1e-9));
    expect(f.pricesAt(14), isEmpty);
    expect(f.pricesAt(20), contains(130));
  });

  test('Fibonacci time zones step by the anchors distance', () {
    final z = FibTimeZoneDrawing(id: 1, anchors: const [DrawingAnchor(10, 0), DrawingAnchor(14, 0)]);
    expect(z.logicals.take(6), [10, 14, 18, 22, 30, 42]);
  });

  test('pitchfork: median through the middle of the second and third anchors', () {
    final p = PitchforkDrawing(
      id: 1,
      anchors: const [DrawingAnchor(0, 100), DrawingAnchor(10, 120), DrawingAnchor(10, 100)],
    );
    // Median from (0, 100) through (10, 110): slope 1 per bar.
    expect(p.pricesAt(20), [120, 130, 110]);
    p.variant = PitchforkVariant.schiff; // starts at (0, 110)
    expect(p.pricesAt(20).first, 110);
  });

  test('Gann fan: 1x1 through the second anchor, the others scaled', () {
    final g = GannFanDrawing(id: 1, anchors: const [DrawingAnchor(0, 100), DrawingAnchor(10, 110)]);
    final prices = g.pricesAt(10);
    expect(prices[GannFanDrawing.defaultRatios.indexWhere((r) => r.$2 == '1/1')], 110);
    expect(prices[GannFanDrawing.defaultRatios.indexWhere((r) => r.$2 == '2/1')], 120);
    expect(prices[GannFanDrawing.defaultRatios.indexWhere((r) => r.$2 == '1/2')], 105);
    expect(g.pricesAt(-1), isEmpty);
  });

  test('durations', () {
    expect(formatDuration(3 * 86400 + 4 * 3600), '3d 4h');
    expect(formatDuration(2 * 3600 + 15 * 60), '2h 15m');
    expect(formatDuration(45 * 60), '45m');
    expect(formatDuration(86400), '1d');
  });

  group('drawings over the data', () {
    testWidgets('anchored VWAP is the volume-weighted typical price since its bar', (tester) async {
      final (chart, candles, _) = await _pump(tester);
      final volume = chart.addHistogramSeries(const HistogramSeriesOptions(priceScaleId: 'v'))
        ..setData([for (final (i, b) in _bars(200).indexed) HistogramData(time: b.time, value: 1.0 + i % 3)]);
      final vwap = AnchoredVwapDrawing(id: 1, anchors: const [DrawingAnchor(50, 0)], source: candles, volume: volume);
      final bars = _bars(200);
      var pv = 0.0, v = 0.0;
      for (var i = 50; i <= 60; i++) {
        final b = bars[i];
        final w = 1.0 + i % 3;
        pv += (b.high + b.low + b.close) / 3 * w;
        v += w;
      }
      expect(vwap.pricesAt(60).single, closeTo(pv / v, 1e-9));
      expect(vwap.pricesAt(40), isEmpty);
      vwap.bandMultipliers = const [1];
      expect(vwap.pricesAt(60), hasLength(3));
    });

    testWidgets('regression trend fits the closes between its anchors', (tester) async {
      final (chart, _, _) = await _pump(tester);
      final line = chart.addLineSeries()
        ..setData([for (var i = 0; i < 100; i++) LineData(time: _t0 + i * _day, value: 50 + 2.0 * i)]);
      final r = RegressionTrendDrawing(
        id: 1,
        anchors: const [DrawingAnchor(10, 0), DrawingAnchor(40, 0)],
        source: line,
      );
      final (slope, intercept, sd) = r.fit!;
      expect(slope, closeTo(2, 1e-9));
      expect(intercept, closeTo(50, 1e-9));
      expect(sd, closeTo(0, 1e-9));
      expect(r.pricesAt(20), [closeTo(90, 1e-9), closeTo(90, 1e-9), closeTo(90, 1e-9)]);
      expect(r.pricesAt(41), isEmpty);
    });
  });

  testWidgets('every new drawing paints, hits and round-trips through the codec', (tester) async {
    final (chart, candles, editor) = await _pump(tester);
    final drawings = <Drawing>[
      PositionDrawing(id: 'pos', anchors: const [DrawingAnchor(150, 110), DrawingAnchor(170, 116)])..completed(),
      FibExtensionDrawing(
        id: 'fx',
        anchors: const [DrawingAnchor(120, 100), DrawingAnchor(140, 115), DrawingAnchor(150, 105)],
      ),
      FibTimeZoneDrawing(id: 'tz', anchors: const [DrawingAnchor(150, 100), DrawingAnchor(153, 100)]),
      PitchforkDrawing(
        id: 'pf',
        anchors: const [DrawingAnchor(130, 100), DrawingAnchor(150, 115), DrawingAnchor(160, 105)],
      ),
      GannFanDrawing(id: 'gann', anchors: const [DrawingAnchor(140, 100), DrawingAnchor(150, 105)]),
      AnchoredVwapDrawing(id: 'vwap', anchors: const [DrawingAnchor(150, 0)], source: candles, bandMultipliers: [1]),
      RegressionTrendDrawing(id: 'reg', anchors: const [DrawingAnchor(140, 0), DrawingAnchor(190, 0)], source: candles),
      CalloutDrawing(id: 'note', anchors: const [DrawingAnchor(160, 110), DrawingAnchor(170, 118)], text: 'Look'),
      DateRangeDrawing(id: 'dates', anchors: const [DrawingAnchor(150, 104), DrawingAnchor(165, 108)]),
      PriceRangeDrawing(id: 'prices', anchors: const [DrawingAnchor(170, 102), DrawingAnchor(175, 112)]),
    ];
    for (final d in drawings) {
      editor.add(d);
      editor.select(d.id);
      await tester.pump();
    }
    expect(tester.takeException(), isNull);

    final codec = DrawingCodec(source: candles);
    final json = codec.encodeAll(editor.drawings, chart.timeScale().logicalToTime);
    expect(json.map((j) => j['kind']), [
      'position',
      'fibExtension',
      'fibTimeZone',
      'pitchfork',
      'gannFan',
      'anchoredVwap',
      'regressionTrend',
      'callout',
      'dateRange',
      'priceRange',
    ]);
    final back = codec.decodeAll(json, chart.timeScale().timeToLogical);
    expect(back, hasLength(drawings.length));
    for (final (i, d) in back.indexed) {
      expect(d.runtimeType, drawings[i].runtimeType);
      expect(d.anchors, drawings[i].anchors);
    }
    expect((back[0] as PositionDrawing).stop, (drawings[0] as PositionDrawing).stop);
    expect((back[5] as AnchoredVwapDrawing).source, candles);
    expect((back[5] as AnchoredVwapDrawing).bandMultipliers, [1]);
    expect((back[7] as CalloutDrawing).text, 'Look');
  });

  group('editor', () {
    testWidgets('a position placed with two taps gets its stop', (tester) async {
      final (chart, _, editor) = await _pump(tester);
      editor.tool = (id, anchors) => PositionDrawing(id: id, anchors: anchors);
      final rect = tester.getRect(find.byType(SwmChart));
      await tester.tapAt(rect.center.translate(-60, 0));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tapAt(rect.center.translate(0, -40));
      await tester.pump(const Duration(milliseconds: 400));
      final p = editor.drawings.single as PositionDrawing;
      expect(p.anchors, hasLength(3));
      expect(p.target, greaterThan(p.entry));
      expect(p.stop, lessThan(p.entry));
      expect(editor.selected, p);
      chart.timeScale(); // keep the chart alive
    });

    testWidgets('update is one undo step; duplicate copies and selects', (tester) async {
      final (_, candles, editor) = await _pump(tester);
      editor.add(TrendLineDrawing(id: 'a', anchors: const [DrawingAnchor(150, 100), DrawingAnchor(160, 110)]));
      Drawing? changed;
      editor.onChanged = (d) => changed = d;
      editor.update('a', (d) => d.style = d.style.copyWith(color: const Color(0xFFFF0000)));
      expect(changed?.id, 'a');
      expect(editor.drawings.single.style.color, const Color(0xFFFF0000));
      editor.undo();
      expect(editor.drawings.single.style.color, const DrawingStyle().color);

      final copy = editor.duplicate('a')!;
      expect(editor.drawings, hasLength(2));
      expect(editor.selected, copy);
      expect(copy.id, isNot('a'));
      expect(copy.anchors.first, const DrawingAnchor(155, 100));
      editor.undo();
      expect(editor.drawings, hasLength(1));

      editor.add(AnchoredVwapDrawing(id: 'v', anchors: const [DrawingAnchor(150, 0)], source: candles));
      final vwap = editor.duplicate('v', codec: DrawingCodec(source: candles)) as AnchoredVwapDrawing;
      expect(vwap.source, candles);
    });
  });
}
