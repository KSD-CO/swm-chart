import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/src/model/tick_marks.dart';
import 'package:swm_chart/src/model/time_utils.dart';

List<(int, int)> _summary(List<TickMark> marks) => [for (final m in marks) (m.index, m.weight)];

void main() {
  for (final (name, step) in [('1 minute', 60), ('5 minutes', 300), ('1 hour', 3600), ('1 day', 86400)]) {
    test('appending bars rebuilds only the tail, same result as a full rebuild ($name)', () {
      final random = math.Random(step);
      final times = <num>[];
      final weights = <int>[];
      var t = 1700000000;
      for (var i = 0; i < 5000; i++) {
        t += step * (random.nextInt(20) == 0 ? 3 : 1); // occasional gaps
        times.add(t);
        weights.add(0);
      }
      fillWeightsForPoints(times, weights);

      final incremental = TickMarks()..setTimeScalePoints(times, weights, 0);
      for (final spacing in [0.5, 3.0, 12.0]) {
        incremental.build(spacing, 60);
      }

      for (var round = 0; round < 300; round++) {
        final from = times.length;
        final count = 1 + random.nextInt(3);
        for (var i = 0; i < count; i++) {
          t += step;
          times.add(t);
          weights.add(0);
        }
        fillWeightsForPoints(times, weights, from);
        incremental.setTimeScalePoints(times, weights, from);
        final spacing = [0.5, 3.0, 12.0][round % 3];
        final full = TickMarks()..setTimeScalePoints(times, weights, 0);
        expect(
          _summary(incremental.build(spacing, 60)),
          _summary(full.build(spacing, 60)),
          reason: 'round $round, spacing $spacing',
        );
      }
    });
  }

  test('with indicesWithData filtering', () {
    final times = <num>[for (var i = 0; i < 3000; i++) 1700000000 + i * 60];
    final weights = List<int>.filled(times.length, 0, growable: true);
    fillWeightsForPoints(times, weights);
    final withData = {for (var i = 0; i < times.length; i += 3) i};
    final incremental = TickMarks()..setTimeScalePoints(times, weights, 0);
    incremental.build(2, 60, checkIndicesForData: true, indicesWithData: withData, indicesWithDataId: 1);
    for (var round = 0; round < 100; round++) {
      final from = times.length;
      times.add(times.last + 60);
      weights.add(0);
      fillWeightsForPoints(times, weights, from);
      incremental.setTimeScalePoints(times, weights, from);
      final full = TickMarks()..setTimeScalePoints(times, weights, 0);
      expect(
        _summary(incremental.build(2, 60, checkIndicesForData: true, indicesWithData: withData, indicesWithDataId: 1)),
        _summary(full.build(2, 60, checkIndicesForData: true, indicesWithData: withData, indicesWithDataId: 1)),
      );
    }
  });
}
