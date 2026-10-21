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

Future<(ChartController, DrawingEditor)> _pump(WidgetTester tester) async {
  final chart = ChartController();
  chart.addCandlestickSeries().setData(_bars(200));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 400, height: 300, child: SwmChart(controller: chart)),
      ),
    ),
  );
  final editor = DrawingEditor(chart);
  addTearDown(() {
    editor.dispose();
    chart.dispose();
  });
  await tester.pump();
  return (chart, editor);
}

DrawingFactory _trend = (id, anchors) => TrendLineDrawing(id: id, anchors: anchors);

Offset _at(ChartController chart, DrawingAnchor a) =>
    Offset(chart.timeScale().logicalToCoordinate(a.logical), chart.panes().first.priceToCoordinate(a.price)!);

Future<void> _tap(WidgetTester tester, Offset p) async {
  await tester.tapAt(p);
  await tester.pump(kDoubleTapTimeout);
}

void main() {
  testWidgets('a trend line is drawn with one drag and the chart does not scroll', (tester) async {
    final (chart, editor) = await _pump(tester);
    final created = <Drawing>[];
    editor
      ..onCreated = created.add
      ..tool = _trend;
    final before = chart.timeScale().scrollPosition();
    await tester.dragFrom(const Offset(100, 200), const Offset(150, -100));
    await tester.pumpAndSettle();

    expect(chart.timeScale().scrollPosition(), before);
    expect(created, hasLength(1));
    final line = created.single;
    expect(line, isA<TrendLineDrawing>());
    expect(line.anchors, hasLength(2));
    expect(line.anchors[1].logical, greaterThan(line.anchors[0].logical));
    expect(line.anchors[1].price, greaterThan(line.anchors[0].price));
    // Done: the tool clears and the new line is selected.
    expect(editor.tool, isNull);
    expect(editor.selected, line);
  });

  testWidgets('taps place the anchors one by one', (tester) async {
    final (_, editor) = await _pump(tester);
    editor.tool = (id, anchors) => ParallelChannelDrawing(id: id, anchors: anchors);
    await _tap(tester, const Offset(80, 200));
    await _tap(tester, const Offset(250, 120));
    expect(editor.isDrawing, isTrue);
    expect(editor.drawings, isEmpty);
    await _tap(tester, const Offset(150, 230));

    expect(editor.isDrawing, isFalse);
    expect(editor.drawings.single.anchors, hasLength(3));
  });

  testWidgets('a drawing is selected by a tap and moved by a drag', (tester) async {
    final (chart, editor) = await _pump(tester);
    final line = TrendLineDrawing(id: 'l', anchors: const [DrawingAnchor(150, 105), DrawingAnchor(180, 115)]);
    editor.add(line);
    await tester.pump();
    final mid = Offset.lerp(_at(chart, line.anchors[0]), _at(chart, line.anchors[1]), 0.5)!;

    final selections = <Object?>[];
    editor.onSelectionChanged = (d) => selections.add(d?.id);
    await _tap(tester, mid);
    expect(editor.selected, line);

    final changed = <Drawing>[];
    editor.onChanged = changed.add;
    final before = chart.timeScale().scrollPosition();
    final from = List.of(line.anchors);
    await tester.dragFrom(mid, const Offset(0, 40));
    await tester.pumpAndSettle();

    expect(chart.timeScale().scrollPosition(), before);
    expect(changed, [line]);
    expect(line.anchors[0].logical, closeTo(from[0].logical, 0.01));
    expect(line.anchors[0].price, lessThan(from[0].price));
    expect(line.anchors[1].price - line.anchors[0].price, closeTo(from[1].price - from[0].price, 1e-6));

    // A tap on empty space clears the selection.
    await _tap(tester, const Offset(30, 30));
    expect(editor.selected, isNull);
    expect(selections, ['l', null]);
  });

  testWidgets('dragging a handle of the selected drawing moves only that anchor', (tester) async {
    final (chart, editor) = await _pump(tester);
    final line = TrendLineDrawing(id: 'l', anchors: const [DrawingAnchor(150, 105), DrawingAnchor(180, 115)]);
    editor
      ..add(line)
      ..select('l');
    await tester.pump();
    final first = line.anchors[0];
    await tester.dragFrom(_at(chart, line.anchors[1]), const Offset(30, 0));
    await tester.pumpAndSettle();

    expect(line.anchors[0], first);
    expect(line.anchors[1].logical, greaterThan(180));
  });

  testWidgets('dragging empty space still scrolls the chart', (tester) async {
    final (chart, editor) = await _pump(tester);
    editor.add(TrendLineDrawing(id: 'l', anchors: const [DrawingAnchor(150, 105), DrawingAnchor(180, 115)]));
    final before = chart.timeScale().scrollPosition();
    await tester.dragFrom(const Offset(60, 40), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(chart.timeScale().scrollPosition(), lessThan(before));
  });

  testWidgets('freehand collects the stroke', (tester) async {
    final (_, editor) = await _pump(tester);
    editor.tool = (id, anchors) => FreehandDrawing(id: id, anchors: anchors);
    final gesture = await tester.startGesture(const Offset(100, 100));
    for (var i = 1; i <= 10; i++) {
      await gesture.moveBy(const Offset(10, 4));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(editor.drawings.single.anchors.length, greaterThan(5));
  });

  testWidgets('every built-in drawing paints, selected or not', (tester) async {
    final (_, editor) = await _pump(tester);
    const a = DrawingAnchor(150, 105), b = DrawingAnchor(185, 116), c = DrawingAnchor(170, 100);
    final all = <Drawing>[
      TrendLineDrawing(id: 1, anchors: const [a, b], extendRight: true),
      TrendLineDrawing(id: 2, anchors: const [a, b], arrow: true),
      HorizontalLineDrawing(id: 3, anchors: const [a], label: 'R1'),
      VerticalLineDrawing(id: 4, anchors: const [a]),
      CrossLineDrawing(id: 5, anchors: const [b]),
      RectangleDrawing(
        id: 6,
        anchors: const [a, b],
        style: const DrawingStyle(fillColor: Color(0x222962FF)),
      ),
      EllipseDrawing(id: 7, anchors: const [a, b]),
      ParallelChannelDrawing(
        id: 8,
        anchors: const [a, b, c],
        style: const DrawingStyle(fillColor: Color(0x222962FF)),
      ),
      FibRetracementDrawing(id: 9, anchors: const [a, b], extendRight: true),
      TextDrawing(id: 10, anchors: const [c], text: 'Note', backgroundColor: const Color(0xFFFFEB3B)),
      MeasureDrawing(id: 11, anchors: const [a, b]),
      PathDrawing.xabcd(id: 12, anchors: const [a, b, c, a, b]),
      FreehandDrawing(id: 13, anchors: const [a, c, b]),
    ];
    for (final d in all) {
      editor
        ..add(d)
        ..select(d.id);
      await tester.pump();
    }
    editor.select(null);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test('Fibonacci levels run from 1 at the first anchor to 0 at the second', () {
    final fib = FibRetracementDrawing(id: 'f', anchors: const [DrawingAnchor(0, 200), DrawingAnchor(10, 100)]);
    expect(fib.priceAt(1), 200);
    expect(fib.priceAt(0), 100);
    expect(fib.priceAt(0.618), closeTo(161.8, 1e-9));
  });

  test('a measurement reports the change and bar count', () {
    final m = MeasureDrawing(id: 'm', anchors: const [DrawingAnchor(10, 100), DrawingAnchor(22, 110)]);
    expect(m.change, 10);
    expect(m.changeFraction, closeTo(0.1, 1e-12));
    expect(m.bars, 12);
  });
}
