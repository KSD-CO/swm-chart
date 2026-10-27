import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/swm_chart.dart';

const _t0 = 1704067200;

List<IndicatorInput> _bars(int n, [int seed = 1]) {
  final r = math.Random(seed);
  var c = 100.0;
  return [
    for (var i = 0; i < n; i++)
      () {
        final o = c;
        c = math.max(1, c + (r.nextDouble() - 0.5) * 4);
        return IndicatorInput(
          time: _t0 + i * 3600,
          open: o,
          high: math.max(o, c) + r.nextDouble() * 2,
          low: math.min(o, c) - r.nextDouble() * 2,
          close: c,
          volume: 100 + r.nextDouble() * 900,
        );
      }(),
  ];
}

void _expectClose(List<double?> actual, List<double?> expected, {double eps = 1e-9, String? reason}) {
  expect(actual.length, expected.length, reason: reason);
  for (var i = 0; i < actual.length; i++) {
    if (expected[i] == null) {
      expect(actual[i], isNull, reason: '$reason [$i]');
    } else {
      expect(actual[i], closeTo(expected[i]!, eps), reason: '$reason [$i]');
    }
  }
}

// ---- naive references, straight from the definitions ----

List<double?> _naiveSma(List<double> v, int p) => [
  for (var i = 0; i < v.length; i++) i < p - 1 ? null : v.sublist(i - p + 1, i + 1).reduce((a, b) => a + b) / p,
];

List<double?> _naiveEma(List<double> v, int p) {
  final out = List<double?>.filled(v.length, null);
  final k = 2 / (p + 1);
  for (var i = p - 1; i < v.length; i++) {
    out[i] = i == p - 1 ? v.sublist(0, p).reduce((a, b) => a + b) / p : v[i] * k + out[i - 1]! * (1 - k);
  }
  return out;
}

List<double?> _naiveRsi(List<double> c, int p) {
  final out = List<double?>.filled(c.length, null);
  double? g, l;
  for (var i = 1; i < c.length; i++) {
    final d = c[i] - c[i - 1];
    final up = math.max(d, 0.0), down = math.max(-d, 0.0);
    if (i < p) continue;
    if (i == p) {
      var sg = 0.0, sl = 0.0;
      for (var j = 1; j <= p; j++) {
        final dd = c[j] - c[j - 1];
        sg += math.max(dd, 0);
        sl += math.max(-dd, 0);
      }
      g = sg / p;
      l = sl / p;
    } else {
      g = (g! * (p - 1) + up) / p;
      l = (l! * (p - 1) + down) / p;
    }
    out[i] = l == 0 ? 100 : 100 - 100 / (1 + g / l);
  }
  return out;
}

