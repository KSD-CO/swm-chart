import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/src/model/chart_model.dart';
import 'package:swm_chart/src/model/price_scale.dart' as ps;
import 'package:swm_chart/swm_chart.dart';

const _day = 86400;
const _t0 = 1704067200; // 2024-01-01T00:00:00Z

List<CandlestickData> _bars(int count, {double base = 100}) => List.generate(count, (i) {
      final o = base + i;
      return CandlestickData(time: _t0 + i * _day, open: o, high: o + 2, low: o - 2, close: o + 1);
    });

List<LineData> _line(int count, double Function(int) f) =>
    [for (var i = 0; i < count; i++) LineData(time: _t0 + i * _day, value: f(i))];

double _measure(String s) => s.length * 7.0;

class _RecordingPrimitive extends ChartPrimitive {
  int paints = 0;

  @override
  void paint(PrimitivePaintContext ctx) => paints++;

  @override
  List<AxisLabel> priceAxisLabels(PrimitiveContext ctx) =>
      [AxisLabel(coordinate: 10, text: 'P', backgroundColor: const Color(0xFF000000))];

  @override
  List<AxisLabel> timeAxisLabels(PrimitiveContext ctx) =>
      [AxisLabel(coordinate: 10, text: 'T', backgroundColor: const Color(0xFF000000))];
}

