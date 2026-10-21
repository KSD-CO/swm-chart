import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/src/model/time_scale.dart' show IndexRange;
import 'package:swm_chart/src/widget/attribution_logo.dart';
import 'package:swm_chart/swm_chart.dart';

const _day = 86400;
const _t0 = 1704067200; // 2024-01-01T00:00:00Z

List<LineData> _line(int count, [int start = 0]) =>
    [for (var i = start; i < start + count; i++) LineData(time: _t0 + i * _day, value: i.toDouble())];

double _measure(String s) => s.length * 7.0;

void main() {
  group('whitespace', () {
    test('whitespace extends the time scale without data', () {
      final chart = ChartController();
      final s = chart.addLineSeries();
      s.setData([..._line(10), for (var i = 10; i < 15; i++) WhitespaceData(time: _t0 + i * _day)]);
      expect(chart.model.timeScale.pointsCount, 15);
      expect(s.dataByIndex(12), isNull);
      expect(s.data(), hasLength(15));
      // Base index is the last bar with data, not the whitespace after it.
      expect(chart.model.timeScale.baseIndex, 9);
      chart.dispose();
    });

    test('update can turn whitespace into data and back', () {
      final chart = ChartController();
      final s = chart.addLineSeries()..setData([..._line(3), WhitespaceData(time: _t0 + 3 * _day)]);
      s.update(LineData(time: _t0 + 3 * _day, value: 42));
      expect(s.dataByIndex(3)!.value, 42);
      s.update(WhitespaceData(time: _t0 + 3 * _day));
      expect(s.dataByIndex(3), isNull);
      s.update(WhitespaceData(time: _t0 + 4 * _day));
      expect(chart.model.timeScale.pointsCount, 5);
      chart.dispose();
    });

    test('rejects items of the wrong type', () {
      final chart = ChartController();
      final s = chart.addLineSeries();
      expect(() => s.setData([const HistogramData(time: 1, value: 1)]), throwsArgumentError);
      chart.dispose();
    });

    test('ignoreWhitespaceIndices snaps the crosshair to data', () {
      final chart = ChartController(
        options: const ChartOptions(timeScale: TimeScaleOptions(ignoreWhitespaceIndices: true, barSpacing: 20)),
      );
      chart.addLineSeries().setData([
        LineData(time: _t0, value: 1),
        for (var i = 1; i < 5; i++) WhitespaceData(time: _t0 + i * _day),
        LineData(time: _t0 + 5 * _day, value: 2),
      ]);
      chart.model.layout(const Size(400, 300), 1, _measure);
      chart.timeScale().fitContent();
      chart.model.layout(const Size(400, 300), 1, _measure);
      final x = chart.timeScale().logicalToCoordinate(1);
      chart.model.setCrosshairPosition(0, Offset(x, 10));
      expect(chart.model.crosshair!.index, 0);
      chart.dispose();
    });
  });

  group('horizontal scale behaviors', () {
    test('yield curve: months axis, linear whitespace, line/area only', () {
      final chart = ChartController.yieldCurve();
      final s = chart.addLineSeries();
      s.setData([
        const LineData(time: 1, value: 5.2),
        const LineData(time: 12, value: 4.8),
        const LineData(time: 360, value: 4.4),
      ]);
      // Whitespace every month from 0 to 360.
      expect(chart.model.timeScale.pointsCount, 361);
      expect(chart.model.formatTime(30), '2Y6M');
      expect(chart.model.formatTime(6), '6M');
      expect(() => chart.addCandlestickSeries(), throwsUnsupportedError);
      expect(chart.options.leftPriceScale.visible, isTrue);
      chart.dispose();
    });

    test('options chart: price axis', () {
      final chart = ChartController.options(precision: 1);
      chart.addLineSeries().setData([
        for (var strike = 90; strike <= 110; strike += 5) LineData(time: strike, value: (strike - 100).abs() / 10),
      ]);
      expect(chart.model.formatTime(95), '95.0');
      final weights = chart.model.timeScale.weights;
      expect(weights[2], 8); // 100 is a multiple of 100
      chart.dispose();
    });
  });

  group('time scale options', () {
    test('rightOffsetPixels keeps a pixel margin while zooming', () {
      final chart = ChartController(options: const ChartOptions(timeScale: TimeScaleOptions(rightOffsetPixels: 60)));
      chart.addLineSeries().setData(_line(200));
      chart.model.layout(const Size(400, 300), 1, _measure);
      final ts = chart.model.timeScale;
      expect(ts.rightOffset * ts.barSpacing, closeTo(60, 1e-6));
      ts.setBarSpacing(12);
      expect(ts.rightOffset * ts.barSpacing, closeTo(60, 1e-6));
      chart.dispose();
    });

    test('lockVisibleTimeRangeOnResize keeps the range', () {
      final chart = ChartController(
        options: const ChartOptions(timeScale: TimeScaleOptions(lockVisibleTimeRangeOnResize: true)),
      );
      chart.addLineSeries().setData(_line(200));
      chart.model.layout(const Size(400, 300), 1, _measure);
      final before = chart.timeScale().getVisibleLogicalRange()!;
      chart.model.layout(const Size(800, 300), 1, _measure);
      final after = chart.timeScale().getVisibleLogicalRange()!;
      expect(after.to - after.from, closeTo(before.to - before.from, 0.5));
      chart.dispose();
    });

    test('minimumHeight of the time axis', () {
      final chart = ChartController(options: const ChartOptions(timeScale: TimeScaleOptions(minimumHeight: 50)));
      chart.addLineSeries().setData(_line(10));
      chart.model.layout(const Size(400, 300), 1, _measure);
      expect(chart.timeScale().height(), 50);
      chart.dispose();
    });
  });

  group('price scale options', () {
    test('ensureEdgeTickMarksVisible labels both edges', () {
      final chart = ChartController(
        // Edge marks only apply when the margins are smaller than a tick step.
        options: const ChartOptions(
          rightPriceScale: PriceScaleOptions(ensureEdgeTickMarksVisible: true, scaleMargins: ScaleMargins(top: 0, bottom: 0)),
        ),
      );
      chart.addLineSeries().setData(_line(50));
      chart.model.layout(const Size(400, 300), 1, _measure);
      final marks = chart.model.panes.first.rightScale.marks();
      final height = chart.model.panes.first.height;
      expect(marks.first.coord, lessThan(12));
      expect(marks.last.coord, greaterThan(height - 12));
      chart.dispose();
    });

    test('overlayPriceScales provides overlay defaults', () {
      final chart = ChartController(
        options: const ChartOptions(
          overlayPriceScales: PriceScaleOptions(scaleMargins: ScaleMargins(top: 0.7, bottom: 0)),
        ),
      );
      chart.addHistogramSeries(const HistogramSeriesOptions(priceScaleId: 'vol'));
      expect(chart.priceScale('vol').options.scaleMargins.top, 0.7);
      chart.dispose();
    });

    test('tickmarks and percentage formatters', () {
      final chart = ChartController(
        options: ChartOptions(
          localization: LocalizationOptions(
            tickmarksPriceFormatter: (prices) => [for (final p in prices) 'P${p.toInt()}'],
            percentageFormatter: (v) => '${v.round()} pct',
          ),
        ),
      );
      // Values start at 1: a 0 base value makes percentages infinite.
      final s = chart.addLineSeries()..setData(_line(50, 1));
      chart.model.layout(const Size(400, 300), 1, _measure);
      expect(chart.model.panes.first.rightScale.marks().first.label, startsWith('P'));
      chart.priceScale().applyOptions(const PriceScaleOptions(mode: PriceScaleMode.percentage));
      chart.model.layout(const Size(400, 300), 1, _measure);
      expect(s.formatPrice(s.data().cast<LineData>()[10].value * 2), endsWith('pct'));
      chart.dispose();
    });
  });

  group('localization', () {
    test('dateFormat and month names', () {
      final chart = ChartController(
        options: const ChartOptions(
          localization: LocalizationOptions(
            dateFormat: 'dd/MM/yyyy MMMM',
            longMonthNames: ['Tháng 1', 'Tháng 2', 'Tháng 3', 'Tháng 4', 'Tháng 5', 'Tháng 6', 'Tháng 7', 'Tháng 8',
              'Tháng 9', 'Tháng 10', 'Tháng 11', 'Tháng 12'],
          ),
        ),
      );
      expect(chart.model.formatTime(_t0 + 40 * _day), '10/02/2024 Tháng 2');
      chart.dispose();
    });

    test('tickMarkFormatter receives the locale', () {
      String? seenLocale;
      final chart = ChartController(
        options: ChartOptions(
          localization: const LocalizationOptions(locale: 'vi-VN'),
          timeScale: TimeScaleOptions(tickMarkFormatter: (time, type, locale) {
            seenLocale = locale;
            return null;
          }),
        ),
      );
      chart.addLineSeries().setData(_line(100));
      chart.model.layout(const Size(400, 300), 1, _measure);
      chart.model.timeScale.marks(12, chart.model.formatTickMark);
      expect(seenLocale, 'vi-VN');
      chart.dispose();
    });
  });

  group('series api', () {
    test('dataByIndex mismatch directions', () {
      final chart = ChartController();
      final a = chart.addLineSeries()..setData([LineData(time: _t0, value: 1), LineData(time: _t0 + 4 * _day, value: 2)]);
      chart.addLineSeries().setData(_line(5));
      expect(a.dataByIndex(2), isNull);
      expect(a.dataByIndex(2, MismatchDirection.nearestLeft)!.value, 1);
      expect(a.dataByIndex(2, MismatchDirection.nearestRight)!.value, 2);
      chart.dispose();
    });

    test('seriesOrder, seriesType, lastValueData, subscribeDataChanged', () {
      final chart = ChartController();
      final a = chart.addLineSeries();
      final b = chart.addAreaSeries();
      expect(b.seriesOrder(), 1);
      b.setSeriesOrder(0);
      expect(a.seriesOrder(), 1);
      expect(b.seriesType(), SeriesType.area);
      var changes = 0;
      a.subscribeDataChanged(() => changes++);
      a.setData(_line(3));
      a.update(LineData(time: _t0 + 3 * _day, value: 9));
      expect(changes, 2);
      expect(a.lastValueData()!.price, 9);
      chart.dispose();
    });
  });

  hitTestGroup();
  extraGroups();
  apiGroup();
  chartOptionsGroup();
  perfStructuresGroup();
  transformGroup();
  hoveredInfoGroup();

  test('attribution logo path parses and is placed at the bottom left', () {
    final path = parseSvgPath('M0 0h10v10H0Z');
    expect(path.getBounds(), const Rect.fromLTWH(0, 0, 10, 10));
    final rect = attributionLogoRect(const Rect.fromLTWH(50, 0, 300, 200));
    expect(rect.left, 60);
    expect(rect.bottom, 190);
  });
}

