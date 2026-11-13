import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/swm_chart.dart';

void main() {
  test('range bars end on prices where rounding misses the range', () {
    // VND prices: at 50 000 a double's step is ~7e-12, more than the old
    // 1e-12 slack, so a bar could stop just short of its range for ever.
    final bars = [
      for (var i = 0; i < 300; i++)
        CandlestickData(
          time: i * 3600,
          open: 50000 + (i % 17) * 50.0,
          high: 50300 + (i % 13) * 70.0,
          low: 49700 - (i % 11) * 30.0,
          close: 50000 + (i % 7) * 90.0,
        ),
    ];
    for (final range in [0.1, 0.3, 1.1, 7.7, 30.0, 70.0, 100.0, autoBoxSize(bars)]) {
      final out = rangeBars(bars, range: range);
      expect(out, isNotEmpty, reason: '$range');
    }
  }, timeout: const Timeout(Duration(seconds: 10)));
}