void main() {
  late ChartController chart;

  setUp(() => chart = ChartController());
  tearDown(() => chart.dispose());

  void layout([Size size = const Size(400, 600)]) => chart.model.layout(size, 2, _measure);

  group('panes', () {
    test('series on a new pane splits the height by stretch factors', () {
      chart.addCandlestickSeries().setData(_bars(50));
      chart.addHistogramSeries(const HistogramSeriesOptions(), 1).setData([
        for (var i = 0; i < 50; i++) HistogramData(time: _t0 + i * _day, value: i.toDouble()),
      ]);
      layout();
      final panes = chart.panes();
      expect(panes, hasLength(2));
      final available = 600 - chart.timeScale().height() - 1; // one separator
      expect(panes[0].getHeight() + panes[1].getHeight(), closeTo(available, 1e-9));
      expect(panes[0].getHeight(), closeTo(available / 2, 0.5));

      panes[0].setStretchFactor(3);
      layout();
      expect(panes[0].getHeight(), closeTo(available * 0.75, 0.5));

      panes[1].setHeight(100);
      layout();
      expect(panes[1].getHeight(), closeTo(100, 0.5));
    });

    test('empty panes are removed unless preserved', () {
      final s = chart.addLineSeries(const LineSeriesOptions(), 1)..setData(_line(10, (i) => i.toDouble()));
      expect(chart.panes(), hasLength(2));
      chart.removeSeries(s);
      expect(chart.panes(), hasLength(1));

      final kept = chart.addPane(preserveEmptyPane: true);
      final s2 = chart.addLineSeries(const LineSeriesOptions(), kept.paneIndex());
      chart.removeSeries(s2);
      expect(chart.panes(), hasLength(2));
    });

    test('moveToPane and swapPanes', () {
      final a = chart.addLineSeries()..setData(_line(10, (i) => i.toDouble()));
      final b = chart.addLineSeries()..setData(_line(10, (i) => -i.toDouble()));
      b.moveToPane(1);
      expect(b.getPane().paneIndex(), 1);
      chart.swapPanes(0, 1);
      expect(b.getPane().paneIndex(), 0);
      expect(a.getPane().paneIndex(), 1);
    });

    test('separator resize keeps the minimum pane height', () {
      chart.addLineSeries().setData(_line(10, (i) => i.toDouble()));
      chart.addLineSeries(const LineSeriesOptions(), 1).setData(_line(10, (i) => i.toDouble()));
      layout();
      final model = chart.model;
      model.startPaneResize(0);
      model.resizePane(0, -10000);
      model.endPaneResize();
      layout();
      expect(model.panes[0].height, closeTo(30, 0.5));
    });

    test('crosshair horizontal line belongs to one pane, events report it', () {
      chart.addLineSeries().setData(_line(10, (i) => i.toDouble()));
      chart.addLineSeries(const LineSeriesOptions(), 1).setData(_line(10, (i) => i.toDouble()));
      layout();
      ChartEventParams? event;
      chart.subscribeCrosshairMove((p) => event = p);
      chart.model.setCrosshairPosition(1, Offset(chart.timeScale().timeToCoordinate(_t0 + 5 * _day)!, 50));
      expect(chart.model.crosshair!.paneIndex, 1);
      expect(event!.paneIndex, 1);
      expect(event!.seriesData, hasLength(2));
    });
  });

  group('price scale modes', () {
    test('logarithmic: equal ratios are equally spaced', () {
      final s = chart.addLineSeries();
      s.setData(_line(3, (i) => [10.0, 100.0, 1000.0][i]));
      chart.priceScale().applyOptions(const PriceScaleOptions(mode: PriceScaleMode.logarithmic));
      layout();
      final y10 = s.priceToCoordinate(10)!, y100 = s.priceToCoordinate(100)!, y1000 = s.priceToCoordinate(1000)!;
      // Upstream's log formula adds a tiny coordOffset, so spacing is nearly equal.
      expect(y10 - y100, closeTo(y100 - y1000, 0.01));
      expect(s.coordinateToPrice(y100), closeTo(100, 1e-6));
      expect(chart.model.panes.first.rightScale.marks(), isNotEmpty);
    });

    test('percentage: first visible value is 0%', () {
      final s = chart.addLineSeries();
      s.setData(_line(20, (i) => 100.0 + i * 5));
      chart.priceScale().applyOptions(const PriceScaleOptions(mode: PriceScaleMode.percentage));
      chart.timeScale().fitContent();
      layout();
      final scale = chart.model.panes.first.rightScale;
      expect(s.formatPrice(100), '0.00%');
      expect(s.formatPrice(150), '50.00%');
      expect(scale.marks().every((m) => m.label.endsWith('%')), isTrue);
      expect(scale.coordinateToDisplay(s.priceToCoordinate(200)!), closeTo(100, 1e-6));
    });

    test('indexedTo100: first visible value is 100', () {
      final s = chart.addLineSeries();
      s.setData(_line(20, (i) => 50.0 + i));
      chart.priceScale().applyOptions(const PriceScaleOptions(mode: PriceScaleMode.indexedTo100));
      chart.timeScale().fitContent();
      layout();
      expect(s.formatPrice(50), '100.00');
      expect(s.formatPrice(75), '150.00');
    });

    test('log conversions round-trip', () {
      const f = ps.LogFormula(4, 0.0001);
      for (final v in [0.001, 1.0, 123.45, 1e6, -42.0]) {
        expect(ps.fromLog(ps.toLog(v, f), f), closeTo(v, v.abs() * 1e-9));
      }
    });
  });

  test('left price scale', () {
    chart.applyOptions(const ChartOptions(
      leftPriceScale: PriceScaleOptions(visible: true),
      rightPriceScale: PriceScaleOptions(visible: false),
    ));
    chart.addLineSeries(const LineSeriesOptions(priceScaleId: 'left')).setData(_line(10, (i) => i.toDouble()));
    layout();
    expect(chart.priceScale('left').width(), greaterThan(0));
    expect(chart.priceScale().width(), 0);
    expect(chart.model.panes.first.defaultPriceScale.id, 'left');
    expect(chart.model.priceAxisLabels(chart.model.panes.first, AxisSide.left), hasLength(1));
  });

  test('custom price lines get axis labels', () {
    final s = chart.addCandlestickSeries()..setData(_bars(20));
    final line = s.createPriceLine(const PriceLineOptions(price: 110, title: 'TP'));
    layout();
    final labels = chart.model.priceAxisLabels(chart.model.panes.first, AxisSide.right);
    expect(labels.map((l) => l.text), contains('110.00'));
    expect(labels.firstWhere((l) => l.text == '110.00').title, 'TP');
    line.applyOptions(line.options.copyWith(price: 111));
    expect(s.priceLines().single.options.price, 111);
    s.removePriceLine(s.priceLines().single);
    expect(s.priceLines(), isEmpty);
  });

  test('priceLineSource.lastVisible follows the last visible bar', () {
    final s = chart.addCandlestickSeries(const CandlestickSeriesOptions(priceLineSource: PriceLineSource.lastVisible));
    s.setData(_bars(300));
    layout();
    chart.timeScale().scrollToPosition(-100);
    layout();
    final visible = chart.model.timeScale.visibleStrictRange()!;
    final label = chart.model.priceAxisLabels(chart.model.panes.first, AxisSide.right).single;
    expect(label.text, s.data()[visible.right].close.toStringAsFixed(2));
  });

  test('autoscaleInfoProvider overrides the range', () {
    chart.addLineSeries(LineSeriesOptions(
      autoscaleInfoProvider: (_) => const AutoscaleInfo(priceRange: PriceRange(0, 1000)),
    )).setData(_line(10, (i) => i.toDouble()));
    layout();
    expect(chart.priceScale().getVisibleRange(), const PriceRange(0, 1000));
  });

  test('markers reserve autoscale margins', () {
    final s = chart.addCandlestickSeries()..setData(_bars(30));
    layout();
    final before = chart.model.panes.first.rightScale.internalHeight;
    createSeriesMarkers(s, [
      SeriesMarker(time: _t0, position: SeriesMarkerPosition.aboveBar, shape: SeriesMarkerShape.arrowDown, color: const Color(0xFFFF0000)),
    ]);
    layout();
    expect(chart.model.panes.first.rightScale.internalHeight, lessThan(before));
  });

  test('primitives contribute axis labels', () {
    final s = chart.addLineSeries()..setData(_line(10, (i) => i.toDouble()));
    final p = _RecordingPrimitive();
    s.attachPrimitive(p);
    layout();
    expect(chart.model.priceAxisLabels(chart.model.panes.first, AxisSide.right).map((l) => l.text), contains('P'));
    expect(chart.model.timeAxisPrimitiveLabels().single.text, 'T');
    s.detachPrimitive(p);
    expect(p.host, isNull);
  });

  test('barsInLogicalRange', () {
    final s = chart.addLineSeries()..setData(_line(100, (i) => i.toDouble()));
    final info = s.barsInLogicalRange(const LogicalRange(10, 89))!;
    expect(info.barsBefore, 10);
    expect(info.barsAfter, 10);
    expect(info.from, _t0 + 10 * _day);
    expect(info.to, _t0 + 89 * _day);
  });

  test('setCrosshairPosition places the crosshair exactly', () {
    final s = chart.addCandlestickSeries()..setData(_bars(30));
    layout();
    chart.setCrosshairPosition(105.5, _t0 + 5 * _day, s);
    final c = chart.model.crosshair!;
    expect(c.index, 5);
    expect(c.y, closeTo(s.priceToCoordinate(105.5)!, 1e-9));
  });

  test('area, bar and baseline series autoscale', () {
    chart.addAreaSeries().setData([for (var i = 0; i < 10; i++) AreaData(time: _t0 + i * _day, value: i.toDouble())]);
    chart.addBarSeries().setData([
      for (var i = 0; i < 10; i++) BarData(time: _t0 + i * _day, open: 5, high: 20, low: -3, close: 6),
    ]);
    chart.addBaselineSeries(const BaselineSeriesOptions(baseValue: 4))
        .setData([for (var i = 0; i < 10; i++) BaselineData(time: _t0 + i * _day, value: i.toDouble())]);
    layout();
    expect(chart.priceScale().getVisibleRange(), const PriceRange(-3, 20));
  });
}
