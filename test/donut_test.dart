import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/swm_chart.dart';

const _slices = [
  SwmDonutSlice(value: 50, color: Color(0xFF26A69A)),
  SwmDonutSlice(value: 25, color: Color(0xFFEF5350)),
  SwmDonutSlice(value: 0, color: Color(0xFF000000)),
  SwmDonutSlice(value: 25, color: Color(0xFF2962FF)),
];

void main() {
  const donut = SwmDonut(slices: _slices, size: 100, innerRadius: 20, thickness: 20);

  test('hit tests by angle from 12 o\'clock, skipping empty slices', () {
    // Right of center: a quarter turn in → still the first half.
    expect(donut.sliceAt(const Offset(80, 50)), 0);
    // Below center: half a turn → start of the second slice.
    expect(donut.sliceAt(const Offset(48, 80)), 1);
    // Left of center: three quarters → the last (non-empty) slice.
    expect(donut.sliceAt(const Offset(20, 48)), 3);
    // In the hole or outside the ring.
    expect(donut.sliceAt(const Offset(50, 50)), isNull);
    expect(donut.sliceAt(const Offset(99, 99)), isNull);
  });

  test('paints any input without throwing', () {
    for (final slices in [
      const <SwmDonutSlice>[],
      const [SwmDonutSlice(value: 1, color: Color(0xFF000000))],
      const [SwmDonutSlice(value: double.nan, color: Color(0xFF000000))],
      _slices,
    ]) {
      final recorder = ui.PictureRecorder();
      SwmDonutPainter(
        slices: slices,
        innerRadius: 20,
        thickness: 20,
        selectedThickness: 26,
        selected: 0,
      ).paint(Canvas(recorder), const Size(100, 100));
      recorder.endRecording().dispose();
    }
  });

  testWidgets('touch selects a slice and release clears it', (tester) async {
    final events = <int?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SwmDonut(
            slices: _slices,
            size: 100,
            innerRadius: 20,
            thickness: 20,
            onSelect: events.add,
            center: const Text('Total'),
          ),
        ),
      ),
    );
    expect(find.text('Total'), findsOneWidget);
    final topLeft = tester.getTopLeft(find.byType(SwmDonut));
    await tester.tapAt(topLeft + const Offset(80, 50));
    expect(events.first, 0);
    expect(events.last, isNull);
  });
}
