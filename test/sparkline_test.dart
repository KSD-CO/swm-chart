import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/swm_chart.dart';

void main() {
  test('color follows the direction, or the baseline', () {
    expect(SwmSparklinePainter(values: const [1, 2, 3]).resolvedColor, kSparklineUpColor);
    expect(SwmSparklinePainter(values: const [3, 2, 1]).resolvedColor, kSparklineDownColor);
    expect(SwmSparklinePainter(values: const [3, 2, 2.5], baseline: 2).resolvedColor, kSparklineUpColor);
    expect(
      SwmSparklinePainter(values: const [1, 3], color: const Color(0xFF123456)).resolvedColor,
      const Color(0xFF123456),
    );
    expect(SwmSparklinePainter(values: const [double.nan, 2, 1]).resolvedColor, kSparklineDownColor);
  });

  test('paints any input without throwing', () {
    for (final values in <List<double>>[
      const [],
      const [5],
      const [5, 5, 5],
      const [1, double.nan, 3, double.infinity, 2],
      [for (var i = 0; i < 500; i++) i.toDouble()],
    ]) {
      for (final curved in [false, true]) {
        final recorder = ui.PictureRecorder();
        SwmSparklinePainter(
          values: values,
          curved: curved,
          baseline: 2,
          lastPointDot: true,
        ).paint(Canvas(recorder), const Size(80, 30));
        recorder.endRecording().dispose();
      }
    }
  });

  test('repaints only when something changed', () {
    final a = SwmSparklinePainter(values: const [1, 2, 3]);
    expect(SwmSparklinePainter(values: const [1, 2, 3]).shouldRepaint(a), isFalse);
    expect(SwmSparklinePainter(values: const [1, 2, 4]).shouldRepaint(a), isTrue);
    expect(SwmSparklinePainter(values: const [1, 2, 3], area: false).shouldRepaint(a), isTrue);
  });

  testWidgets('lays out at its size, fills the width when none given', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            SwmSparkline(key: Key('fixed'), values: [1, 3, 2], width: 80, height: 30),
            SwmSparkline(key: Key('fill'), values: [1, 3, 2], semanticsLabel: 'Price trend'),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(const Key('fixed'))), const Size(80, 30));
    expect(tester.getSize(find.byKey(const Key('fill'))).width, 800);
    expect(find.bySemanticsLabel('Price trend'), findsOneWidget);
  });
}
