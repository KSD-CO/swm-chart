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

Future<(ChartController, CandlestickSeriesApi)> _pump(WidgetTester tester) async {
  final chart = ChartController();
  final candles = chart.addCandlestickSeries()..setData(_bars(120));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 400, height: 300, child: SwmChart(controller: chart)),
      ),
    ),
  );
  addTearDown(chart.dispose);
  return (chart, candles);
}

void main() {
  testWidgets('band fill, levels and a volume profile render', (tester) async {
    final (_, candles) = await _pump(tester);
    candles.attachPrimitive(
      BandFillPrimitive(
        points: [
          for (var i = 0; i < 120; i++) BandPoint(time: _t0 + i * _day, upper: 112.0 + (i % 7), lower: 98.0 + (i % 5)),
        ],
        options: const BandFillOptions(
          invertedFillColor: Color(0x33F44336),
          upperLineColor: Color(0xFF2962FF),
          lowerLineColor: Color(0xFF2962FF),
        ),
      ),
    );
    candles.attachPrimitive(
      PriceLevelsPrimitive(
        levels: const [
          PriceLevel(price: 115, label: '0.618', fillColorToNext: Color(0x2226A69A)),
          PriceLevel(price: 105, label: '0.5', lineStyle: LineStyle.dashed),
        ],
      ),
    );
    candles.attachPrimitive(
      VolumeProfilePrimitive(
        bins: [
          for (var p = 96.0; p < 124; p += 2)
            VolumeProfileBin(low: p, high: p + 2, volume: 100 + (p % 6) * 30, upVolume: 60),
        ],
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a level with an id is reported under a click', (tester) async {
    final (chart, candles) = await _pump(tester);
    candles.attachPrimitive(PriceLevelsPrimitive(levels: const [PriceLevel(price: 110, id: 'r1')]));
    await tester.pump();
    final y = chart.panes().first.priceToCoordinate(110)!;
    Object? hit;
    chart.subscribeClick((p) => hit = p.hoveredObjectId);
    await tester.tapAt(Offset(150, y));
    await tester.pump(kDoubleTapTimeout);
    expect(hit, 'r1');
  });

  testWidgets('levels can carry a price axis label', (tester) async {
    final (chart, candles) = await _pump(tester);
    final levels = PriceLevelsPrimitive(
      levels: const [
        PriceLevel(price: 110, label: 'R1', axisLabel: true),
        PriceLevel(price: 100, label: 'S1'),
      ],
    );
    candles.attachPrimitive(levels);
    await tester.pump();
    final labels = levels.priceAxisLabels(_Ctx(chart));
    expect(labels.map((l) => l.text), ['R1']);
  });
}

/// Enough of a context for [PriceLevelsPrimitive.priceAxisLabels].
class _Ctx implements PrimitiveContext {
  _Ctx(this.chart);

  final ChartController chart;

  @override
  double? priceToCoordinate(double price) => chart.panes().first.priceToCoordinate(price);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
