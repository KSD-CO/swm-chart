import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/swm_chart.dart';

const _hour = 3600;
const _t0 = 1704067200;

List<CandlestickData> _bars(int count) => List.generate(count, (i) {
  final o = 100.0 + (i % 30) - (i % 7);
  return CandlestickData(time: _t0 + i * _hour, open: o, high: o + 2, low: o - 2, close: i.isEven ? o + 1 : o - 1);
});

List<double> _volumes(int count) => [for (var i = 0; i < count; i++) 100.0 + i % 13 * 10];

Future<ProChartController> _pump(WidgetTester tester, {int bars = 200}) async {
  final pro = ProChartController(symbol: 'TEST', interval: '1h')..setData(_bars(bars), volumes: _volumes(bars));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 500, height: 400, child: SwmChart(controller: pro.chart)),
      ),
    ),
  );
  addTearDown(pro.dispose);
  await tester.pump();
  return pro;
}

void main() {
  test('the catalog has every indicator once, and each one computes', () {
    final ids = IndicatorCatalog.all.map((s) => s.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    expect(ids, hasLength(73));
    final input = [
      for (final b in _bars(300))
        IndicatorInput(time: b.time, open: b.open, high: b.high, low: b.low, close: b.close, volume: 1000),
    ];
    for (final spec in IndicatorCatalog.all) {
      final indicator = spec.build();
      final out = indicator.computeAll(input);
      expect(out, hasLength(indicator.lines.length), reason: spec.id);
      expect(out.expand((l) => l).whereType<double>(), isNotEmpty, reason: spec.id);
    }
    expect(IndicatorCatalog.search('rsi').map((s) => s.id), containsAll(['rsi', 'stochrsi', 'connorsrsi']));
    expect(IndicatorCatalog.byId('bollinger')!.withDefaults({'period': 30}), {'period': 30, 'multiplier': 2});
  });

  testWidgets('changing the type keeps indicators and trading lines', (tester) async {
    final pro = await _pump(tester);
    pro.addIndicator(IndicatorCatalog.byId('ema')!, values: {'period': 10});
    pro.addIndicator(IndicatorCatalog.byId('rsi')!);
    pro.trading.add(TradingLine(id: 'a', kind: TradingLineKind.alert, price: 110));
    final panes = pro.chart.panes().length;

    for (final type in ProChartType.values.reversed) {
      pro.type = type;
      await tester.pump();
      expect(pro.indicators.map((i) => i.spec.id), ['ema', 'rsi']);
      expect(pro.indicators.first.handle.source, pro.mainSeries);
      expect(pro.trading.lines.single.id, 'a');
      expect(pro.chart.panes(), hasLength(panes));
      expect(pro.mainSeries.data(), hasLength(200));
    }
    expect(pro.mainSeries.seriesType(), SeriesType.candlestick);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new inputs recompute an indicator in its own pane', (tester) async {
    final pro = await _pump(tester);
    final rsi = pro.addIndicator(IndicatorCatalog.byId('rsi')!);
    final macd = pro.addIndicator(IndicatorCatalog.byId('macd')!);
    final macdPane = macd.handle.series.first.getPane().paneIndex();
    pro.updateIndicator(rsi, values: {'period': 21});
    expect(rsi.name, 'RSI 21');
    expect(rsi.handle.series.first.getPane().paneIndex(), 1);
    expect(macd.handle.series.first.getPane().paneIndex(), macdPane);
    expect(pro.chart.panes(), hasLength(3));

    // Removing RSI shifts MACD up; updating MACD keeps it in its pane.
    pro.removeIndicator(rsi);
    pro.updateIndicator(macd, values: {'fast': 8});
    expect(pro.chart.panes(), hasLength(2));
    expect(macd.handle.series.first.getPane().paneIndex(), 1);

    pro.updateIndicator(
      macd,
      styles: [for (final s in macd.styles) s.copyWith(color: const Color(0xFF123456))],
      visible: false,
    );
    expect(macd.handle.series.map((s) => s.options.visible), everyElement(isFalse));
    expect((macd.handle.series[1].options as LineSeriesOptions).color, const Color(0xFF123456));
  });

  testWidgets('a saved chart restores on a fresh controller', (tester) async {
    final pro = await _pump(tester);
    pro
      ..type = ProChartType.heikinAshi
      ..scaleMode = PriceScaleMode.logarithmic;
    final bb = pro.addIndicator(IndicatorCatalog.byId('bollinger')!, values: {'period': 30});
    pro.updateIndicator(bb, styles: [for (final s in bb.styles) s.copyWith(lineWidth: 3)]);
    pro.addIndicator(IndicatorCatalog.byId('obv')!, visible: false);
    pro.drawings
      ..add(TrendLineDrawing(id: 't', anchors: const [DrawingAnchor(150, 100), DrawingAnchor(170, 110)]))
      ..add(PositionDrawing(id: 'p', anchors: const [DrawingAnchor(180, 105), DrawingAnchor(195, 109)])..completed())
      ..add(AnchoredVwapDrawing(id: 'v', anchors: const [DrawingAnchor(120, 0)], source: pro.mainSeries));
    pro.trading
      ..add(TradingLine(id: 'pos', kind: TradingLineKind.position, price: 104, quantity: 2))
      ..add(TradingLine(id: 'sl', kind: TradingLineKind.stopLoss, price: 99, quantity: 2, color: Colors.purple));

    final saved = jsonDecode(jsonEncode(pro.saveState())) as Map<String, Object?>;

    final copy = ProChartController()..setData(_bars(200), volumes: _volumes(200));
    addTearDown(copy.dispose);
    copy.restoreState(saved);
    expect(copy.type, ProChartType.heikinAshi);
    expect(copy.scaleMode, PriceScaleMode.logarithmic);
    expect(copy.symbol, 'TEST');
    expect(copy.interval, '1h');
    expect(copy.indicators.map((i) => i.spec.id), ['bollinger', 'obv']);
    expect(copy.indicators.first.values['period'], 30);
    expect(copy.indicators.first.styles.map((s) => s.lineWidth), everyElement(3));
    expect(copy.indicators.last.visible, isFalse);
    expect(copy.drawings.drawings.map((d) => d.id), ['t', 'p', 'v']);
    expect(copy.drawings.drawings[1].anchors, pro.drawings.drawings[1].anchors);
    expect((copy.drawings.drawings[2] as AnchoredVwapDrawing).source, copy.mainSeries);
    expect(copy.trading.lines.map((l) => l.id), ['pos', 'sl']);
    expect(copy.trading.lines.last.color?.toARGB32(), Colors.purple.toARGB32());
    expect(copy.saveState(), saved);
  });

  testWidgets('realtime updates go to the price, volume and Heikin-Ashi series', (tester) async {
    final pro = await _pump(tester);
    pro.type = ProChartType.heikinAshi;
    final last = pro.bars.last;
    final next = CandlestickData(time: last.time + _hour, open: 100, high: 104, low: 99, close: 103);
    pro.update(next, volume: 500);
    pro.update(CandlestickData(time: next.time, open: 100, high: 106, low: 99, close: 105), volume: 700);
    expect(pro.bars, hasLength(201));
    expect(pro.volumeSeries!.data().last, isA<HistogramData>().having((d) => d.value, 'value', 700));
    final expected = heikinAshi(pro.bars).last;
    final ha = pro.mainSeries.data().last as CandlestickData;
    expect(ha.close, closeTo(expected.close, 1e-9));
    expect(ha.open, closeTo(expected.open, 1e-9));
  });
}
