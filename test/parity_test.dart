import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
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

  test('attribution logo path parses and is placed at the bottom left', () {
    final path = parseSvgPath('M0 0h10v10H0Z');
    expect(path.getBounds(), const Rect.fromLTWH(0, 0, 10, 10));
    final rect = attributionLogoRect(const Rect.fromLTWH(50, 0, 300, 200));
    expect(rect.left, 60);
    expect(rect.bottom, 190);
  });
}
