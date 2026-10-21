// Port of lightweight-charts src/model/price-tick-span-calculator.ts
import 'dart:math' as math;

const double _tickSpanEpsilon = 1e-14;

bool _greaterOrEqual(double x1, double x2, double epsilon) => (x2 - x1) <= epsilon;

bool _equal(double x1, double x2, double epsilon) => (x1 - x2).abs() < epsilon;

double _log10(double x) => math.log(x) / math.ln10;

bool isBaseDecimal(num value) {
  if (value < 0) return false;
  if (value > 1e18) return true;
  for (num current = value; current > 1; current /= 10) {
    if (current % 10 != 0) return false;
  }
  return true;
}

class PriceTickSpanCalculator {
  PriceTickSpanCalculator(this._base, this._integralDividers) {
    if (isBaseDecimal(_base)) {
      _fractionalDividers = const [2, 2.5, 2];
    } else {
      final dividers = <double>[];
      for (var baseRest = _base; baseRest != 1;) {
        if (baseRest % 2 == 0) {
          dividers.add(2);
          baseRest ~/= 2;
        } else if (baseRest % 5 == 0) {
          dividers.addAll(const [2, 2.5]);
          baseRest ~/= 5;
        } else {
          throw ArgumentError('unexpected base $_base');
        }
        if (dividers.length > 100) {
          throw StateError('something wrong with base $_base');
        }
      }
      _fractionalDividers = dividers;
    }
  }

  final int _base;
  final List<double> _integralDividers;
  late final List<double> _fractionalDividers;

  double tickSpan(double high, double low, double maxTickSpan) {
    final minMovement = _base == 0 ? 0.0 : 1 / _base;

    var resultTickSpan = math.pow(10, math.max(0, _log10(high - low).ceil())).toDouble();

    var index = 0;
    var c = _integralDividers[0];

    while (true) {
      // The second part matters for very small values like 1e-10,
      // where greaterOrEqual alone fails.
      final largerMinMovement = _greaterOrEqual(resultTickSpan, minMovement, _tickSpanEpsilon) &&
          resultTickSpan > (minMovement + _tickSpanEpsilon);
      final largerMaxTickSpan = _greaterOrEqual(resultTickSpan, maxTickSpan * c, _tickSpanEpsilon);
      final larger1 = _greaterOrEqual(resultTickSpan, 1, _tickSpanEpsilon);
      if (!(largerMinMovement && largerMaxTickSpan && larger1)) break;
      resultTickSpan /= c;
      c = _integralDividers[++index % _integralDividers.length];
    }

    if (resultTickSpan <= minMovement + _tickSpanEpsilon) {
      resultTickSpan = minMovement;
    }

    resultTickSpan = math.max(1, resultTickSpan);

    if (_fractionalDividers.isNotEmpty && _equal(resultTickSpan, 1, _tickSpanEpsilon)) {
      index = 0;
      c = _fractionalDividers[0];
      while (_greaterOrEqual(resultTickSpan, maxTickSpan * c, _tickSpanEpsilon) &&
          resultTickSpan > minMovement + _tickSpanEpsilon) {
        resultTickSpan /= c;
        c = _fractionalDividers[++index % _fractionalDividers.length];
      }
    }

    return resultTickSpan;
  }
}