void hitTestGroup() {
  group('hit testing', () {
    late ChartController chart;
    setUp(() => chart = ChartController());
    tearDown(() => chart.dispose());

    void layout() => chart.model.layout(const Size(400, 300), 1, _measure);

    test('candles: range hit, outside misses', () {
      final s = chart.addCandlestickSeries()
        ..setData([
          for (var i = 0; i < 30; i++)
            CandlestickData(time: _t0 + i * _day, open: 100.0 + i, high: 105.0 + i, low: 95.0 + i, close: 102.0 + i),
        ]);
      layout();
      final t = _t0 + 20 * _day;
      final x = chart.timeScale().timeToCoordinate(t)!;
      final hit = chart.model.hitTest(0, Offset(x, s.priceToCoordinate(120)!));
      expect(hit!.series, isNotNull);
      expect(hit.priority.name, 'range');
      expect(chart.model.hitTest(0, Offset(x, s.priceToCoordinate(150)!)), isNull);
    });

    test('lines: near the line hits, price lines report their id', () {
      final s = chart.addLineSeries()..setData(_line(30, 1));
      s.createPriceLine(const PriceLineOptions(price: 5, id: 'stop'));
      layout();
      final x = chart.timeScale().timeToCoordinate(_t0 + 10 * _day)!;
      final onLine = chart.model.hitTest(0, Offset(x, s.priceToCoordinate(10)! + 2));
      expect(onLine!.priority.name, 'line');
      final xFar = chart.timeScale().timeToCoordinate(_t0 + 25 * _day)!;
      final onPriceLine = chart.model.hitTest(0, Offset(xFar, s.priceToCoordinate(5)!));
      expect(onPriceLine!.objectId, 'stop');
    });

    test('events expose hoveredSeries', () {
      final s = chart.addLineSeries()..setData(_line(30, 1));
      layout();
      ChartEventParams? clicked;
      chart.subscribeClick((p) => clicked = p);
      final x = chart.timeScale().timeToCoordinate(_t0 + 10 * _day)!;
      chart.model.click(0, Offset(x, s.priceToCoordinate(10)!));
      expect(clicked!.hoveredSeries, same(s));
    });
  });
}

