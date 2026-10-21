import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/swm_chart.dart';

const _day = 86400;
const _t0 = 1704067200;

List<CandlestickData> _bars(int count) => List.generate(count, (i) {
  final o = 100.0 + (i % 20);
  return CandlestickData(time: _t0 + i * _day, open: o, high: o + 3, low: o - 3, close: i.isEven ? o + 1 : o - 1);
});

Future<ChartController> _pump(WidgetTester tester, {ChartOptions options = const ChartOptions()}) async {
  final chart = ChartController(options: options);
  chart.addCandlestickSeries().setData(_bars(300));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 400, height: 300, child: SwmChart(controller: chart)),
      ),
    ),
  );
  addTearDown(chart.dispose);
  return chart;
}

void main() {
  testWidgets('a handler that takes the drag gets its events and the chart does not scroll', (tester) async {
    final chart = await _pump(tester);
    final events = <ChartPointerEvent>[];
    chart.subscribePointer((e) {
      events.add(e);
      return true;
    });
    final before = chart.timeScale().scrollPosition();
    await tester.dragFrom(const Offset(200, 100), const Offset(-80, 60));
    await tester.pumpAndSettle();

    expect(chart.timeScale().scrollPosition(), before);
    expect(events.first.phase, ChartPointerPhase.down);
    expect(events.last.phase, ChartPointerPhase.up);
    expect(events.where((e) => e.phase == ChartPointerPhase.move), isNotEmpty);
    expect(events.every((e) => e.source == ChartPointerSource.drag && e.paneIndex == 0), isTrue);
    // Moving down and left: a lower price and an earlier bar.
    expect(events.last.price, lessThan(events.first.price!));
    expect(events.last.logical, lessThan(events.first.logical));
    expect(events.first.time, isNotNull);
  });

  testWidgets('a handler that declines leaves the drag to the chart', (tester) async {
    final chart = await _pump(tester);
    final phases = <ChartPointerPhase>[];
    chart.subscribePointer((e) {
      phases.add(e.phase);
      return false;
    });
    final before = chart.timeScale().scrollPosition();
    await tester.dragFrom(const Offset(200, 150), const Offset(120, 0));
    await tester.pumpAndSettle();

    expect(chart.timeScale().scrollPosition(), lessThan(before));
    expect(phases, [ChartPointerPhase.down]);
  });

  testWidgets('the latest handler is offered the gesture first', (tester) async {
    final chart = await _pump(tester);
    final calls = <String>[];
    chart.subscribePointer((e) {
      calls.add('first ${e.phase.name}');
      return true;
    });
    chart.subscribePointer((e) {
      calls.add('second ${e.phase.name}');
      return true;
    });
    await tester.dragFrom(const Offset(200, 150), const Offset(60, 0));
    await tester.pumpAndSettle();

    expect(calls.first, 'second down');
    expect(calls.any((c) => c.startsWith('first')), isFalse);
  });

  testWidgets('with the long-press crosshair off, long presses go to the handlers', (tester) async {
    final chart = await _pump(
      tester,
      options: const ChartOptions(trackingMode: TrackingModeOptions(longPressCrosshair: false)),
    );
    final events = <ChartPointerEvent>[];
    chart.subscribePointer((e) {
      events.add(e);
      return e.source == ChartPointerSource.longPress;
    });
    final gesture = await tester.startGesture(const Offset(150, 100));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(40, 20));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(chart.model.crosshair, isNull);
    final press = events.where((e) => e.source == ChartPointerSource.longPress).toList();
    expect(press.map((e) => e.phase), [ChartPointerPhase.down, ChartPointerPhase.move, ChartPointerPhase.up]);
    expect(press.last.point.dx, greaterThan(press.first.point.dx));
  });

  testWidgets('clicks report the price under the pointer', (tester) async {
    final chart = await _pump(tester);
    final prices = <double?>[];
    chart.subscribeClick((p) => prices.add(p.price));
    await tester.tapAt(const Offset(200, 60));
    await tester.pump(kDoubleTapTimeout);
    await tester.tapAt(const Offset(200, 200));
    await tester.pump(kDoubleTapTimeout);

    expect(prices, hasLength(2));
    expect(prices[0], greaterThan(prices[1]!));
  });

  testWidgets('a pane converts between prices and coordinates', (tester) async {
    final chart = await _pump(tester);
    final pane = chart.panes().first;
    final y = pane.priceToCoordinate(110)!;
    expect(pane.coordinateToPrice(y), closeTo(110, 0.01));
  });
}
