// Port of lightweight-charts IHorzScaleBehavior and its three
// implementations: time (horz-scale-behavior-time), price
// (horz-scale-behavior-price, used by options charts) and months
// (yield-curve-horz-scale-behavior).
import '../options.dart';
import 'tick_marks.dart';
import 'time_utils.dart';

/// What the horizontal axis measures and how its labels look.
abstract class HorzScaleBehavior {
  const HorzScaleBehavior();

  /// Fills [weights] of [times] from [startIndex]. Heavier tick marks win
  /// when labels would overlap.
  void fillWeights(List<num> times, List<int> weights, int startIndex);

  String formatTickMark(TickMark mark, ChartOptions options);

  /// Label of the crosshair on the horizontal axis.
  String formatHorzItem(num time, ChartOptions options);

  /// Weight from which tick mark labels are bold.
  int maxTickMarkWeight(Iterable<int> weights) => weights.reduce((a, b) => a > b ? a : b);
}

/// Time axis: [SeriesData.time] is a UTC timestamp in seconds.
class TimeHorzScaleBehavior extends HorzScaleBehavior {
  const TimeHorzScaleBehavior();

  @override
  void fillWeights(List<num> times, List<int> weights, int startIndex) =>
      fillWeightsForPoints(times, weights, startIndex);

  @override
  String formatTickMark(TickMark mark, ChartOptions options) {
    final ts = options.timeScale;
    final l = options.localization;
    final type = weightToTickMarkType(mark.weight, ts.timeVisible, ts.secondsVisible);
    return ts.tickMarkFormatter?.call(mark.time, type, l.locale) ??
        defaultTickMarkFormatter(mark.time, type, l.shortMonthNames);
  }

  @override
  String formatHorzItem(num time, ChartOptions options) {
    final l = options.localization;
    final custom = l.timeFormatter;
    if (custom != null) return custom(time);
    return defaultTimeFormatter(
      time,
      dateFormat: l.dateFormat,
      shortMonthNames: l.shortMonthNames,
      longMonthNames: l.longMonthNames,
      timeVisible: options.timeScale.timeVisible,
      secondsVisible: options.timeScale.secondsVisible,
    );
  }

  /// The heaviest visible weight is bold, capped at month, like upstream.
  @override
  int maxTickMarkWeight(Iterable<int> weights) {
    final max = super.maxTickMarkWeight(weights);
    return max > TickMarkWeight.day ? TickMarkWeight.month : max;
  }
}

/// Price axis for options charts: [SeriesData.time] is a strike price.
class PriceHorzScaleBehavior extends HorzScaleBehavior {
  const PriceHorzScaleBehavior({this.precision = 2});

  /// Decimals of the axis labels.
  final int precision;

  static int _priceWeight(num price) {
    bool multipleOf(num step) => price == (price / step).ceil() * step;
    if (multipleOf(100)) return 8;
    if (multipleOf(50)) return 7;
    if (multipleOf(25)) return 6;
    if (multipleOf(10)) return 5;
    if (multipleOf(5)) return 4;
    if (price == price.ceil()) return 3;
    if (price * 2 == (price * 2).ceil()) return 1;
    return 0;
  }

  @override
  void fillWeights(List<num> times, List<int> weights, int startIndex) {
    for (var i = startIndex; i < times.length; i++) {
      weights[i] = _priceWeight(times[i]);
    }
  }

  String _format(num price, ChartOptions options) =>
      options.localization.timeFormatter?.call(price) ?? price.toStringAsFixed(precision);

  @override
  String formatTickMark(TickMark mark, ChartOptions options) => _format(mark.time, options);

  @override
  String formatHorzItem(num time, ChartOptions options) => _format(time, options);
}

/// Options of a yield curve chart.
class YieldCurveOptions {
  const YieldCurveOptions({
    this.baseResolution = 1,
    this.minimumTimeRange = 120,
    this.startTimeRange = 0,
    this.formatTime,
  });

  /// Spacing of the axis in months.
  final int baseResolution;

  /// The axis always spans at least this many months.
  final int minimumTimeRange;

  /// First month of the axis.
  final int startTimeRange;

  /// Overrides the `1M` / `2Y6M` labels.
  final String Function(num months)? formatTime;
}

/// Months axis for yield curves: [SeriesData.time] is a duration in months.
class YieldCurveHorzScaleBehavior extends HorzScaleBehavior {
  const YieldCurveHorzScaleBehavior(this.options);

  final YieldCurveOptions options;

  static int _monthWeight(num time) {
    if (time % 120 == 0) return 10;
    if (time % 60 == 0) return 9;
    if (time % 36 == 0) return 8;
    if (time % 12 == 0) return 7;
    if (time % 6 == 0) return 6;
    if (time % 3 == 0) return 5;
    if (time % 1 == 0) return 4;
    return 0;
  }

  @override
  void fillWeights(List<num> times, List<int> weights, int startIndex) {
    for (var i = startIndex; i < times.length; i++) {
      weights[i] = _monthWeight(times[i]);
    }
  }

  String _format(num months, ChartOptions chart) {
    final custom = options.formatTime ?? chart.localization.timeFormatter;
    if (custom != null) return custom(months);
    if (months < 12) return '${months}M';
    final years = months ~/ 12;
    final remaining = months % 12;
    return remaining == 0 ? '${years}Y' : '${years}Y${remaining}M';
  }

  @override
  String formatTickMark(TickMark mark, ChartOptions options) => _format(mark.time, options);

  @override
  String formatHorzItem(num time, ChartOptions options) => _format(time, options);
}
