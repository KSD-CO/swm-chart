import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/swm_chart.dart';

void main() {
  final rnd = math.Random(7);
  var price = 100.0;
  final input = <IndicatorInput>[];
  for (var i = 0; i < 300; i++) {
    final open = price;
    price *= math.exp(0.02 * (rnd.nextDouble() - 0.5));
    final high = math.max(open, price) * (1 + 0.01 * rnd.nextDouble());
    final low = math.min(open, price) * (1 - 0.01 * rnd.nextDouble());
    input.add(
      IndicatorInput(
        time: 1704067200 + i * 86400,
        open: open,
        high: high,
        low: low,
        close: price,
        volume: 1000 + 500 * rnd.nextDouble(),
      ),
    );
  }
  final bars = [
    for (final b in input)
      TaPoint(
        date: DateTime.fromMillisecondsSinceEpoch((b.time * 1000).round(), isUtc: true),
        open: b.open,
        high: b.high,
        low: b.low,
        close: b.close,
        volume: b.volume,
      ),
  ];

  final indicators = <TaIndicator>[
    WilliamsR(),
    Adx(),
    Obv(),
    Cci(),
    Mfi(),
    Cmf(),
    Aroon(),
    Roc(),
    ParabolicSar(),
    Kama(),
    Keltner(),
    Donchian(),
    Supertrend(),
    VolumeSma(),
    SineWave(),
    EvenBetterSinewave(),
  ];

  test('each indicator matches its Ta function, from any bar on', () {
    for (final ind in indicators) {
      final all = ind.computeAll(input);
      expect(all, hasLength(ind.lines.length), reason: ind.name);
      expect(all, ind.series(bars), reason: ind.name);
      // Recomputing from a later bar leaves the earlier outputs alone.
      final out = [
        for (final l in all) [...l],
      ];
      ind.compute(input, 250, out);
      expect(out, all, reason: ind.name);
      expect(all.any((l) => l.any((v) => v != null)), isTrue, reason: ind.name);
    }
  });

  test('all of them go on a chart', () {
    final chart = ChartController();
    addTearDown(chart.dispose);
    final candles = chart.addCandlestickSeries()
      ..setData([
        for (final b in input) CandlestickData(time: b.time, open: b.open, high: b.high, low: b.low, close: b.close),
      ]);
    final volume = chart.addHistogramSeries()
      ..setData([for (final b in input) HistogramData(time: b.time, value: b.volume!)]);
    for (final ind in indicators) {
      final h = chart.addIndicator(ind, source: candles, volume: volume);
      expect(h.series, hasLength(ind.lines.length), reason: ind.name);
      expect(h.paneIndex == 0, ind.overlay, reason: ind.name);
    }
  });
}