class _RangeData extends SeriesData {
  const _RangeData({required super.time, required this.low, required this.high});

  final double low;
  final double high;
}

class _RangeView extends CustomSeriesView<_RangeData> {
  int draws = 0;

  @override
  List<double> priceValues(_RangeData item) => [item.low, item.high];

  @override
  bool isWhitespace(_RangeData item) => item.low.isNaN;

  @override
  void draw(CustomSeriesDrawContext<_RangeData> ctx) {
    draws++;
    for (final bar in ctx.bars) {
      ctx.canvas.drawLine(
        Offset(bar.x, ctx.priceToCoordinate(bar.data.low)),
        Offset(bar.x, ctx.priceToCoordinate(bar.data.high)),
        Paint()..color = ctx.options.color,
      );
    }
  }
}

void extraGroups() {
  test('custom series: autoscale, last value and whitespace from the view', () {
    final chart = ChartController();
    final view = _RangeView();
    final s = chart.addCustomSeries(view);
    s.setData([
      for (var i = 0; i < 10; i++) _RangeData(time: _t0 + i * _day, low: i.toDouble(), high: i + 5.0),
      _RangeData(time: _t0 + 10 * _day, low: double.nan, high: double.nan),
    ]);
    chart.model.layout(const Size(400, 300), 1, _measure);
    expect(chart.priceScale().getVisibleRange(), const PriceRange(0, 14));
    expect(s.lastValueData()!.price, 14);
    expect(s.dataByIndex(10), isNull);
    expect(s.seriesType(), SeriesType.custom);
    chart.dispose();
  });

  test('up/down markers show the direction of an update, then expire', () async {
    final chart = ChartController();
    final s = chart.addLineSeries();
    final plugin = createUpDownMarkers(
      s,
      const UpDownMarkersOptions(updateVisibilityDuration: Duration(milliseconds: 10)),
    );
    plugin.setData(_line(5, 1));
    // _line(5, 1) ends at day 5.
    plugin.update(LineData(time: _t0 + 5 * _day, value: 10));
    expect(plugin.markers().single.sign, MarkerSign.positive);
    plugin.update(LineData(time: _t0 + 5 * _day, value: 3));
    expect(plugin.markers().single.sign, MarkerSign.negative);
    plugin.update(LineData(time: _t0 + 6 * _day, value: 3)); // new point: no marker
    expect(plugin.markers(), hasLength(1));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(plugin.markers(), isEmpty);
    expect(() => createUpDownMarkers(chart.addHistogramSeries() as dynamic), throwsA(anything));
    chart.dispose();
  });

  test('conflation merges bars when bar spacing < 1 device pixel', () {
    final chart = ChartController(
      options: const ChartOptions(timeScale: TimeScaleOptions(enableConflation: true, minBarSpacing: 0.01)),
    );
    final s = chart.addCandlestickSeries();
    s.setData([
      // 5000 bars on ~350px: spacing < 0.25, which conflates at DPR 2.
      for (var i = 0; i < 5000; i++)
        CandlestickData(time: _t0 + i * 60, open: i.toDouble(), high: i + 2.0, low: i - 2.0, close: i + 1.0),
    ]);
    chart.model.layout(const Size(400, 300), 2, _measure);
    chart.timeScale().fitContent();
    chart.model.layout(const Size(400, 300), 2, _measure);
    final ts = chart.model.timeScale;
    final factor = ts.conflationFactor(2);
    expect(factor, greaterThan(1));
    final model = chart.model.series.first as dynamic;
    final items = model.renderItems(factor);
    expect(items.length, lessThan(5000));
    final first = items.data.first as CandlestickData;
    expect(first.open, 0);
    expect(first.high, (factor - 1) + 2.0);
    expect(first.close, factor.toDouble());
    chart.dispose();
  });
}

