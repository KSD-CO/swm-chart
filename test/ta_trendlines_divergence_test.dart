import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/swm_chart.dart';

List<TaPoint> _bars(List<double> closes) => [
  for (var i = 0; i < closes.length; i++)
    TaPoint(
      date: DateTime(2026, 1, 1).add(Duration(days: i)),
      open: closes[i],
      high: closes[i] * 1.005,
      low: closes[i] * 0.995,
      close: closes[i],
    ),
];

void main() {
  test('rising zig-zag gets a support line under every later close', () {
    // Uptrend with pullbacks: higher lows every 10 bars.
    final closes = [for (var i = 0; i < 80; i++) 100 + i * 0.5 + 4 * sin(i * pi / 5)];
    final pts = _bars(closes);
    final lines = Ta.autoTrendlines(pts);
    final support = lines.where((l) => l.support).toList();
    expect(support, hasLength(1));
    final l = support.single;
    expect(l.pb, greaterThan(l.pa)); // rising
    for (var k = l.a; k < pts.length; k++) {
      expect(pts[k].close, greaterThanOrEqualTo(l.priceAt(k.toDouble()) * 0.997));
    }
  });

  test('a line price has closed through is not drawn', () {
    final closes = [
      for (var i = 0; i < 60; i++) 100 + i * 0.5 + 4 * sin(i * pi / 5),
      for (var i = 0; i < 15; i++) 110 - i * 3.0, // collapse through support
    ];
    final lines = Ta.autoTrendlines(_bars(closes));
    for (final l in lines.where((l) => l.support)) {
      expect(l.b, greaterThan(60)); // only lines formed after the break
    }
  });

  test('bullish divergence: lower price low, higher oscillator low', () {
    final closes = [for (var i = 0; i < 40; i++) 100 - i * 0.2 + 3 * sin(i * pi / 6)];
    final pts = _bars(closes);
    // Oscillator that rises at each later low.
    final osc = [for (var i = 0; i < 40; i++) 30.0 + i * 0.5];
    final d = Ta.divergences(pts, osc);
    expect(d.where((x) => x.bullish), isNotEmpty);
    for (final x in d.where((x) => x.bullish)) {
      expect(closes[x.end], lessThan(closes[x.start]));
      expect(osc[x.end], greaterThan(osc[x.start]));
    }
  });
}
