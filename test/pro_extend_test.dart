import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/swm_chart.dart';

const _hour = 3600;
const _t0 = 1704067200;

List<CandlestickData> _bars(int count) => List.generate(count, (i) {
  final o = 100.0 + (i % 30) - (i % 7);
  return CandlestickData(time: _t0 + i * _hour, open: o, high: o + 2, low: o - 2, close: i.isEven ? o + 1 : o - 1);
});

ProChartController _pro({List<DrawingKind> kinds = const []}) =>
    ProChartController(symbol: 'TEST', interval: '1h', drawingKinds: kinds)..setData(_bars(200));

/// An app's own drawing: a rectangle saved under its own kind, with a note.
class _Zone extends RectangleDrawing {
  _Zone({required super.id, required super.anchors, super.style, this.note = ''});

  String note;

  @override
  String get kind => 'zone';
}

final _zoneKind = DrawingKind<_Zone>(
  name: 'zone',
  create: (id, anchors, style, props) => _Zone(id: id, anchors: anchors, style: style, note: '${props['note'] ?? ''}'),
  props: (d) => {'note': d.note},
);

final _myTrend = IndicatorSpec(
  id: 'myTrend',
  title: 'My Trend',
  group: IndicatorGroup.custom,
  params: const [IndicatorParam('period', 'Length', 30)],
  create: (v) => Sma(v['period']!.round()),
);

Future<void> _pumpPro(WidgetTester tester, ProChartController pro, {ProChartStrings? strings}) async {
  await tester.binding.setSurfaceSize(const Size(900, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SwmProChart(controller: pro, strings: strings),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('your own indicators', () {
    tearDown(() => IndicatorCatalog.unregister('myTrend'));

    test('a registered indicator is found, added and saved like a built-in one', () {
      IndicatorCatalog.register(_myTrend);
      expect(IndicatorCatalog.byId('myTrend'), _myTrend);
      expect(IndicatorCatalog.search('my trend'), [_myTrend]);
      expect(IndicatorCatalog.all.map((s) => s.id), isNot(contains('myTrend')));

      final pro = _pro();
      addTearDown(pro.dispose);
      pro.addIndicator(_myTrend, values: {'period': 12});
      final saved = pro.saveState();

      final back = _pro();
      addTearDown(back.dispose);
      back.restoreState(saved);
      expect(back.indicators.single.spec.id, 'myTrend');
      expect(back.indicators.single.values, {'period': 12});
    });

    test('unregistered, it is gone', () {
      IndicatorCatalog.register(_myTrend);
      IndicatorCatalog.unregister('myTrend');
      expect(IndicatorCatalog.byId('myTrend'), isNull);
    });
  });

  test('your own drawings are saved and restored through drawingKinds', () {
    final pro = _pro(kinds: [_zoneKind]);
    addTearDown(pro.dispose);
    pro.drawings.add(_Zone(id: 'z', anchors: const [DrawingAnchor(10, 95), DrawingAnchor(40, 110)], note: 'buy zone'));
    final saved = pro.saveState();

    final back = _pro(kinds: [_zoneKind]);
    addTearDown(back.dispose);
    back.restoreState(saved);
    final zone = back.drawings.drawings.single;
    expect(zone, isA<_Zone>());
    expect((zone as _Zone).note, 'buy zone');
  });

  group('display settings', () {
    test('crosshair, grid and watermark apply, keep the scale and are saved', () {
      final pro = _pro();
      addTearDown(pro.dispose);
      pro.scaleMode = PriceScaleMode.logarithmic;
      pro
        ..crosshairStyle = LineStyle.solid
        ..crosshairColor = const Color(0xFFFFD600)
        ..crosshairWidth = 2
        ..showGrid = false
        ..showWatermark = true;
      final o = pro.chart.options;
      expect(o.crosshair.vertLine.style, LineStyle.solid);
      expect(o.crosshair.horzLine.color, const Color(0xFFFFD600));
      expect(o.crosshair.vertLine.width, 2);
      expect(o.grid.vertLines.visible, isFalse);
      expect(o.grid.horzLines.visible, isFalse);
      // Chart-wide options used to reset the price scale.
      expect(pro.scaleMode, PriceScaleMode.logarithmic);

      final back = _pro();
      addTearDown(back.dispose);
      back.restoreState(pro.saveState());
      expect(back.crosshairStyle, LineStyle.solid);
      expect(back.crosshairColor, const Color(0xFFFFD600));
      expect(back.crosshairWidth, 2);
      expect(back.showGrid, isFalse);
      expect(back.showWatermark, isTrue);

      back.resetDisplay();
      expect(back.showGrid, isTrue);
      expect(back.showWatermark, isFalse);
      expect(back.crosshairStyle, LineStyle.largeDashed);
    });

    testWidgets('the chart settings menu opens them', (tester) async {
      final pro = _pro();
      addTearDown(pro.dispose);
      await _pumpPro(tester, pro);
      await tester.tap(find.byTooltip('Chart settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chart display…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grid lines'));
      await tester.pumpAndSettle();
      expect(pro.showGrid, isFalse);
      await tester.tap(find.text('Solid'));
      await tester.pumpAndSettle();
      expect(pro.crosshairStyle, LineStyle.solid);
    });
  });

  group('your own words', () {
    const vi = ProChartStrings(
      indicators: 'Chỉ báo',
      undo: 'Hoàn tác',
      chartSettings: 'Cài đặt chart',
      searchIndicators: 'Tìm chỉ báo',
      chartDisplay: 'Hiển thị chart',
      gridLines: 'Lưới',
    );

    testWidgets('the screen and its sheets show them', (tester) async {
      final pro = _pro();
      addTearDown(pro.dispose);
      await _pumpPro(
        tester,
        pro,
        strings: ProChartStrings(
          indicators: vi.indicators,
          undo: vi.undo,
          chartSettings: vi.chartSettings,
          searchIndicators: vi.searchIndicators,
          chartDisplay: vi.chartDisplay,
          gridLines: vi.gridLines,
          indicatorTitle: (spec) => spec.id == 'rsi' ? 'Chỉ số sức mạnh' : spec.title,
          groupName: (g) => g == IndicatorGroup.movingAverages ? 'Đường trung bình' : g.label,
        ),
      );
      expect(find.text('Chỉ báo'), findsOneWidget);
      expect(find.byTooltip('Hoàn tác'), findsOneWidget);

      // The indicator sheet, opened from the bar, keeps them.
      await tester.tap(find.text('Chỉ báo'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Tìm chỉ báo'), findsOneWidget);
      expect(find.text('Đường trung bình'), findsOneWidget);
      // A translated name is found by search.
      await tester.enterText(find.byType(TextField), 'sức mạnh');
      await tester.pumpAndSettle();
      expect(find.text('Chỉ số sức mạnh'), findsOneWidget);
      Navigator.of(tester.element(find.text('Chỉ số sức mạnh'))).pop();
      await tester.pumpAndSettle();

      // So does the display sheet.
      await tester.tap(find.byTooltip('Cài đặt chart'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hiển thị chart…'));
      await tester.pumpAndSettle();
      expect(find.text('Lưới'), findsOneWidget);
    });

    testWidgets('without them, English', (tester) async {
      final pro = _pro();
      addTearDown(pro.dispose);
      await _pumpPro(tester, pro);
      expect(find.text('Indicators'), findsOneWidget);
      expect(find.byTooltip('Undo'), findsOneWidget);
    });
  });
}
