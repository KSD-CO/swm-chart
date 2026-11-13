import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/swm_chart.dart';

const _day = 86400;

CandlestickData _bar(int i, double close) =>
    CandlestickData(time: i * _day, open: close, high: close + 0.5, low: close - 0.5, close: close);

List<CandlestickData> _closes(List<double> closes) => [for (final (i, c) in closes.indexed) _bar(i, c)];

void main() {
  group('Point & figure', () {
    test('a rising column, then a falling one after three boxes back', () {
      final cols = pointAndFigure(_closes([10, 11, 12, 13, 12, 11, 10, 9]), boxSize: 1);
      expect(cols, hasLength(2));
      // Xs from 10 to 13.
      expect((cols[0].open, cols[0].close), (10.0, 13.0));
      // Os from 12 down to 9, started by the bar that reversed.
      expect((cols[1].open, cols[1].close), (12.0, 9.0));
      expect(cols[1].time, 6 * _day);
    });

    test('a pullback smaller than the reversal keeps the column', () {
      final cols = pointAndFigure(_closes([10, 12, 11, 10.5, 14]), boxSize: 1);
      expect(cols, hasLength(1));
      expect(cols.single.close, 14);
    });
  });

  group('Kagi', () {
    test('turns on a reversal, thick past the shoulder, thin below the waist', () {
      final line = kagi(_closes([10, 14, 11, 15, 12, 9]), reversal: 2);
      // Start, the turn at 14, the turn at 11, the turn at 15, and the end.
      expect([for (final p in line) p.value], [10, 14, 11, 15, 9]);
      final yang = line.first.color;
      expect(line[3].color, yang); // 15 > the 14 shoulder
      expect(line.last.color, isNot(yang)); // 9 < the 11 waist
      final times = [for (final p in line) p.time];
      expect(times, orderedEquals([...times]..sort()));
    });
  });

  test('box size: rounded average true range', () {
    final bars = [
      for (var i = 0; i < 30; i++) CandlestickData(time: i * _day, open: 100, high: 101.7, low: 100, close: 100.5),
    ];
    expect(autoBoxSize(bars), 2); // ATR 1.7 -> 2
    expect(autoBoxSize(bars.take(5).toList()), 1); // too few: 1% of 100.5 -> 1
  });

  testWidgets('the pro chart draws every built type, without volume', (tester) async {
    final pro = ProChartController()
      ..setData(
        [for (var i = 0; i < 200; i++) _bar(i, 100 + 10 * ((i % 40) - 20).abs() / 20)],
        volumes: [for (var i = 0; i < 200; i++) 1000.0],
      );
    addTearDown(pro.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SwmProChart(controller: pro)),
      ),
    );
    for (final type in ProChartType.values.where((t) => t.isBuilt)) {
      pro.type = type;
      await tester.pump();
      expect(pro.mainSeries.data(), isNotEmpty, reason: type.name);
      expect(pro.volumeSeries?.data() ?? const [], isEmpty, reason: type.name);
      // A tick rebuilds it.
      pro.update(_bar(200, 130));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: type.name);
    }
    pro.type = ProChartType.candles;
    await tester.pump();
    expect(pro.volumeSeries?.data(), isNotEmpty);
    pro.brickSize = 5;
    expect(pro.effectiveBrickSize, 5);
  });
}
