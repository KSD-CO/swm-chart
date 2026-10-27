import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/swm_chart.dart';

const _t0 = 1704067200; // Monday 2024-01-01 00:00 UTC

CandlestickData _bar(num t, double o, double h, double l, double c) =>
    CandlestickData(time: t, open: o, high: h, low: l, close: c);

List<CandlestickData> _walk(int n, {int step = 3600, int seed = 3}) {
  final r = math.Random(seed);
  var c = 100.0;
  return [
    for (var i = 0; i < n; i++)
      () {
        final o = c;
        c = math.max(1, c + (r.nextDouble() - 0.5) * 6);
        return _bar(_t0 + i * step, o, math.max(o, c) + r.nextDouble(), math.min(o, c) - r.nextDouble(), c);
      }(),
  ];
}

void _ascending(List<SeriesData> data) {
  for (var i = 1; i < data.length; i++) {
    expect(data[i].time, greaterThan(data[i - 1].time), reason: 'index $i');
  }
}

void main() {
  test('Heikin-Ashi follows its definition; streaming matches with ticks', () {
    final bars = _walk(50);
    final ha = heikinAshi(bars);
    expect(ha.first.open, (bars.first.open + bars.first.close) / 2);
    for (var i = 1; i < ha.length; i++) {
      final b = bars[i];
      expect(ha[i].close, closeTo((b.open + b.high + b.low + b.close) / 4, 1e-12));
      expect(ha[i].open, closeTo((ha[i - 1].open + ha[i - 1].close) / 2, 1e-12));
      expect(ha[i].high, greaterThanOrEqualTo(math.max(ha[i].open, ha[i].close)));
    }
    // Streaming with a tick on every bar, then the final value.
    final streaming = HeikinAshi();
    CandlestickData? last;
    for (final b in bars) {
      streaming.add(_bar(b.time, b.open, b.open, b.open, b.open)); // a first tick
      last = streaming.add(b); // the bar's final value replaces it
    }
    expect(last!.open, closeTo(ha.last.open, 1e-12));
    expect(last.close, closeTo(ha.last.close, 1e-12));
  });

  test('Renko: one-box bricks, reversals need two boxes', () {
    List<CandlestickData> run(List<double> closes) => renko([
      for (var i = 0; i < closes.length; i++) _bar(_t0 + i * 60, closes[i], closes[i], closes[i], closes[i]),
    ], boxSize: 1);
    // 10 -> 13: three up bricks.
    expect(run([10, 13]).map((b) => b.close), [11, 12, 13]);
    // Pulling back one box doesn't reverse; two boxes do.
    expect(run([10, 13, 12]).length, 3);
    final reversed = run([10, 13, 11]);
    expect(reversed.map((b) => (b.open, b.close)), [(10, 11), (11, 12), (12, 13), (12, 11)]);
    for (final b in renko(_walk(300), boxSize: 2)) {
      expect((b.close - b.open).abs(), closeTo(2, 1e-9));
    }
    _ascending(renko(_walk(300), boxSize: 0.5));
  });

  test('line break: continuation and three-line reversal', () {
    final closes = <double>[10, 11, 12, 13, 12.5, 9.5, 9];
    final out = lineBreak([
      for (var i = 0; i < closes.length; i++) _bar(_t0 + i, closes[i], closes[i], closes[i], closes[i]),
    ]);
    // 10->11, 11->12, 12->13 up; 12.5 is inside the last 3 lines; 9.5 breaks
    // below their low (10): a down line from 12 (the last line's open).
    expect(out.map((l) => (l.open, l.close)), [(10, 11), (11, 12), (12, 13), (12, 9.5), (9.5, 9)]);
  });

  test('range bars span exactly the range', () {
    final bars = rangeBars(_walk(200), range: 3);
    expect(bars, isNotEmpty);
    for (final b in bars) {
      expect(b.high - b.low, closeTo(3, 1e-9));
    }
    _ascending(bars);
  });

  test('resample to hours, days, weeks and months', () {
    final minutes = _walk(60 * 24 * 40, step: 60); // 40 days of 1-minute bars
    final hourly = resample(minutes, const Timeframe.hours(1));
    expect(hourly, hasLength(24 * 40));
    final firstHour = minutes.sublist(0, 60);
    expect(hourly.first.open, firstHour.first.open);
    expect(hourly.first.close, firstHour.last.close);
    expect(hourly.first.high, firstHour.map((b) => b.high).reduce(math.max));
    expect(hourly.first.low, firstHour.map((b) => b.low).reduce(math.min));
    expect(resample(minutes, const Timeframe.days(1)), hasLength(40));
    final weekly = resample(minutes, const Timeframe.weeks());
    // 2024-01-01 is a Monday: weeks start on 01-01, 01-08, ...
    expect(weekly.first.time, _t0);
    expect(weekly[1].time, _t0 + 7 * 86400);
    final monthly = resample(minutes, const Timeframe.months());
    expect(monthly.map((m) => utcMonth(m.time)), [1, 2]);
    expect(
      resampleSum([
        for (final b in minutes.take(120)) HistogramData(time: b.time, value: 1),
      ], const Timeframe.hours(1)).map((v) => v.value),
      [60, 60],
    );
  });

  test('streaming resampler matches the batch result with ticks', () {
    final minutes = _walk(600, step: 60);
    final r = Resampler(const Timeframe.minutes(15));
    final out = <CandlestickData>[];
    for (final b in minutes) {
      for (final c in [r.add(_bar(b.time, b.open, b.open, b.open, b.open)), r.add(b)]) {
        if (out.isNotEmpty && out.last.time == c.time) {
          out[out.length - 1] = c;
        } else {
          out.add(c);
        }
      }
    }
    final batch = resample(minutes, const Timeframe.minutes(15));
    expect(out.length, batch.length);
    for (var i = 0; i < out.length; i++) {
      expect(
        (out[i].open, out[i].high, out[i].low, out[i].close),
        (batch[i].open, batch[i].high, batch[i].low, batch[i].close),
      );
    }
  });

  test('comparison switches to percentage and back', () {
    final chart = ChartController();
    chart.addCandlestickSeries().setData(_walk(30));
    final eth = chart.addComparison([
      for (final b in _walk(30, seed: 8)) LineData(time: b.time, value: b.close),
    ], title: 'ETH');
    expect(chart.priceScale().options.mode, PriceScaleMode.percentage);
    final sol = chart.addComparison(_walk(30, seed: 9), title: 'SOL');
    expect(eth.options.color, isNot(sol.options.color));
    expect(chart.comparisons(), [eth, sol]);
    chart.removeComparison(eth);
    expect(chart.priceScale().options.mode, PriceScaleMode.percentage);
    chart.removeComparison(sol);
    expect(chart.priceScale().options.mode, PriceScaleMode.normal);
    chart.dispose();
  });
}

int utcMonth(num seconds) => DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round(), isUtc: true).month;
