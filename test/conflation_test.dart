import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/src/model/series.dart';
import 'package:swm_chart/swm_chart.dart';

/// Straight port of upstream's DataConflater for OHLC rows: level 2 from
/// the data in pairs (a trailing odd row folded into the previous chunk),
/// level 2k from level k.
List<(int, double, double, double, double)> referenceLevel(
  List<(int, double, double, double, double)> rows,
  int level,
) {
  List<(int, double, double, double, double)> pairs(List<(int, double, double, double, double)> src) {
    final out = <(int, double, double, double, double)>[];
    for (var i = 0; i < src.length; i += 2) {
      if (i + 1 < src.length) {
        final a = src[i], b = src[i + 1];
        out.add((a.$1, a.$2, math.max(a.$3, b.$3), math.min(a.$4, b.$4), b.$5));
      } else if (out.isEmpty) {
        out.add(src[i]);
      } else {
        final a = out.removeLast(), b = src[i];
        out.add((a.$1, a.$2, math.max(a.$3, b.$3), math.min(a.$4, b.$4), b.$5));
      }
    }
    return out;
  }

  var current = rows;
  for (var l = 2; l <= level; l *= 2) {
    current = pairs(current);
  }
  return current;
}

List<(int, double, double, double, double)> rowsOf(SeriesItems<CandlestickData> items) => [
  for (var i = 0; i < items.length; i++)
    (items.indices[i], items.data[i].open, items.data[i].high, items.data[i].low, items.data[i].close),
];

CandlestickData bar(int i, math.Random r) {
  final o = r.nextDouble() * 100;
  return CandlestickData(
    time: i,
    open: o,
    high: o + r.nextDouble() * 10,
    low: o - r.nextDouble() * 10,
    close: r.nextDouble() * 100,
  );
}

void main() {
  test('normalizeConflationLevel', () {
    expect(SeriesModel.normalizeConflationLevel(1), 2);
    expect(SeriesModel.normalizeConflationLevel(3), 4);
    expect(SeriesModel.normalizeConflationLevel(64), 64);
    expect(SeriesModel.normalizeConflationLevel(5000), 512);
  });

  for (final n in [2, 3, 7, 64, 65, 1001]) {
    test('levels match upstream for $n bars', () {
      final r = math.Random(n);
      final chart = ChartController();
      final s = chart.addCandlestickSeries()..setData([for (var i = 0; i < n; i++) bar(i, r)]);
      final model = chart.model.series.first as CandlestickSeriesModel;
      final rows = rowsOf(model.renderItems(1));
      for (final level in [2, 4, 8, 64, 512]) {
        expect(rowsOf(model.renderItems(level)), referenceLevel(rows, level), reason: 'level $level');
      }
      expect(s, isNotNull);
      chart.dispose();
    });
  }

  test('incremental updates match a fresh build', () {
    final r = math.Random(7);
    final chart = ChartController();
    final s = chart.addCandlestickSeries()..setData([for (var i = 0; i < 300; i++) bar(i, r)]);
    final model = chart.model.series.first as CandlestickSeriesModel;
    for (final level in [2, 8, 32]) {
      model.renderItems(level); // build the cache
    }
    var next = 300;
    for (var round = 0; round < 200; round++) {
      // Mostly replace the last bar, sometimes append.
      if (r.nextInt(4) == 0) {
        s.update(bar(next++, r));
      } else {
        s.update(bar(next - 1, r));
      }
      final level = [2, 8, 32][round % 3];
      final rows = rowsOf(model.renderItems(1));
      expect(rowsOf(model.renderItems(level)), referenceLevel(rows, level), reason: 'round $round level $level');
    }
    chart.dispose();
  });

  test('custom series conflate with the view reducer, or not at all', () {
    final chart = ChartController();
    final reducing = chart.addCustomSeries(_SumView(reduce: true));
    final plain = chart.addCustomSeries(_SumView(reduce: false));
    final data = [for (var i = 0; i < 9; i++) _Value(time: i, v: i.toDouble())];
    reducing.setData(data);
    plain.setData(data);
    final models = chart.model.series.toList();
    final conflated = models[0].renderItems(4);
    // Chunks of 4 (the odd last item folds into the last chunk): sums 6, 22+8.
    expect([for (final d in conflated.data) (d as _Value).v], [6, 30]);
    expect(conflated.indices, [0, 4]);
    expect(models[1].renderItems(4).length, 9);
    chart.dispose();
  });

  test('per-series conflationThresholdFactor', () {
    final chart = ChartController(
      options: const ChartOptions(
        timeScale: TimeScaleOptions(enableConflation: true, barSpacing: 0.3, minBarSpacing: 0.01),
      ),
    );
    final ts = chart.model.timeScale;
    expect(ts.conflationFactor(2), 1); // 0.3 >= 0.5 / 1? no: threshold 0.5 -> factor 1
    expect(ts.conflationFactor(2, 4), 4); // threshold 2 -> 2 / 0.3 = 6.6 -> 4
    expect(ts.possibleConflationFactors(2), [1, 2, 4, 8, 16, 32]);
    chart.dispose();
  });

  testWidgets('precomputeConflationOnInit builds levels in a scheduled task', (tester) async {
    final chart = ChartController(
      options: const ChartOptions(
        timeScale: TimeScaleOptions(enableConflation: true, precomputeConflationOnInit: true, minBarSpacing: 0.01),
      ),
    );
    final r = math.Random(3);
    chart.addCandlestickSeries().setData([for (var i = 0; i < 1000; i++) bar(i, r)]);
    final model = chart.model.series.first;
    // Run the scheduled idle task.
    await tester.pump();
    await tester.idle();
    expect(model.cachedConflationLevels, containsAll([2, 4, 8, 16, 32]));
    chart.dispose();
  });
}

class _Value extends SeriesData {
  const _Value({required super.time, required this.v});

  final double v;
}

class _SumView extends CustomSeriesView<_Value> {
  _SumView({required this.reduce});

  final bool reduce;

  @override
  List<double> priceValues(_Value item) => [item.v];

  @override
  void draw(CustomSeriesDrawContext<_Value> ctx) {}

  @override
  _Value Function(CustomConflationContext<_Value> a, CustomConflationContext<_Value> b)? get conflationReducer =>
      reduce ? (a, b) => _Value(time: a.time, v: a.data.v + b.data.v) : null;
}