void apiGroup() {
  test('pop, priceFormatter, pane.addSeries', () {
    final chart = ChartController();
    final s = chart.addLineSeries()..setData(_line(10, 1));
    final removed = s.pop(3);
    expect(removed, hasLength(3));
    expect(s.data(), hasLength(7));
    expect(chart.model.timeScale.pointsCount, 7);
    expect(s.priceFormatter().format(1.234), '1.23');
    final pane = chart.addPane();
    final h = pane.addHistogramSeries();
    expect(h.getPane().paneIndex(), 1);
    chart.dispose();
  });
}

void chartOptionsGroup() {
  test('defaultVisiblePriceScaleId puts series without an id on the left', () {
    final chart = ChartController(
      options: const ChartOptions(
        defaultVisiblePriceScaleId: 'left',
        leftPriceScale: PriceScaleOptions(visible: true),
      ),
    );
    final s = chart.addLineSeries()..setData(_line(5, 1));
    expect(s.priceScale().id, 'left');
    chart.dispose();
  });

  test('addDefaultPane: false starts without panes', () {
    final chart = ChartController(options: const ChartOptions(addDefaultPane: false));
    expect(chart.panes(), isEmpty);
    chart.model.layout(const Size(400, 300), 1, _measure);
    chart.addLineSeries().setData(_line(5, 1));
    expect(chart.panes(), hasLength(1));
    chart.dispose();
  });

  test('hoveredSeriesOnTop draws the hovered series last', () {
    final chart = ChartController();
    final a = chart.addLineSeries()..setData(_line(30, 1));
    chart.addLineSeries().setData([for (final d in _line(30, 1)) LineData(time: d.time, value: d.value + 100)]);
    chart.model.layout(const Size(400, 300), 1, _measure);
    final x = chart.timeScale().timeToCoordinate(_t0 + 10 * _day)!;
    chart.model.setCrosshairPosition(0, Offset(x, a.priceToCoordinate(10)!));
    final order = chart.model.drawOrder(chart.model.panes.first);
    expect(order.last, chart.model.series.first);
    chart.dispose();
  });
}

