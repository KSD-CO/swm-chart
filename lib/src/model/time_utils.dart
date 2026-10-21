// Port of lightweight-charts
// src/model/horz-scale-behavior-time/time-scale-point-weight-generator.ts
// and the default tick mark / date formatters.
import '../options.dart';

/// Tick mark weights, as in lightweight-charts `TickMarkWeight`.
abstract final class TickMarkWeight {
  static const int lessThanSecond = 0;
  static const int second = 10;
  static const int minute1 = 20;
  static const int minute5 = 21;
  static const int minute30 = 22;
  static const int hour1 = 30;
  static const int hour3 = 31;
  static const int hour6 = 32;
  static const int hour12 = 33;
  static const int day = 50;
  static const int month = 60;
  static const int year = 70;
}

const List<(int, int)> _intradayWeightDivisors = [
  (1000, TickMarkWeight.second),
  (60 * 1000, TickMarkWeight.minute1),
  (5 * 60 * 1000, TickMarkWeight.minute5),
  (30 * 60 * 1000, TickMarkWeight.minute30),
  (60 * 60 * 1000, TickMarkWeight.hour1),
  (3 * 60 * 60 * 1000, TickMarkWeight.hour3),
  (6 * 60 * 60 * 1000, TickMarkWeight.hour6),
  (12 * 60 * 60 * 1000, TickMarkWeight.hour12),
];

DateTime utcDate(int seconds) => DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

int _weightByTime(DateTime current, DateTime prev) {
  if (current.year != prev.year) return TickMarkWeight.year;
  if (current.month != prev.month) return TickMarkWeight.month;
  if (current.day != prev.day) return TickMarkWeight.day;

  final currentMs = current.millisecondsSinceEpoch;
  final prevMs = prev.millisecondsSinceEpoch;
  for (var i = _intradayWeightDivisors.length - 1; i >= 0; --i) {
    final (divisor, weight) = _intradayWeightDivisors[i];
    if (prevMs ~/ divisor != currentMs ~/ divisor) return weight;
  }
  return TickMarkWeight.lessThanSecond;
}

/// Fills [weights] for [times] (sorted, seconds) starting at [startIndex].
void fillWeightsForPoints(List<int> times, List<int> weights, [int startIndex = 0]) {
  if (times.isEmpty) return;

  int? prevTime = startIndex == 0 ? null : times[startIndex - 1];
  DateTime? prevDate = prevTime != null ? utcDate(prevTime) : null;
  var totalTimeDiff = 0;

  for (var index = startIndex; index < times.length; ++index) {
    final currentTime = times[index];
    final currentDate = utcDate(currentTime);
    if (prevDate != null) {
      weights[index] = _weightByTime(currentDate, prevDate);
    }
    totalTimeDiff += currentTime - (prevTime ?? currentTime);
    prevTime = currentTime;
    prevDate = currentDate;
  }

  if (startIndex == 0 && times.length > 1) {
    // Guess the first point's weight assuming the previous point was one
    // average interval back in history.
    final averageTimeDiff = (totalTimeDiff / (times.length - 1)).ceil();
    final approxPrevDate = utcDate(times[0] - averageTimeDiff);
    weights[0] = _weightByTime(utcDate(times[0]), approxPrevDate);
  }
}

TickMarkType weightToTickMarkType(int weight, bool timeVisible, bool secondsVisible) {
  if (weight <= TickMarkWeight.second) {
    return timeVisible
        ? (secondsVisible ? TickMarkType.timeWithSeconds : TickMarkType.time)
        : TickMarkType.dayOfMonth;
  }
  if (weight < TickMarkWeight.day) {
    return timeVisible ? TickMarkType.time : TickMarkType.dayOfMonth;
  }
  if (weight == TickMarkWeight.day) return TickMarkType.dayOfMonth;
  if (weight == TickMarkWeight.month) return TickMarkType.month;
  return TickMarkType.year;
}

const List<String> _monthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
];

String _two(int v) => v.toString().padLeft(2, '0');

String defaultTickMarkFormatter(int time, TickMarkType type) {
  final d = utcDate(time);
  switch (type) {
    case TickMarkType.year:
      return '${d.year}';
    case TickMarkType.month:
      return _monthsShort[d.month - 1];
    case TickMarkType.dayOfMonth:
      return '${d.day}';
    case TickMarkType.time:
      return '${_two(d.hour)}:${_two(d.minute)}';
    case TickMarkType.timeWithSeconds:
      return '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';
  }
}

/// Default crosshair time label: `dd MMM 'yy` plus `HH:mm[:ss]` when time is visible.
String defaultTimeFormatter(int time, {required bool timeVisible, required bool secondsVisible}) {
  final d = utcDate(time);
  final date = "${_two(d.day)} ${_monthsShort[d.month - 1]} '${_two(d.year % 100)}";
  if (!timeVisible) return date;
  final clock = secondsVisible
      ? '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}'
      : '${_two(d.hour)}:${_two(d.minute)}';
  return '$date $clock';
}
