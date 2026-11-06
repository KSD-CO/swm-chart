import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/swm_chart.dart';

const _hour = 3600;
const _t0 = 1704067200;

List<CandlestickData> _bars(int count) => List.generate(count, (i) {
  final o = 100.0 + (i % 30) - (i % 7);
  return CandlestickData(time: _t0 + i * _hour, open: o, high: o + 2, low: o - 2, close: i.isEven ? o + 1 : o - 1);
});

Future<ProChartController> _pump(WidgetTester tester, {void Function(String)? onInterval}) async {
  tester.view.physicalSize = const Size(420, 860);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final pro = ProChartController(symbol: 'BTC/USD', interval: '1h')
    ..setData(_bars(150), volumes: [for (var i = 0; i < 150; i++) 100.0 + i]);
  addTearDown(pro.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SwmProChart(controller: pro, onIntervalChanged: onInterval),
      ),
    ),
  );
  await tester.pump();
  return pro;
}

Rect _chartRect(WidgetTester tester) => tester.getRect(find.byType(SwmChart));

void main() {
  testWidgets('pick an indicator, then change its inputs', (tester) async {
    final pro = await _pump(tester);
    await tester.tap(find.byTooltip('Indicators'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'strength');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Relative Strength Index'));
    await tester.pumpAndSettle();
    expect(pro.indicators.single.name, 'RSI 14');

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('On the chart'), findsOneWidget);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Length'), '21');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(pro.indicators.single.name, 'RSI 21');

    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    expect(pro.indicators, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('interval and chart type from the top bar', (tester) async {
    String? picked;
    final pro = await _pump(tester, onInterval: (i) => picked = i);
    await tester.tap(find.text('1h'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4h').last);
    await tester.pumpAndSettle();
    expect(picked, '4h');
    expect(pro.interval, '4h');

    await tester.tap(find.byTooltip('Chart type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Heikin-Ashi'));
    await tester.pumpAndSettle();
    expect(pro.type, ProChartType.heikinAshi);

    await tester.tap(find.byTooltip('Chart settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<String>, 'Log scale'));
    await tester.pumpAndSettle();
    expect(pro.scaleMode, PriceScaleMode.logarithmic);
  });

  testWidgets('draw from the toolbar, restyle, delete and undo', (tester) async {
    final pro = await _pump(tester);
    await tester.tap(find.byTooltip('Lines'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trend line'));
    await tester.pumpAndSettle();
    expect(pro.activeTool?.id, 'trendLine');

    final rect = _chartRect(tester);
    await tester.tapAt(rect.center.translate(-80, 40));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(rect.center.translate(0, -40));
    await tester.pump(const Duration(milliseconds: 400));
    final line = pro.drawings.drawings.single;
    expect(line, isA<TrendLineDrawing>());
    expect(pro.activeTool, isNull);
    expect(find.byType(DrawingStyleBar), findsOneWidget);

    await tester.tap(find.byTooltip('Color'));
    await tester.pumpAndSettle();
    // The palette's red.
    final red = find.byWidgetPredicate(
      (w) => w is Container && (w.decoration as BoxDecoration?)?.color == const Color(0xFFF23645),
    );
    await tester.tap(red.last);
    await tester.pumpAndSettle();
    expect(line.style.color, const Color(0xFFF23645));

    await tester.tap(find.byTooltip('Lock'));
    await tester.pump();
    expect(line.locked, isTrue);

    await tester.tap(find.byTooltip('Duplicate'));
    await tester.pump();
    expect(pro.drawings.drawings, hasLength(2));

    await tester.tap(find.byTooltip('Delete'));
    await tester.pump();
    expect(pro.drawings.drawings, hasLength(1));

    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(pro.drawings.drawings, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new text asks for its text', (tester) async {
    final pro = await _pump(tester);
    await tester.tap(find.byTooltip('Annotations'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Callout'));
    await tester.pumpAndSettle();
    final rect = _chartRect(tester);
    await tester.tapAt(rect.center.translate(-40, 40));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(rect.center.translate(20, -40));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Breakout');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect((pro.drawings.drawings.single as CalloutDrawing).text, 'Breakout');
  });

  testWidgets('magnet snaps anchors to the bar prices', (tester) async {
    final pro = await _pump(tester);
    await tester.tap(find.byTooltip('Magnet'));
    await tester.pump();
    expect(pro.magnet, isTrue);
    pro.activeTool = DrawingTools.byId('horizontalLine');
    await tester.tapAt(_chartRect(tester).center);
    await tester.pump(const Duration(milliseconds: 400));
    final a = pro.drawings.drawings.single.anchors.single;
    final bar = pro.bars[a.logical.round()];
    expect([bar.open, bar.high, bar.low, bar.close], contains(a.price));
  });
}
