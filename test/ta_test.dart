import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/swm_chart.dart';

void main() {
  group('Ta.fibonacci', () {
    test('returns null for empty points', () {
      final result = Ta.fibonacci([]);
      expect(result, isNull);
    });

    test('returns null for single point (degenerate range)', () {
      final points = [TaPoint(date: DateTime(2024, 1, 1), close: 100, high: 100, low: 100)];
      final result = Ta.fibonacci(points);
      expect(result, isNull, reason: 'Single point has range=0, should return null');
    });

    test('returns null for flat range (all prices identical)', () {
      final points = List.generate(
        10,
        (i) => TaPoint(date: DateTime(2024, 1, 1).add(Duration(days: i)), close: 100, high: 100, low: 100),
      );
      final result = Ta.fibonacci(points);
      expect(result, isNull, reason: 'Flat range should return null to avoid 7 stacked lines');
    });

    test('calculates 7 levels for normal range', () {
      final points = [
        TaPoint(date: DateTime(2024, 1, 1), close: 90, high: 100, low: 90),
        TaPoint(date: DateTime(2024, 1, 2), close: 95, high: 98, low: 92),
        TaPoint(date: DateTime(2024, 1, 3), close: 92, high: 97, low: 91),
      ];
      final result = Ta.fibonacci(points);
      expect(result, isNotNull);
      expect(result!.high, 100);
      expect(result.low, 90);
      expect(result.levels.length, 7);

      // Check key levels
      expect(result.levels[0].ratio, 0.0);
      expect(result.levels[0].price, closeTo(100, 0.01)); // 0% = high

      expect(result.levels[3].ratio, 0.5);
      expect(result.levels[3].price, closeTo(95, 0.01)); // 50% = midpoint

      expect(result.levels[6].ratio, 1.0);
      expect(result.levels[6].price, closeTo(90, 0.01)); // 100% = low
    });

    test('clamps extreme prices (NaN, Infinity)', () {
      final points = [
        TaPoint(date: DateTime(2024, 1, 1), close: double.nan, high: double.infinity, low: -double.infinity),
      ];
      final result = Ta.fibonacci(points);
      // After clamp: high = 1e9, low = 0, range > 0.01 → valid result
      expect(result, isNotNull);
      expect(result!.high, lessThanOrEqualTo(1e9));
      expect(result.high, greaterThanOrEqualTo(0));
      expect(result.low, greaterThanOrEqualTo(0));
      expect(result.low, lessThanOrEqualTo(1e9));
    });

    test('handles very small non-zero range (< 0.01)', () {
      final points = [
        TaPoint(date: DateTime(2024, 1, 1), close: 100.000, high: 100.005, low: 100.000),
        TaPoint(date: DateTime(2024, 1, 2), close: 100.002, high: 100.004, low: 100.001),
      ];
      final result = Ta.fibonacci(points);
      // range = 0.005 < 0.01 → should return null
      expect(result, isNull, reason: 'Very small range (<0.01) should be treated as degenerate');
    });

    test('handles negative prices gracefully (clamped to zero)', () {
      final points = [TaPoint(date: DateTime(2024, 1, 1), close: -50, high: -40, low: -60)];
      final result = Ta.fibonacci(points);
      // Clamped to 0, so range = 0 → null
      expect(result, isNull, reason: 'Negative prices clamped to 0 → flat range → null');
    });

    test('handles mixed valid and extreme prices', () {
      final points = [
        TaPoint(date: DateTime(2024, 1, 1), close: 100, high: 110, low: 90),
        TaPoint(date: DateTime(2024, 1, 2), close: double.nan, high: double.infinity, low: 95),
        TaPoint(date: DateTime(2024, 1, 3), close: 105, high: 108, low: 102),
      ];
      final result = Ta.fibonacci(points);
      // NaN/Infinity clamped, valid range from other points
      expect(result, isNotNull);
      expect(result!.high, greaterThan(100));
      expect(result.low, lessThan(110));
    });

    test('performance: 10,000 points completes in < 100ms', () {
      final points = List.generate(
        10000,
        (i) => TaPoint(
          date: DateTime(2024, 1, 1).add(Duration(days: i)),
          close: 100 + i * 0.1,
          high: 101 + i * 0.1,
          low: 99 + i * 0.1,
        ),
      );
      final stopwatch = Stopwatch()..start();
      final result = Ta.fibonacci(points);
      stopwatch.stop();

      expect(result, isNotNull, reason: 'Should handle large datasets');
      expect(stopwatch.elapsedMilliseconds, lessThan(100), reason: 'Should be fast O(n)');
      expect(result!.levels.length, 7);
    });

    test('golden ratio levels are mathematically correct', () {
      final points = [TaPoint(date: DateTime(2024, 1, 1), close: 0, high: 100, low: 0)];
      final result = Ta.fibonacci(points);
      expect(result, isNotNull);

      // Verify key Fibonacci ratios (high - ratio * range)
      final range = 100.0;
      expect(result!.levels[0].price, closeTo(100, 0.01)); // 0%
      expect(result.levels[1].price, closeTo(100 - 0.236 * range, 0.01)); // 23.6%
      expect(result.levels[2].price, closeTo(100 - 0.382 * range, 0.01)); // 38.2%
      expect(result.levels[3].price, closeTo(100 - 0.5 * range, 0.01)); // 50%
      expect(result.levels[4].price, closeTo(100 - 0.618 * range, 0.01)); // 61.8%
      expect(result.levels[5].price, closeTo(100 - 0.786 * range, 0.01)); // 78.6%
      expect(result.levels[6].price, closeTo(0, 0.01)); // 100%
    });

    test('handles missing high/low (fallback to close)', () {
      final points = [
        TaPoint(date: DateTime(2024, 1, 1), close: 100), // no high/low
        TaPoint(date: DateTime(2024, 1, 2), close: 110),
        TaPoint(date: DateTime(2024, 1, 3), close: 90),
      ];
      final result = Ta.fibonacci(points);
      expect(result, isNotNull);
      expect(result!.high, 110); // from close values
      expect(result.low, 90);
    });
  });

  group('Ta.atr', () {
    test('returns null when insufficient data', () {
      final points = List.generate(
        10,
        (i) => TaPoint(
          date: DateTime(2024, 1, 1).add(Duration(days: i)),
          close: 100 + i.toDouble(),
          high: 101 + i.toDouble(),
          low: 99 + i.toDouble(),
        ),
      );
      expect(Ta.atr(points), isNull);
    });

    test('returns series aligned to input length', () {
      final points = List.generate(
        40,
        (i) => TaPoint(
          date: DateTime(2024, 1, 1).add(Duration(days: i)),
          close: 100 + i.toDouble(),
          high: 102 + i.toDouble(),
          low: 98 + i.toDouble(),
        ),
      );
      final result = Ta.atr(points);
      expect(result, isNotNull);
      expect(result!.values.length, points.length);
      expect(result.values.take(14).every((v) => v == null), isTrue);
      expect(result.values.last, isNotNull);
    });
  });

  group('Ta.adx', () {
    test('returns null when insufficient data', () {
      final points = List.generate(
        20,
        (i) => TaPoint(
          date: DateTime(2024, 1, 1).add(Duration(days: i)),
          close: 100 + i.toDouble(),
          high: 102 + i.toDouble(),
          low: 98 + i.toDouble(),
        ),
      );
      expect(Ta.adx(points), isNull);
    });

    test('returns ADX aligned to input length', () {
      final points = List.generate(
        60,
        (i) => TaPoint(
          date: DateTime(2024, 1, 1).add(Duration(days: i)),
          close: 100 + i.toDouble(),
          high: 102 + i.toDouble(),
          low: 98 + i.toDouble(),
        ),
      );
      final result = Ta.adx(points);
      expect(result, isNotNull);
      expect(result!.adx.length, points.length);
      expect(result.plusDI.length, points.length);
      expect(result.minusDI.length, points.length);
      expect(result.adx.last, isNotNull);
    });
  });

  group('Ta.kama', () {
    List<TaPoint> series(List<double> closes) => [
      for (final (i, c) in closes.indexed)
        TaPoint(
          date: DateTime(2026, 1, 1).add(Duration(days: i)),
          close: c,
        ),
    ];

    test('is null until the efficiency window is filled', () {
      final k = Ta.kama(series(List.generate(15, (i) => 100.0 + i)));
      expect(k.take(10), everyElement(isNull));
      expect(k[10], isNotNull);
    });

    test('follows a clean trend closely', () {
      // Every bar moves the same way: efficiency ratio 1, fast speed.
      final closes = List.generate(60, (i) => 100.0 + i);
      final k = Ta.kama(series(closes));
      expect(closes.last - k.last!, lessThan(2));
    });

    test('barely moves in back-and-forth chop', () {
      // Alternating ±1 around 100: no net move, efficiency ratio 0.
      final closes = List.generate(60, (i) => i.isEven ? 100.0 : 101.0);
      final k = Ta.kama(series(closes));
      // Price swings 1.0 every bar; KAMA should hardly react to any of it.
      final values = k.whereType<double>().toList();
      for (var i = 1; i < values.length; i++) {
        expect((values[i] - values[i - 1]).abs(), lessThan(0.01));
      }
    });
  });

  group('Ta.zigzag', () {
    List<TaPoint> series(List<double> closes) => [
      for (final (i, c) in closes.indexed)
        TaPoint(
          date: DateTime(2026, 1, 1).add(Duration(days: i)),
          close: c,
        ),
    ];

    test('marks swings of at least the deviation and joins them', () {
      // Up 100→120, down to 102, up to 130 (moves ≥ 5%), with 1% wiggles.
      final closes = <double>[100.0, 104, 103, 110, 120, 119, 112, 102, 103, 115, 130, 129];
      final z = Ta.zigzag(series(closes), deviation: 5);
      final swings = [
        for (final (i, v) in z.pivots.indexed)
          if (v != null) (i, v),
      ];
      expect(swings, [(0, 100.0), (4, 120.0), (7, 102.0), (10, 130.0)]);
      // The line runs straight between swings.
      expect(z.line[2], closeTo(110, 1e-9));
      expect(z.line[4], 120);
      expect(z.line.last, isNull); // after the last (forming) swing
    });

    test('ignores moves smaller than the deviation', () {
      final closes = <double>[100.0, 102, 100.5, 102.5, 101, 103];
      final z = Ta.zigzag(series(closes), deviation: 5);
      expect(z.pivots.whereType<double>(), isEmpty);
    });
  });

  group('Ta.elliottWaves', () {
    // Straight runs between the given turning points, 4 bars per leg.
    List<TaPoint> legs(List<double> turns) {
      final closes = <double>[turns.first];
      for (var k = 1; k < turns.length; k++) {
        for (var j = 1; j <= 4; j++) {
          closes.add(turns[k - 1] + (turns[k] - turns[k - 1]) * j / 4);
        }
      }
      return [
        for (final (i, c) in closes.indexed)
          TaPoint(
            date: DateTime(2026, 1, 1).add(Duration(days: i)),
            close: c,
          ),
      ];
    }

    test('labels a valid impulse and the correction after it', () {
      final count = Ta.elliottWaves(legs(<double>[100, 120, 110, 150, 130, 160, 140, 150, 125]))!;
      expect(count.isUp, isTrue);
      expect(count.start.price, 100);
      expect(count.waves.map((w) => w.label), ['1', '2', '3', '4', '5', 'A', 'B', 'C']);
      expect(count.waves.map((w) => w.price), [120, 110, 150, 130, 160, 140, 150, 125]);
    });

    test('rejects a count where wave 4 overlaps wave 1', () {
      // Wave 4 (115) dips below wave 1's top (120).
      expect(Ta.elliottWaves(legs(<double>[100, 120, 110, 150, 115, 160])), isNull);
    });
  });

  group('Ta.sineWave', () {
    test('finds a 20-bar cycle and stays within ±1', () {
      final pts = [
        for (var i = 0; i < 300; i++)
          TaPoint(
            date: DateTime(2026, 1, 1).add(Duration(days: i)),
            close: 100 + 5 * math.sin(2 * math.pi * i / 20),
          ),
      ];
      final r = Ta.sineWave(pts);
      final periods = r.period.skip(150).whereType<double>().toList();
      expect(periods, isNotEmpty);
      final avg = periods.reduce((a, b) => a + b) / periods.length;
      expect(avg, closeTo(20, 4));
      for (final v in [...r.sine, ...r.leadSine].whereType<double>()) {
        expect(v, inInclusiveRange(-1, 1));
      }
    });
  });

  group('Ta.evenBetterSinewave', () {
    List<TaPoint> series(double Function(int) f, int n) => [
      for (var i = 0; i < n; i++)
        TaPoint(
          date: DateTime(2026, 1, 1).add(Duration(days: i)),
          close: f(i),
        ),
    ];

    test('stays within ±1 and flips with each swing of a cycle', () {
      final w = Ta.evenBetterSinewave(series((i) => 100 + 5 * math.sin(2 * math.pi * i / 30), 300));
      final v = w.skip(60).whereType<double>().toList();
      expect(v, everyElement(inInclusiveRange(-1, 1)));
      // A 30-bar cycle over 240 bars: about 8 up and 8 down swings.
      var flips = 0;
      for (var i = 1; i < v.length; i++) {
        if (v[i - 1].sign != v[i].sign) flips++;
      }
      expect(flips, inInclusiveRange(12, 20));
    });

    test('holds near +1 through a steady upswing', () {
      // A rise lasting about half the high-pass duration.
      final w = Ta.evenBetterSinewave(series((i) => i < 60 ? 100 : 100 + (i - 60) * 0.5, 80));
      final upswing = w.skip(68).whereType<double>().toList();
      expect(upswing, everyElement(greaterThan(0.8)));
    });
  });

  test('volume profile splits each bucket into up and down volume', () {
    final day = DateTime(2026, 1, 1);
    final bars = [
      TaPoint(date: day, open: 10, high: 11, low: 10, close: 11, volume: 100),
      TaPoint(date: day, open: 11, high: 11, low: 10, close: 10, volume: 300),
    ];
    final vp = Ta.volumeProfile(bars, buckets: 1);
    expect(vp.buckets.single.volume, 400);
    final grid = Ta.volumeProfile(bars, buckets: 4);
    final up = grid.buckets.fold(0.0, (a, b) => a + b.upVolume!);
    final all = grid.buckets.fold(0.0, (a, b) => a + b.volume);
    expect(up, closeTo(100, 1e-9));
    expect(all, closeTo(400, 1e-9));
  });
}
