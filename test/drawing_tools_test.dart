import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/swm_chart.dart';

const _day = 86400;
const _t0 = 1704067200;

List<CandlestickData> _bars(int count, [double base = 100]) => List.generate(count, (i) {
  final o = base + (i % 20);
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

void main() {
  group('time and logical index', () {
    const times = [100, 200, 300, 400];

    test('interpolate between bars and extrapolate past them', () {
      expect(logicalOfTime(times, 250), 1.5);
      expect(logicalOfTime(times, 600), 5);
      expect(logicalOfTime(times, 50), -0.5);
      expect(timeOfLogical(times, 1.5), 250);
      expect(timeOfLogical(times, 5), 600);
      expect(logicalOfTime(const [], 1), isNull);
    });
  });

  group('pricesAt', () {
    test('a trend line gives its price within its span, or extended', () {
      final t = TrendLineDrawing(id: 1, anchors: const [DrawingAnchor(10, 100), DrawingAnchor(20, 120)]);
      expect(t.pricesAt(15), [110]);
      expect(t.pricesAt(25), isEmpty);
      t.extendRight = true;
      expect(t.pricesAt(25), [130]);
    });

    test('a horizontal ray only from its anchor on', () {
      final h = HorizontalLineDrawing(id: 1, anchors: const [DrawingAnchor(10, 50)], ray: true);
      expect(h.pricesAt(5), isEmpty);
      expect(h.pricesAt(12), [50]);
    });

    test('a channel gives both rails and its middle', () {
      final c = ParallelChannelDrawing(
        id: 1,
        anchors: const [DrawingAnchor(0, 100), DrawingAnchor(10, 110), DrawingAnchor(5, 115)],
      );
      expect(c.pricesAt(5), [105, 115, 110]);
      expect(c.pricesAt(20), isEmpty);
    });

    test('a rectangle gives its bottom and top across its width', () {
      final r = RectangleDrawing(id: 1, anchors: const [DrawingAnchor(10, 120), DrawingAnchor(20, 100)]);
      expect(r.pricesAt(15), [100, 120]);
      expect(r.pricesAt(30), isEmpty);
    });
  });

  group('undo and redo', () {
    testWidgets('step back through adding, removing and clearing', (tester) async {
      final (_, editor) = await _pump(tester);
      var changes = 0;
      editor.onHistoryChanged = () => changes++;
      expect(editor.canUndo, isFalse);

      editor.add(TrendLineDrawing(id: 'a', anchors: const [DrawingAnchor(10, 100), DrawingAnchor(20, 110)]));
      editor.add(HorizontalLineDrawing(id: 'b', anchors: const [DrawingAnchor(30, 105)]));
      editor.remove('a');
      expect(editor.drawings.map((d) => d.id), ['b']);

      editor.undo();
      expect(editor.drawings.map((d) => d.id), ['a', 'b']);
      editor.undo();
      expect(editor.drawings.map((d) => d.id), ['a']);
      expect(editor.canRedo, isTrue);
      editor.redo();
      expect(editor.drawings.map((d) => d.id), ['a', 'b']);

      editor.clear();
      expect(editor.drawings, isEmpty);
      editor.undo();
      expect(editor.drawings.length, 2);
      expect(changes, greaterThan(0));
    });

    testWidgets('a checkpoint lets a style change be undone', (tester) async {
      final (_, editor) = await _pump(tester);
      final line = TrendLineDrawing(id: 'a', anchors: const [DrawingAnchor(10, 100), DrawingAnchor(20, 110)]);
      editor.add(line);
      editor.checkpoint();
      line.style = const DrawingStyle(color: Color(0xFFFF0000));
      editor.undo();
      expect(line.style.color, const DrawingStyle().color);
    });

    testWidgets('dragging a drawing can be undone', (tester) async {
      final (chart, editor) = await _pump(tester);
      final line = TrendLineDrawing(id: 'a', anchors: const [DrawingAnchor(120, 110), DrawingAnchor(180, 112)]);
      editor.add(line);
      await tester.pump();
      final before = List.of(line.anchors);
      final pane = chart.panes().first;
      Offset at(DrawingAnchor a) =>
          Offset(chart.timeScale().logicalToCoordinate(a.logical), pane.priceToCoordinate(a.price)!);
      final mid = Offset.lerp(at(before[0]), at(before[1]), 0.5)!;
      final gesture = await tester.startGesture(mid, kind: PointerDeviceKind.mouse);
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(line.anchors, isNot(before));

      editor.undo();
      expect(line.anchors, before);
    });
  });

  group('DrawingCodec', () {
    testWidgets('round-trips the built-in drawings by time', (tester) async {
      final (chart, editor) = await _pump(tester);
      final codec = DrawingCodec();
      final drawings = <Drawing>[
        TrendLineDrawing(
          id: 't',
          anchors: const [DrawingAnchor(10, 100), DrawingAnchor(20.5, 110)],
          extendRight: true,
          style: const DrawingStyle(color: Color(0xFF00FF00), lineStyle: LineStyle.dashed),
        ),
        HorizontalLineDrawing(id: 'h', anchors: const [DrawingAnchor(30, 105)], ray: true, label: 'Stop'),
        ParallelChannelDrawing(
          id: 'c',
          anchors: const [DrawingAnchor(0, 100), DrawingAnchor(10, 110), DrawingAnchor(5, 115)],
          middleLine: false,
        ),
        TextDrawing(id: 'x', anchors: const [DrawingAnchor(40, 101)], text: 'Note'),
        FibRetracementDrawing(id: 'f', anchors: const [DrawingAnchor(50, 100), DrawingAnchor(60, 120)]),
        // Past the last bar: placed by extrapolating the bar step.
        RectangleDrawing(id: 'r', anchors: const [DrawingAnchor(195, 100), DrawingAnchor(210, 120)]),
      ];
      final ts = chart.timeScale();
      final json = codec.encodeAll(drawings, ts.logicalToTime);
      expect(json.length, drawings.length);
      expect(json.first['kind'], 'trendLine');

      final back = codec.decodeAll(json, ts.timeToLogical);
      expect(back.length, drawings.length);
      for (var i = 0; i < drawings.length; i++) {
        expect(back[i].runtimeType, drawings[i].runtimeType);
        expect(back[i].id, drawings[i].id);
        for (var j = 0; j < drawings[i].anchors.length; j++) {
          expect(back[i].anchors[j].logical, closeTo(drawings[i].anchors[j].logical, 1e-9));
          expect(back[i].anchors[j].price, drawings[i].anchors[j].price);
        }
      }
      final t = back[0] as TrendLineDrawing;
      expect(t.extendRight, isTrue);
      expect(t.style.color, const Color(0xFF00FF00));
      expect(t.style.lineStyle, LineStyle.dashed);
      expect((back[1] as HorizontalLineDrawing).label, 'Stop');
      expect((back[2] as ParallelChannelDrawing).middleLine, isFalse);
      expect((back[3] as TextDrawing).text, 'Note');
      expect(editor.drawings, isEmpty);
    });

    test('custom kinds round-trip; unknown ones are skipped', () {
      final codec = DrawingCodec(
        custom: [
          DrawingKind<_Marker>(
            name: 'marker',
            create: (id, a, s, p) => _Marker(id, a, p['label'] as String),
            props: (d) => {'label': d.label},
          ),
        ],
      );
      num? timeOf(double l) => l * 10;
      double? logicalOf(num t) => t / 10;
      final json = codec.encode(_Marker('m', const [DrawingAnchor(3, 50)], 'Hi'), timeOf)!;
      expect(json['kind'], 'marker');
      final back = codec.decode(json, logicalOf) as _Marker;
      expect(back.label, 'Hi');
      expect(back.anchors.single, const DrawingAnchor(3, 50));
      expect(DrawingCodec().encode(_Marker('m', const [DrawingAnchor(3, 50)], 'Hi'), timeOf), isNull);
      expect(codec.decode({'kind': 'nope'}, logicalOf), isNull);
    });
  });

  testWidgets('CrosshairSync moves the other chart to the same time', (tester) async {
    final a = ChartController(), b = ChartController();
    final sa = a.addCandlestickSeries()..setData(_bars(100));
    final sb = b.addCandlestickSeries()..setData(_bars(100, 300));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(width: 400, height: 200, child: SwmChart(controller: a)),
              SizedBox(width: 400, height: 200, child: SwmChart(controller: b)),
            ],
          ),
        ),
      ),
    );
    final sync = CrosshairSync([(a, sa), (b, sb)]);
    addTearDown(() {
      sync.dispose();
      a.dispose();
      b.dispose();
    });
    ChartEventParams? onB;
    b.subscribeCrosshairMove((p) => onB = p);

    a.setCrosshairPosition(110, _t0 + 50 * _day, sa);
    await tester.pump();
    expect(onB?.time, _t0 + 50 * _day);

    a.clearCrosshairPosition();
    await tester.pump();
    expect(onB?.time, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CrosshairSync across intervals lands on the bar holding the time', (tester) async {
    const hour = 3600;
    final hourly = [
      for (var i = 0; i < 96; i++)
        CandlestickData(time: _t0 + i * hour, open: 100, high: 101, low: 99, close: 100.0 + i),
    ];
    final a = ChartController(), b = ChartController();
    final sa = a.addCandlestickSeries()..setData(hourly);
    final sb = b.addCandlestickSeries()..setData(resample(hourly, const Timeframe.hours(4)));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(width: 400, height: 200, child: SwmChart(controller: a)),
              SizedBox(width: 400, height: 200, child: SwmChart(controller: b)),
            ],
          ),
        ),
      ),
    );
    final sync = CrosshairSync([(a, sa), (b, sb)]);
    addTearDown(() {
      sync.dispose();
      a.dispose();
      b.dispose();
    });
    ChartEventParams? onB;
    b.subscribeCrosshairMove((p) => onB = p);

    // 02:00 and 03:00 are inside the 00:00 4h bar (bars near the end are on
    // screen).
    for (final h in [80 + 2, 80 + 3, 80]) {
      a.setCrosshairPosition(100.0 + h, _t0 + h * hour, sa);
      await tester.pump();
      expect(onB?.time, _t0 + 80 * hour, reason: 'hour $h');
    }
  });
}

class _Marker extends Drawing {
  _Marker(Object id, List<DrawingAnchor> anchors, this.label) : super(id: id, anchors: anchors);

  final String label;

  @override
  int get anchorCount => 1;

  @override
  void paint(Canvas canvas, DrawingContext c) {}

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) => null;
}
