import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/src/renderers/label_alignment.dart';

class _Label implements AlignableLabel {
  _Label(this.coordinate) : render = coordinate;

  @override
  final double coordinate;

  @override
  double render;
}

void main() {
  // Fixtures were produced by running upstream's _fixLabelOverlap /
  // recalculateOverlapping on random label sets.
  test('alignLabels matches lightweight-charts', () {
    final cases = jsonDecode(File('test/fixtures/align_labels.json').readAsStringSync()) as List<dynamic>;
    expect(cases, hasLength(300));
    for (final c in cases.cast<Map<String, dynamic>>()) {
      final labels = [for (final v in c['coords'] as List<dynamic>) _Label((v as num).toDouble())];
      fixLabelOverlap(
        labels,
        (c['height'] as num).toDouble(),
        (c['labelHeight'] as num).toDouble(),
        (c['center'] as num).toDouble(),
      );
      final expected = [for (final v in c['renders'] as List<dynamic>) (v as num).toDouble()];
      for (var i = 0; i < labels.length; i++) {
        expect(labels[i].render, closeTo(expected[i], 1e-9), reason: '$c');
      }
    }
  });
}
