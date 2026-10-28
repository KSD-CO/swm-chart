import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/ta.dart';

/// An app's own bar type: Ta gets a `List<_AppBar>`, which Dart treats as
/// a `List<TaBar>` but rejects TaBar-typed callbacks on (covariance).
class _AppBar implements TaBar {
  _AppBar(this.date, this.close, this.open, this.high, this.low, this.volume);
  @override
  final DateTime date;
  @override
  final double close;
  @override
  final double? open;
  @override
  final double? high;
  @override
  final double? low;
  @override
  final double? volume;
}

List<_AppBar> _bars({required bool intraday}) {
  final rnd = math.Random(3);
  var price = 100.0;
  final start = DateTime(2026, 1, 5, 9);
  return [
    for (var i = 0; i < 400; i++)
      () {
        final open = price;
        price *= math.exp(0.025 * (rnd.nextDouble() - 0.5));
        final date = intraday ? start.add(Duration(hours: i)) : start.add(Duration(days: i));
        return _AppBar(
          date,
          price,
          open,
          math.max(open, price) * 1.004,
          math.min(open, price) * 0.996,
          1000 + 900 * rnd.nextDouble(),
        );
      }(),
  ];
}

void main() {
  for (final intraday in [false, true]) {
    test('every Ta function takes a list of a TaBar subtype (intraday: $intraday)', () {
      final b = _bars(intraday: intraday);
      final now = b.last.date.add(const Duration(minutes: 30));
      expect(
        () => [
          Ta.rsi(b),
          Ta.sma(b, 20),
          Ta.smaLast(b, 20),
          Ta.ema(b, 20),
          Ta.macd(b),
          Ta.bollinger(b),
          Ta.stochastic(b),
          Ta.williamsR(b),
          Ta.ichimoku(b),
          Ta.volumeProfile(b),
          Ta.fibonacci(b),
          Ta.regressionChannel(b),
          Ta.supportResistance(b),
          Ta.detectPatterns(b),
          Ta.atr(b),
          Ta.adx(b),
          Ta.obv(b),
          Ta.pivotPoints(b, now: now),
          Ta.cci(b),
          Ta.mfi(b),
          Ta.chaikinMoneyFlow(b),
          Ta.keltnerChannel(b),
          Ta.donchianChannel(b),
          Ta.parabolicSar(b),
          Ta.vwap(b),
          Ta.zigzag(b),
          Ta.elliottWaves(b),
          Ta.evenBetterSinewave(b),
          Ta.sineWave(b),
          Ta.kama(b),
          Ta.supertrend(b),
          Ta.aroon(b),
          Ta.roc(b),
          Ta.volumeSma(b),
          Ta.candlePatterns(b),
          Ta.rsiBullishDivergence(b),
          Ta.rsiBearishDivergence(b),
          Ta.autoTrendlines(b),
          Ta.divergences(b, Ta.rsi(b)),
        ],
        returnsNormally,
      );
    });
  }
}
