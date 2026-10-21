import 'dart:ui' show Color;

/// Base class of every data item.
///
/// [time] is the horizontal value: a UTC timestamp in **seconds** on a time
/// chart, a duration in months on a yield curve chart, a strike price on an
/// options chart.
///
/// Like Lightweight Charts, time labels are rendered from the UTC
/// components of [time]; to show exchange-local time, shift the timestamps
/// before passing them in.
abstract class SeriesData {
  const SeriesData({required this.time});

  final num time;
}

/// A point in time without a value: it extends the time scale but draws
/// nothing (e.g. a session gap). Accepted by every series.
class WhitespaceData extends SeriesData {
  const WhitespaceData({required super.time});

  @override
  String toString() => 'WhitespaceData(time: $time)';
}

/// Open/high/low/close data.
abstract class OhlcData extends SeriesData {
  const OhlcData({
    required super.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.color,
  });

  final double open;
  final double high;
  final double low;
  final double close;

  /// Overrides the series up/down color for this bar.
  final Color? color;

  bool get isUp => close >= open;
}

/// Data for a candlestick series.
class CandlestickData extends OhlcData {
  const CandlestickData({
    required super.time,
    required super.open,
    required super.high,
    required super.low,
    required super.close,
    super.color,
    this.borderColor,
    this.wickColor,
  });

  final Color? borderColor;
  final Color? wickColor;

  @override
  String toString() => 'CandlestickData(time: $time, o: $open, h: $high, l: $low, c: $close)';
}

/// Data for a bar (OHLC) series.
class BarData extends OhlcData {
  const BarData({
    required super.time,
    required super.open,
    required super.high,
    required super.low,
    required super.close,
    super.color,
  });

  @override
  String toString() => 'BarData(time: $time, o: $open, h: $high, l: $low, c: $close)';
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

class AreaData extends SingleValueData {
  const AreaData({required super.time, required super.value, this.lineColor, this.topColor, this.bottomColor})
    : super(color: lineColor);

  final Color? lineColor;
  final Color? topColor;
  final Color? bottomColor;

  @override
  String toString() => 'AreaData(time: $time, value: $value)';
}

class BaselineData extends SingleValueData {
  const BaselineData({
    required super.time,
    required super.value,
    this.topLineColor,
    this.topFillColor1,
    this.topFillColor2,
    this.bottomLineColor,
    this.bottomFillColor1,
    this.bottomFillColor2,
  });

  final Color? topLineColor;
  final Color? topFillColor1;
  final Color? topFillColor2;
  final Color? bottomLineColor;
  final Color? bottomFillColor1;
  final Color? bottomFillColor2;

  @override
  String toString() => 'BaselineData(time: $time, value: $value)';
}