void perfStructuresGroup() {
  test('chunked min/max autoscale matches a full scan after updates', () {
    final chart = ChartController();
    final s = chart.addLineSeries();
    var values = [for (var i = 0; i < 1000; i++) ((i * 7919) % 1000).toDouble()];
    s.setData([for (var i = 0; i < values.length; i++) LineData(time: i, value: values[i])]);
    final model = chart.model.series.first;
    void check(int left, int right) {
      final info = model.baseAutoscaleInfo(IndexRange(left, right))!;
      final slice = values.sublist(left, right + 1);
      expect(info.priceRange!.min, slice.reduce((a, b) => a < b ? a : b));
      expect(info.priceRange!.max, slice.reduce((a, b) => a > b ? a : b));
    }

    for (final r in [(0, 999), (3, 70), (64, 127), (100, 900), (990, 999)]) {
      check(r.$1, r.$2);
    }
    // Replace the last value and append new ones.
    s.update(const LineData(time: 999, value: 5000));
    values[999] = 5000;
    check(900, 999);
    s.update(const LineData(time: 1000, value: -42));
    values = [...values, -42];
    check(0, 1000);
    chart.dispose();
  });
}

void transformGroup() {
  for (final mode in [PriceScaleMode.normal, PriceScaleMode.percentage, PriceScaleMode.indexedTo100]) {
    for (final inverted in [false, true]) {
      test('linear price transform matches priceToCoordinate ($mode, inverted: $inverted)', () {
        final chart = ChartController(
          options: ChartOptions(rightPriceScale: PriceScaleOptions(mode: mode, invertScale: inverted)),
        );
        final s = chart.addLineSeries()..setData(_line(50, 10));
        chart.model.layout(const Size(400, 300), 2, _measure);
        final model = chart.model.series.first;
        final (a, b) = model.priceTransform()!;
        for (final p in [10.0, 25.5, 59.0, 100.0]) {
          expect(a * p + b, closeTo(s.priceToCoordinate(p)!, 1e-6));
        }
        final ts = chart.model.timeScale;
        final (ia, ib) = ts.indexTransform();
        for (final i in [0, 17, 49]) {
          expect(ia * i + ib, closeTo(ts.indexToCoordinate(i), 1e-9));
        }
        chart.dispose();
      });
    }
  }
}

