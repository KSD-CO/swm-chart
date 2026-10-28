import 'ta.dart' show Ta;

/// One OHLCV bar for the technical-analysis functions in [Ta].
///
/// Implement it on your own bar type to pass your data straight in.
/// [open], [high] and [low] may be null (only a close is known); functions
/// that need them fall back to [close].
abstract interface class TaBar {
  DateTime get date;
  double get close;
  double? get open;
  double? get high;
  double? get low;
  double? get volume;
}

/// A plain [TaBar].
class TaPoint implements TaBar {
  const TaPoint({required this.date, required this.close, this.open, this.high, this.low, this.volume});

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
