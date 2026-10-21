// Ported from lightweight-charts tests/unittests/time-scale.spec.ts
import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/src/model/time_scale.dart';
import 'package:swm_chart/src/options.dart';

TimeScale _make(TimeScaleOptions options, {double? width, int? lastIndex}) {
  final ts = TimeScale(options);
  if (width != null) ts.setWidth(width);
  if (lastIndex != null) {
    final times = List<int>.generate(lastIndex + 1, (i) => i);
    ts.update(times, List<int>.filled(times.length, 20), 0);
    ts.setBaseIndex(lastIndex);
  }
  return ts;
}

void main() {
  test('indexToCoordinate and coordinateToIndex inverse', () {
    final ts = _make(const TimeScaleOptions(barSpacing: 1, rightOffset: 0), width: 500, lastIndex: 499);
    expect(ts.indexToCoordinate(ts.coordinateToIndex(499.5)), 499.5);
  });

  test('indexToCoordinate for index 1', () {
    final ts = _make(const TimeScaleOptions(barSpacing: 1, rightOffset: 0), width: 500, lastIndex: 499);
    expect(ts.indexToCoordinate(1), 0.5);
  });

  test('setLogicalRange applies the range even with fewer bars than the minimum', () {
    final ts = _make(const TimeScaleOptions(minBarSpacing: 0, maxBarSpacing: 100000), width: 400, lastIndex: 1);
    ts.setLogicalRange(const LogicalRange(0.49, 0.51));
    final range = ts.visibleLogicalRange()!;
    expect(range.from, closeTo(0.49, 1e-6));
    expect(range.to, closeTo(0.51, 1e-6));
  });

  test('fitContent works with a large maxBarSpacing and a few bars', () {
    final ts = _make(const TimeScaleOptions(minBarSpacing: 0, maxBarSpacing: 100000), width: 400, lastIndex: 1);
    ts.fitContent();
    final range = ts.visibleLogicalRange()!;
    expect(range.from, 0);
    expect(range.to, 1);
  });

  test('applyOptions before layout keeps the bar spacing', () {
    final ts = TimeScale(const TimeScaleOptions(barSpacing: 8));
    ts.applyOptions(const TimeScaleOptions(barSpacing: 8, timeVisible: true));
    ts.setWidth(400);
    expect(ts.barSpacing, 8);
  });

  test('right offset set before layout survives', () {
    final ts = _make(const TimeScaleOptions(rightOffset: 5), lastIndex: 99);
    ts.setWidth(400);
    expect(ts.rightOffset, 5);
  });

  group('timeToIndex', () {
    test('returns index for time on scale', () {
      final ts = _make(const TimeScaleOptions(), lastIndex: 2);
      expect(ts.timeToIndex(0), 0);
      expect(ts.timeToIndex(1), 1);
      expect(ts.timeToIndex(2), 2);
    });

    test('returns null for time not on scale', () {
      final ts = _make(const TimeScaleOptions(), lastIndex: 2);
      expect(ts.timeToIndex(-1), isNull);
      expect(ts.timeToIndex(3), isNull);
    });

    test('returns null if empty', () {
      expect(TimeScale(const TimeScaleOptions()).timeToIndex(123), isNull);
    });

    test('findNearest clamps to the edges', () {
      final ts = _make(const TimeScaleOptions(), lastIndex: 2);
      expect(ts.timeToIndex(3, findNearest: true), 2);
      expect(ts.timeToIndex(-1, findNearest: true), 0);
    });
  });

  test('scroll is bounded so at least 2 bars stay visible', () {
    final ts = _make(const TimeScaleOptions(barSpacing: 10), width: 100, lastIndex: 99);
    ts.startScroll(0);
    ts.scrollTo(100000); // drag far to the right -> into history
    ts.endScroll();
    final range = ts.visibleStrictRange()!;
    expect(range.right, greaterThanOrEqualTo(1));
  });

  test('zoomAnchored keeps the anchor under the focal point', () {
    final ts = _make(const TimeScaleOptions(barSpacing: 10), width: 400, lastIndex: 199);
    final anchor = ts.coordinateToFloatIndex(200);
    ts.zoomAnchored(20, anchor, 200);
    expect(ts.barSpacing, 20);
    expect(ts.coordinateToFloatIndex(200), closeTo(anchor, 1e-6));
  });

  test('marks are spaced by at least the label width', () {
    final ts = _make(const TimeScaleOptions(barSpacing: 6), width: 600, lastIndex: 999);
    final marks = ts.marks(12, (m) => '${m.time}');
    expect(marks, isNotEmpty);
    for (var i = 1; i < marks.length; i++) {
      expect(marks[i].coord - marks[i - 1].coord, greaterThanOrEqualTo(60 - 1e-9));
    }
  });
}
