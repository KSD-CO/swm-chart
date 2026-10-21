import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/src/model/price_tick_span_calculator.dart';

void main() {
  // Fixtures were produced by running upstream's PriceTickSpanCalculator.
  test('tickSpan matches lightweight-charts', () {
    final cases = jsonDecode(File('test/fixtures/tick_span.json').readAsStringSync()) as List<dynamic>;
    expect(cases, isNotEmpty);
    for (final c in cases.cast<Map<String, dynamic>>()) {
      final calc = PriceTickSpanCalculator(
        c['base'] as int,
        (c['dividers'] as List<dynamic>).map((e) => (e as num).toDouble()).toList(),
      );
      final actual = calc.tickSpan(
        (c['high'] as num).toDouble(),
        (c['low'] as num).toDouble(),
        (c['maxTickSpan'] as num).toDouble(),
      );
      expect(actual, closeTo((c['expected'] as num).toDouble(), 1e-12), reason: '$c');
    }
  });

  test('isBaseDecimal', () {
    expect(isBaseDecimal(1), isTrue);
    expect(isBaseDecimal(100), isTrue);
    expect(isBaseDecimal(4), isFalse);
    expect(isBaseDecimal(25), isFalse);
  });
}