void main() {
  final bars = _bars(300);
  final closes = [for (final b in bars) b.close];

  test('SMA, EMA, RSI match their definitions', () {
    _expectClose(Sma(20).computeAll(bars)[0], _naiveSma(closes, 20), eps: 1e-7, reason: 'SMA');
    _expectClose(Ema(12).computeAll(bars)[0], _naiveEma(closes, 12), reason: 'EMA');
    _expectClose(Rsi(14).computeAll(bars)[0], _naiveRsi(closes, 14), reason: 'RSI');
  });

  test('MACD = EMA12 - EMA26, signal = EMA9 of it', () {
    final out = Macd().computeAll(bars);
    final f = _naiveEma(closes, 12), s = _naiveEma(closes, 26);
    final macd = [for (var i = 0; i < closes.length; i++) f[i] == null || s[i] == null ? null : f[i]! - s[i]!];
    _expectClose(out[1], macd, reason: 'MACD');
    final valid = [for (final m in macd) m].whereType<double>().toList();
    final signal = _naiveEma(valid, 9);
    final offset = macd.indexWhere((m) => m != null);
    for (var i = 0; i < valid.length; i++) {
      final expected = signal[i];
      if (expected == null) {
        expect(out[2][offset + i], isNull);
      } else {
        expect(out[2][offset + i], closeTo(expected, 1e-9));
        expect(out[0][offset + i], closeTo(macd[offset + i]! - expected, 1e-9));
      }
    }
  });

  test('sanity checks on simple series', () {
    final rising = [for (var i = 0; i < 40; i++) IndicatorInput.value(time: i, value: i.toDouble())];
    expect(Rsi(14).computeAll(rising)[0].last, 100);
    final flat = [for (var i = 0; i < 40; i++) IndicatorInput.value(time: i, value: 5)];
    final bb = Bollinger().computeAll(flat);
    expect(bb[1].last, 5);
    expect(bb[2].last, 5);
    expect(Macd().computeAll(flat)[1].last, closeTo(0, 1e-12));
    final atr = Atr(
      5,
    ).computeAll([for (var i = 0; i < 20; i++) IndicatorInput(time: i, open: 10, high: 12, low: 10, close: 11)]);
    expect(atr[0].last, closeTo(2, 1e-12));
    final stoch = Stochastic().computeAll([
      for (var i = 0; i < 30; i++) IndicatorInput(time: i, open: 1, high: i + 1.0, low: 0, close: i + 1.0),
    ]);
    expect(stoch[0].last, closeTo(100, 1e-9)); // closing at the high
  });

  test('VWAP restarts each session', () {
    final input = [
      IndicatorInput.value(time: 0, value: 10, volume: 1),
      IndicatorInput.value(time: 3600, value: 20, volume: 3),
      IndicatorInput.value(time: 86400, value: 50, volume: 2),
    ];
    final out = Vwap().computeAll(input)[0];
    expect(out[0], 10);
    expect(out[1], closeTo((10 + 60) / 4, 1e-12));
    expect(out[2], 50); // new day
  });

  for (final make in <Indicator Function()>[
    () => Sma(10),
    () => Ema(10),
    () => Wma(10),
    () => Bollinger(),
    () => Rsi(),
    () => Macd(),
    () => Stochastic(),
    () => Atr(),
    () => Vwap(),
    () => Ichimoku(),
  ]) {
    final name = make().name;
    test('$name: incremental updates match a full computation', () {
      final r = math.Random(5);
      final input = _bars(120, 9).toList();
      final incremental = make();
      final out = [for (final _ in incremental.lines) List<double?>.filled(input.length, null, growable: true)];
      incremental.compute(input, 0, out);
      for (var round = 0; round < 200; round++) {
        final last = input.last;
        IndicatorInput next;
        if (r.nextInt(5) == 0) {
          next = IndicatorInput(
            time: last.time + 3600,
            open: last.close,
            high: last.close + 1,
            low: last.close - 1,
            close: last.close + r.nextDouble() - 0.5,
            volume: 300,
          );
          input.add(next);
          for (final line in out) {
            line.add(null);
          }
        } else {
          final c = last.close + r.nextDouble() - 0.5;
          next = IndicatorInput(
            time: last.time,
            open: last.open,
            high: math.max(last.high, c),
            low: math.min(last.low, c),
            close: c,
            volume: (last.volume ?? 0) + 10,
          );
          input[input.length - 1] = next;
        }
        incremental.compute(input, input.length - 1, out);
        final full = make().computeAll(input);
        for (var l = 0; l < out.length; l++) {
          _expectClose(out[l], full[l], eps: 1e-7, reason: '$name line $l round $round');
        }
      }
    });
  }

  group('on a chart', () {
    late ChartController chart;
    late CandlestickSeriesApi candles;

    setUp(() {
      chart = ChartController();
      candles = chart.addCandlestickSeries()
        ..setData([
          for (final b in bars) CandlestickData(time: b.time, open: b.open, high: b.high, low: b.low, close: b.close),
        ]);
    });
    tearDown(() => chart.dispose());

    test('oscillators get a pane with levels, overlays share the source pane', () {
      final rsi = chart.addIndicator(Rsi(14), source: candles);
      expect(rsi.paneIndex, 1);
      expect(rsi.series.single.priceLines().map((l) => l.options.price), [70, 30]);
      final bb = chart.addIndicator(Bollinger(), source: candles);
      expect(bb.paneIndex, 0);
      expect(bb.series, hasLength(3));
      final last = rsi.series.single.data().last as LineData;
      expect(last.value, closeTo(_naiveRsi(closes, 14).last!, 1e-9));
    });

    test('follows realtime ticks and new bars', () {
      final rsi = chart.addIndicator(Rsi(14), source: candles);
      final last = candles.data().last as CandlestickData;
      candles.update(
        CandlestickData(time: last.time, open: last.open, high: last.high + 5, low: last.low, close: last.high + 5),
      );
      final updated = [...closes]..last = last.high + 5;
      expect((rsi.series.single.data().last as LineData).value, closeTo(_naiveRsi(updated, 14).last!, 1e-9));
      candles.update(CandlestickData(time: last.time + 3600, open: 1, high: 200, low: 1, close: 150));
      expect(rsi.series.single.data().last.time, last.time + 3600);
      expect(rsi.series.single.data(), hasLength(closes.length + 1 - 14));
    });

    test('Ichimoku projects the cloud ahead and draws Chikou behind', () {
      final ichimoku = chart.addIndicator(Ichimoku(), source: candles);
      final spanA = ichimoku.series[2].data();
      final chikou = ichimoku.series[4].data();
      final lastBar = candles.data().last.time;
      expect(spanA.last.time, lastBar + 26 * 3600);
      expect(chikou.last.time, bars[bars.length - 1 - 26].time);
    });

    test('remove takes the series and the pane away', () {
      final macd = chart.addIndicator(Macd(), source: candles);
      expect(chart.panes(), hasLength(2));
      macd.remove();
      expect(chart.panes(), hasLength(1));
      // No more updates after removal.
      candles.update(CandlestickData(time: bars.last.time + 3600, open: 1, high: 2, low: 1, close: 2));
    });

    test('VWAP reads volumes from a histogram series', () {
      final volume = chart.addHistogramSeries(const HistogramSeriesOptions(priceScaleId: 'v'))
        ..setData([for (final b in bars) HistogramData(time: b.time, value: b.volume!)]);
      final vwap = chart.addIndicator(Vwap(), source: candles, volume: volume);
      final expected = Vwap().computeAll(bars)[0];
      expect((vwap.series.single.data().last as LineData).value, closeTo(expected.last!, 1e-9));
    });
  });

  test('band colors', () {
    expect(Ichimoku().band.invertedFillColor, isA<Color>());
  });
}