class _BoxView extends CustomSeriesView<_RangeData> {
  @override
  List<double> priceValues(_RangeData item) => [item.low, item.high];

  @override
  void draw(CustomSeriesDrawContext<_RangeData> ctx) {}

  @override
  CustomSeriesHitTestResult? hitTest(CustomSeriesDrawContext<_RangeData> ctx, double x, double y) {
    for (final bar in ctx.bars) {
      final top = ctx.priceToCoordinate(bar.data.high), bottom = ctx.priceToCoordinate(bar.data.low);
      if ((bar.x - x).abs() < 3 && y >= top && y <= bottom) {
        return CustomSeriesHitTestResult(distance: 0, objectId: 'box-${bar.index}');
      }
    }
    return null;
  }
}

void hoveredInfoGroup() {
  test('hoveredInfo: type, sourceKind and objectKind like upstream', () {
    final chart = ChartController();
    final candles = chart.addCandlestickSeries()
      ..setData([
        for (var i = 0; i < 30; i++)
          CandlestickData(time: _t0 + i * _day, open: 100.0 + i, high: 105.0 + i, low: 95.0 + i, close: 102.0 + i),
      ]);
    candles.createPriceLine(const PriceLineOptions(price: 140, id: 'tp'));
    createSeriesMarkers(candles, [
      SeriesMarker(time: _t0 + 10 * _day, position: SeriesMarkerPosition.aboveBar, shape: SeriesMarkerShape.circle, color: const Color(0xFF000000), id: 'm1'),
    ]);
    final boxes = chart.addCustomSeries(_BoxView(), const CustomSeriesOptions(), 1)
      ..setData([for (var i = 0; i < 30; i++) _RangeData(time: _t0 + i * _day, low: 10, high: 20)]);
    chart.model.layout(const Size(400, 600), 1, _measure);
    // Paint once so the markers know where they are.
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final ctx = chart.model.primitiveContext(chart.model.panes[0], chart.model.series.first, canvas);
    candles.priceScale(); // ensure scale
    for (final p in chart.model.series.first.primitives) {
      p.paint(ctx);
    }

    final events = <ChartEventParams>[];
    chart.subscribeClick(events.add);
    final x10 = chart.timeScale().timeToCoordinate(_t0 + 10 * _day)!;
    final x20 = chart.timeScale().timeToCoordinate(_t0 + 20 * _day)!;

    chart.model.click(0, Offset(x20, candles.priceToCoordinate(120)!));
    chart.model.click(0, Offset(x20, candles.priceToCoordinate(140)!));
    final markerY = (chart.model.series.first.primitives.first as SeriesMarkersPrimitive).hitTestCenterForTest!;
    chart.model.click(0, Offset(x10, markerY));
    chart.model.click(1, Offset(x20, boxes.priceToCoordinate(15)!));

    final infos = [for (final e in events) e.hoveredInfo!];
    expect((infos[0].type, infos[0].sourceKind, infos[0].objectKind),
        (HoveredItemType.seriesRange, HoveredSourceKind.series, HoveredObjectKind.series));
    expect((infos[1].type, infos[1].objectKind, infos[1].objectId),
        (HoveredItemType.priceLine, HoveredObjectKind.customPriceLine, 'tp'));
    expect((infos[2].type, infos[2].sourceKind, infos[2].objectKind, infos[2].objectId),
        (HoveredItemType.marker, HoveredSourceKind.seriesPrimitive, HoveredObjectKind.seriesMarker, 'm1'));
    expect((infos[3].type, infos[3].objectKind, infos[3].objectId, infos[3].series),
        (HoveredItemType.custom, HoveredObjectKind.customObject, 'box-20', boxes));
    chart.dispose();
  });
}
