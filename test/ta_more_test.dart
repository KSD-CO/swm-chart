import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/ta.dart';

final _day = DateTime(2026, 1, 1);

/// Bars whose close is [close] at each index, with a ±1 range and a
/// steady volume.
List<TaPoint> _bars(int n, double Function(int i) close, {double Function(int i)? volume}) => [
  for (var i = 0; i < n; i++)
    TaPoint(
      date: _day.add(Duration(days: i)),
      open: close(i) - 0.5,
      high: close(i) + 1,
      low: close(i) - 1,
      close: close(i),
      volume: volume?.call(i) ?? 1000,
    ),
];

/// A wavy series, to exercise the oscillators.
final _wave = _bars(300, (i) => 100 + 10 * math.sin(i / 7) + i * 0.05);

Iterable<double> _defined(List<double?> v) => v.whereType<double>();

void main() {
  group('moving averages', () {
    final linear = _bars(80, (i) => 10.0 + i);

    test('WMA weighs the newest most', () {
      expect(Ta.wma(_bars(3, (i) => i + 1.0), 3)[2], closeTo(14 / 6, 1e-9));
    });

    test('zero-lag averages sit on a straight line', () {
      final last = linear.last.close;
      // Hull's integer windows leave a fraction of a bar of lag.
      expect(Ta.hma(linear, 16).last, closeTo(last, 1));
      expect(Ta.dema(linear, 10).last, closeTo(last, 1e-6));
      expect(Ta.tema(linear, 10).last, closeTo(last, 1e-6));
      expect(Ta.lsma(linear, 20).last, closeTo(last, 1e-9));
      expect(Ta.zlema(linear, 9).last, closeTo(last, 1e-3));
    });

    test('VWMA is the SMA at a constant volume; RMA/T3/ALMA stay in range', () {
      final sma = Ta.sma(_wave, 20), vwma = Ta.vwma(_wave, 20);
      expect(vwma.last, closeTo(sma.last!, 1e-9));
      final lo = _wave.map((b) => b.close).reduce(math.min), hi = _wave.map((b) => b.close).reduce(math.max);
      for (final s in [Ta.rma(_wave, 14), Ta.t3(_wave, 5), Ta.alma(_wave, 9), Ta.mcGinley(_wave, 14)]) {
        expect(_defined(s), isNotEmpty);
        expect(_defined(s).every((v) => v >= lo - 1 && v <= hi + 1), isTrue);
      }
    });

    test('McGinley on a flat series is the series', () {
      expect(Ta.mcGinley(_bars(40, (_) => 50), 10).last, closeTo(50, 1e-9));
    });

    test('envelope brackets its average by the percent', () {
      final e = Ta.envelope(_wave, 20, percent: 5);
      expect(e.upper.last, closeTo(e.mid.last! * 1.05, 1e-9));
      expect(e.lower.last, closeTo(e.mid.last! * 0.95, 1e-9));
    });

    test('warm-up is null and lengths match', () {
      final w = Ta.wma(_wave, 10);
      expect(w.length, _wave.length);
      expect(w.take(9), everyElement(isNull));
      expect(w[9], isNotNull);
    });
  });

  group('oscillators', () {
    test('bounded ones stay within their range', () {
      void within(Iterable<double> v, double lo, double hi) {
        expect(v, isNotEmpty);
        expect(v.every((x) => x >= lo - 1e-9 && x <= hi + 1e-9), isTrue);
      }

      final s = Ta.stochRsi(_wave);
      within(_defined(s.k), 0, 100);
      within(_defined(s.d), 0, 100);
      within(_defined(Ta.ultimateOscillator(_wave)), 0, 100);
      within(_defined(Ta.cmo(_wave)), -100, 100);
      within(_defined(Ta.tsi(_wave).tsi), -100, 100);
      within(_defined(Ta.connorsRsi(_wave)), 0, 100);
      within(_defined(Ta.choppiness(_wave)), 0, 100);
      within(_defined(Ta.balanceOfPower(_wave)), -1, 1);
    });

    test('flat prices give zero momentum-type readings', () {
      final flat = _bars(120, (_) => 100);
      expect(Ta.trix(flat).trix.last, closeTo(0, 1e-9));
      expect(Ta.awesomeOscillator(flat).last, closeTo(0, 1e-9));
      expect(Ta.ppo(flat).ppo.last, closeTo(0, 1e-9));
      expect(Ta.momentum(flat).last, 0);
      expect(Ta.dpo(flat).last, closeTo(0, 1e-9));
    });

    test('a steady rise reads fully bullish', () {
      final up = _bars(120, (i) => 100.0 + i);
      expect(Ta.cmo(up).last, 100);
      expect(Ta.tsi(up).tsi.last, closeTo(100, 1e-9));
      expect(Ta.momentum(up, period: 10).last, 10);
      expect(Ta.coppock(up).last, greaterThan(0));
      expect(Ta.kst(up).kst.last, greaterThan(0));
    });

    test('fisher, RVI, SMI, KST, accelerator are finite where defined', () {
      for (final s in [
        Ta.fisherTransform(_wave).fisher,
        Ta.rvi(_wave).rvi,
        Ta.rvi(_wave).signal,
        Ta.smi(_wave).smi,
        Ta.kst(_wave).signal,
        Ta.acceleratorOscillator(_wave),
        Ta.massIndex(_wave),
        Ta.coppock(_wave),
      ]) {
        expect(_defined(s), isNotEmpty);
        expect(_defined(s).every((v) => v.isFinite), isTrue);
      }
      expect(Ta.fisherTransform(_wave).trigger[50], Ta.fisherTransform(_wave).fisher[49]);
    });

    test('vortex lines are positive; elder bull power ≥ bear power', () {
      final v = Ta.vortex(_wave);
      expect(_defined(v.plus).every((x) => x > 0), isTrue);
      expect(_defined(v.minus).every((x) => x > 0), isTrue);
      final e = Ta.elderRay(_wave);
      for (var i = 0; i < _wave.length; i++) {
        if (e.bull[i] != null) expect(e.bull[i]!, greaterThanOrEqualTo(e.bear[i]!));
      }
    });
  });

  group('volume', () {
    test('A/D adds the volume when the close is at the high', () {
      final bars = [
        TaPoint(date: _day, open: 9, high: 10, low: 8, close: 10, volume: 100),
        TaPoint(date: _day, open: 9, high: 10, low: 8, close: 8, volume: 40),
      ];
      expect(Ta.accumulationDistribution(bars), [100, 60]);
    });

    test('NVI moves only when the volume falls, PVI when it rises', () {
      final bars = _bars(3, (i) => <double>[100, 110, 121][i], volume: (i) => <double>[100, 50, 80][i]);
      final x = Ta.volumeIndexes(bars);
      expect(x.nvi[1], closeTo(1100, 1e-9));
      expect(x.pvi[1], 1000);
      expect(x.pvi[2], closeTo(1100, 1e-9));
    });

    test('PVT, force, EoM, Klinger, Chaikin osc and volume osc are finite', () {
      final bars = _bars(200, (i) => 100 + 5 * math.sin(i / 5), volume: (i) => 1000 + 300 * math.cos(i / 3));
      for (final s in [
        Ta.priceVolumeTrend(bars),
        Ta.forceIndex(bars),
        Ta.easeOfMovement(bars),
        Ta.klinger(bars).kvo,
        Ta.klinger(bars).signal,
        Ta.chaikinOscillator(bars),
        Ta.volumeOscillator(bars),
      ]) {
        expect(_defined(s), isNotEmpty);
        expect(_defined(s).every((v) => v.isFinite), isTrue);
      }
    });
  });

  group('volatility and bands', () {
    test('steady growth has no volatility and no drawdown', () {
      final up = _bars(60, (i) => 100 * math.pow(1.01, i).toDouble());
      expect(Ta.historicalVolatility(up).last, closeTo(0, 1e-6));
      expect(Ta.ulcerIndex(up).last, closeTo(0, 1e-9));
    });

    test('%B is 0.5 on a flat series and the bandwidth positive on a wave', () {
      expect(Ta.bollingerExtras(_bars(40, (_) => 10)).percentB.last, 0.5);
      expect(_defined(Ta.bollingerExtras(_wave).width).every((w) => w > 0), isTrue);
      expect(Ta.standardDeviation(_bars(40, (_) => 10)).last, 0);
    });

    test('chandelier long sits below the recent high, short above the low', () {
      final c = Ta.chandelierExit(_wave);
      final i = _wave.length - 1;
      final high = _wave.skip(i - 21).map((b) => b.high!).reduce(math.max);
      final low = _wave.skip(i - 21).map((b) => b.low!).reduce(math.min);
      expect(c.long[i]!, lessThan(high));
      expect(c.short[i]!, greaterThan(low));
    });

    test('alligator lines are shifted ahead; fractals find the turns', () {
      final a = Ta.alligator(_wave);
      expect(a.jaw.take(20), everyElement(isNull));
      expect(a.lips[_wave.length - 1], isNotNull);
      final peak = _bars(9, (i) => <double>[1, 2, 3, 4, 9, 4, 3, 2, 1][i]);
      final f = Ta.fractals(peak);
      expect(f.up, [4]);
      expect(f.down, isEmpty);
    });

    test('true range starts with the first bar range', () {
      final tr = Ta.trueRange(_bars(3, (i) => 10.0 + 5 * i));
      expect(tr[0], 2);
      expect(tr[1], 6);
    });
  });
}
