import 'dart:ui' show Color;

/// Base class of every data item. [time] is a UTC timestamp in **seconds**.
///
/// Like Lightweight Charts, labels are rendered from the UTC components of
/// [time]; to show exchange-local time, shift the timestamps before passing
/// them in.
abstract class SeriesData {
  const SeriesData({required this.time});

  final int time;
}

/// Data for a candlestick series.
class CandlestickData extends SeriesData {
  const CandlestickData({
    required super.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.color,
    this.borderColor,
    this.wickColor,
  });

  final double open;
  final double high;
  final double low;
  final double close;

  /// Overrides the series up/down body color for this bar.
  final Color? color;
  final Color? borderColor;
  final Color? wickColor;

  bool get isUp => close >= open;

  @override
  String toString() => 'CandlestickData(time: $time, o: $open, h: $high, l: $low, c: $close)';
}

/// Data with a single value (line, histogram).
abstract class SingleValueData extends SeriesData {
  const SingleValueData({required super.time, required this.value, this.color});

  final double value;

  /// Overrides the series color for this point.
  final Color? color;
}

class LineData extends SingleValueData {
  const LineData({required super.time, required super.value, super.color});

  @override
  String toString() => 'LineData(time: $time, value: $value)';
}

class HistogramData extends SingleValueData {
  const HistogramData({required super.time, required super.value, super.color});

  @override
  String toString() => 'HistogramData(time: $time, value: $value)';
}
