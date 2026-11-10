import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/swm_chart.dart';

const _day = 86400;
const _t0 = 1704067200;

List<CandlestickData> _bars(int count) => List.generate(count, (i) {
  final o = 100.0 + (i % 20);
  return CandlestickData(time: _t0 + i * _day, open: o, high: o + 3, low: o - 3, close: i.isEven ? o + 1 : o - 1);
});

void main() {
  testWidgets('every extra drawing paints, hits and round-trips through the codec', (tester) async {
    final chart = ChartController();
    final candles = chart.addCandlestickSeries()..setData(_bars(200));
    final volume = chart.addHistogramSeries()
      ..setData([for (var i = 0; i < 200; i++) HistogramData(time: _t0 + i * _day, value: 100.0 + i)]);
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

    const flag = IconData(0xe153, fontFamily: 'MaterialIcons');
    final drawings = <Drawing>[
      TrendAngleDrawing(id: 'angle', anchors: const [DrawingAnchor(150, 100), DrawingAnchor(160, 110)]),
      InfoLineDrawing(id: 'info', anchors: const [DrawingAnchor(150, 100), DrawingAnchor(170, 105)], barsLabel: 'nến'),
      RangeVolumeProfileDrawing(
        id: 'vp',
        anchors: const [DrawingAnchor(140, 0), DrawingAnchor(180, 0)],
        source: candles,
        volume: volume,
      ),
      RangeVolumeProfileDrawing(
        id: 'avp',
        anchors: const [DrawingAnchor(170, 0)],
        source: candles,
        volume: volume,
        anchored: true,
      ),
      HarmonicDrawing(
        id: 'xabcd',
        anchors: const [
          DrawingAnchor(150, 100),
          DrawingAnchor(155, 110),
          DrawingAnchor(160, 104),
          DrawingAnchor(165, 112),
          DrawingAnchor(170, 102),
        ],
        style: const DrawingStyle(fillColor: Color(0x2226A69A)),
      ),
      HeadAndShouldersDrawing(
        id: 'hs',
        anchors: [for (var i = 0; i < 7; i++) DrawingAnchor(150.0 + i * 4, i.isEven ? 100 : 108 + (i == 3 ? 4 : 0))],
      ),
      SineLineDrawing(id: 'sine', anchors: const [DrawingAnchor(150, 110), DrawingAnchor(155, 100)]),
      CyclicLinesDrawing(id: 'cyc', anchors: const [DrawingAnchor(150, 100), DrawingAnchor(156, 100)]),
      TimeCyclesDrawing(id: 'tc', anchors: const [DrawingAnchor(150, 100), DrawingAnchor(158, 100)]),
      FibFanDrawing(id: 'ffan', anchors: const [DrawingAnchor(150, 100), DrawingAnchor(160, 115)]),
      FibArcDrawing(id: 'farc', anchors: const [DrawingAnchor(150, 100), DrawingAnchor(160, 115)]),
      IconMarkDrawing(
        id: 'flag',
        anchors: const [DrawingAnchor(160, 112)],
        icon: flag,
        iconKey: 'flag',
        anchorAtBase: true,
      ),
      PriceLabelDrawing(id: 'price', anchors: const [DrawingAnchor(165, 108)]),
    ];
    for (final d in drawings) {
      editor.add(d);
      editor.select(d.id);
      await tester.pump();
    }
    expect(tester.takeException(), isNull);

    final codec = DrawingCodec(source: candles, volume: volume, icons: const {'flag': flag});
    final json = codec.encodeAll(editor.drawings, chart.timeScale().logicalToTime);
    expect(json.map((j) => j['kind']), [
      'trendAngle',
      'infoLine',
      'rangeVolumeProfile',
      'rangeVolumeProfile',
      'harmonic',
      'headAndShoulders',
      'sineLine',
      'cyclicLines',
      'timeCycles',
      'fibFan',
      'fibArc',
      'iconMark',
      'priceLabel',
    ]);
    final back = codec.decodeAll(json, chart.timeScale().timeToLogical);
    expect(back, hasLength(drawings.length));
    for (final (i, d) in back.indexed) {
      expect(d.runtimeType, drawings[i].runtimeType);
      expect(d.anchors, drawings[i].anchors);
    }
    expect((back[1] as InfoLineDrawing).barsLabel, 'nến');
    expect((back[3] as RangeVolumeProfileDrawing).anchored, isTrue);
    expect((back[3] as RangeVolumeProfileDrawing).volume, volume);
    expect((back[11] as IconMarkDrawing).icon, flag);
    expect((back[11] as IconMarkDrawing).anchorAtBase, isTrue);

    // An icon key the codec doesn't know loads as the fallback flag.
    final unknown = DrawingCodec().decodeAll(json, chart.timeScale().timeToLogical);
    expect((unknown[11] as IconMarkDrawing).icon, IconMarkDrawing.fallbackIcon);
  });

  test('the toolbar has every tool once, each making its drawing', () {
    final pro = ProChartController()..setData(_bars(50), volumes: [for (var i = 0; i < 50; i++) 100.0]);
    addTearDown(pro.dispose);
    final tools = [for (final g in DrawingTools.groups) ...g.tools];
    expect(DrawingTools.groups.map((g) => g.label), [
      'Lines',
      'Channels and pitchforks',
      'Fibonacci and Gann',
      'Patterns',
      'Forecasting and measuring',
      'Shapes',
      'Annotations',
    ]);
    expect(tools, hasLength(51));
    expect(tools.map((t) => t.id).toSet(), hasLength(tools.length));
    for (final t in tools) {
      expect(t.create(pro, t.id, const [DrawingAnchor(10, 100)]), isA<Drawing>(), reason: t.id);
    }
  });

  testWidgets('floating toolbar: the pencil shows and puts away the tools', (tester) async {
    tester.view.physicalSize = const Size(420, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final pro = ProChartController()..setData(_bars(100));
    addTearDown(pro.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwmProChart(controller: pro, toolbarMode: DrawingToolbarMode.floating),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(DrawingToolbar), findsNothing);
    // The chart keeps the full width.
    expect(tester.getRect(find.byType(SwmChart)).width, 420);

    await tester.tap(find.byTooltip('Drawing tools'));
    await tester.pump();
    expect(find.byType(DrawingToolbar), findsOneWidget);
    await tester.tap(find.byTooltip('Lines'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trend line'));
    await tester.pumpAndSettle();
    expect(pro.activeTool?.id, 'trendLine');

    // Closing puts the tool down.
    await tester.tap(find.byTooltip('Drawing tools'));
    await tester.pump();
    expect(find.byType(DrawingToolbar), findsNothing);
    expect(pro.activeTool, isNull);
  });

  group('labels', () {
    tearDown(() => DrawingLabels.current = const DrawingLabels());

    test('durations use the current units', () {
      expect(formatDuration(3 * 86400 + 4 * 3600), '3d 4h');
      DrawingLabels.current = const DrawingLabels(days: ' ngày', hours: ' giờ');
      expect(formatDuration(3 * 86400 + 4 * 3600), '3 ngày 4 giờ');
    });

    testWidgets('bar counts follow the current word unless a drawing has its own', (tester) async {
      final chart = ChartController();
      final candles = chart.addCandlestickSeries()..setData(_bars(50));
      addTearDown(chart.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(width: 400, height: 300, child: SwmChart(controller: chart)),
        ),
      );
      final codec = DrawingCodec(source: candles);
      final range = DateRangeDrawing(id: 'r', anchors: const [DrawingAnchor(10, 100), DrawingAnchor(20, 100)]);
      final json = codec.encode(range, chart.timeScale().logicalToTime)!;
      expect((json['props']! as Map).containsKey('barsLabel'), isFalse);

      // A drawing saved by 0.15.0, with the default word: it follows the
      // current one once loaded.
      final old = {
        ...json,
        'props': {'barsLabel': 'bars'},
      };
      final back = codec.decode(old, chart.timeScale().timeToLogical)! as DateRangeDrawing;
      expect(back.barsLabel, isNull);
      final own =
          codec.decode({
                ...json,
                'props': {'barsLabel': 'nến'},
              }, chart.timeScale().timeToLogical)!
              as DateRangeDrawing;
      expect(own.barsLabel, 'nến');
    });
  });
}
