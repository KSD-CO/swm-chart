import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/swm_chart.dart';

const _day = 86400;
const _t0 = 1704067200; // 2024-01-01T00:00:00Z

List<CandlestickData> _bars(int count, {int start = 0}) => List.generate(count, (i) {
  final o = 100.0 + (start + i);
  return CandlestickData(time: _t0 + (start + i) * _day, open: o, high: o + 2, low: o - 2, close: o + 1);
});

double _measure(String s) => s.length * 7.0;

void main() {
  late ChartController chart;

  setUp(() => chart = ChartController());
  tearDown(() => chart.dispose());

  void layout([Size size = const Size(400, 300)]) => chart.model.layout(size, 2, _measure);

  test('merges times of all series into one time scale', () {
    final a = chart.addLineSeries();
    final b = chart.addLineSeries();
    a.setData([const LineData(time: 1, value: 1), const LineData(time: 3, value: 3)]);
    b.setData([const LineData(time: 2, value: 2), const LineData(time: 3, value: 3)]);
    expect(chart.model.timeScale.times, [1, 2, 3]);
    expect(a.dataByIndex(0)!.time, 1);
    expect(a.dataByIndex(1), isNull);
    expect(b.dataByIndex(1)!.time, 2);
  });

  test('setData rejects unsorted data', () {
    final s = chart.addLineSeries();
    expect(
      () => s.setData([const LineData(time: 2, value: 1), const LineData(time: 1, value: 1)]),
      throwsArgumentError,
    );
  });

  test('update replaces the last bar or appends a new one', () {
    final s = chart.addCandlestickSeries();
    s.setData(_bars(3));
    s.update(CandlestickData(time: _t0 + 2 * _day, open: 1, high: 1, low: 1, close: 1));
    expect(s.data().cast<CandlestickData>().length, 3);
    expect(s.data().cast<CandlestickData>().last.close, 1);
    s.update(CandlestickData(time: _t0 + 3 * _day, open: 1, high: 1, low: 1, close: 1));
    expect(s.data().cast<CandlestickData>().length, 4);
    expect(chart.model.timeScale.pointsCount, 4);
    expect(() => s.update(CandlestickData(time: _t0, open: 1, high: 1, low: 1, close: 1)), throwsArgumentError);
  });

  test('new bar shifts the view when the last bar is visible', () {
    final s = chart.addCandlestickSeries();
    s.setData(_bars(100));
    layout();
    final before = chart.timeScale().getVisibleLogicalRange()!;
    s.update(_bars(1, start: 100).first);
    final after = chart.timeScale().getVisibleLogicalRange()!;
    expect(after.to, before.to + 1);
  });

  test('new bar keeps the view when scrolled into history', () {
    final s = chart.addCandlestickSeries();
    s.setData(_bars(300));
    layout();
    chart.timeScale().scrollToPosition(-100);
    final before = chart.timeScale().getVisibleLogicalRange()!;
    s.update(_bars(1, start: 300).first);
    final after = chart.timeScale().getVisibleLogicalRange()!;
    expect(after.from, closeTo(before.from, 1e-9));
    expect(after.to, closeTo(before.to, 1e-9));
  });

  test('prepending history keeps the same bars visible', () {
    final s = chart.addCandlestickSeries();
    s.setData(_bars(100, start: 100));
    layout();
    chart.timeScale().scrollToPosition(-20);
    final firstVisibleTime = chart.timeScale().getVisibleRange()!.from;
    s.setData([..._bars(100), ...s.data().cast<CandlestickData>()]);
    layout();
    expect(chart.timeScale().getVisibleRange()!.from, firstVisibleTime);
  });

  test('autoscale fits the visible bars within the scale margins', () {
    final s = chart.addCandlestickSeries();
    s.setData(_bars(50));
    layout();
    final paneHeight = chart.model.panes.first.height;
    final range = chart.priceScale().getVisibleRange()!;
    final visible = chart.model.timeScale.visibleStrictRange()!;
    final shown = s.data().cast<CandlestickData>().where((d) {
      final i = chart.model.timeScale.timeToIndex(d.time)!;
      return visible.contains(i);
    });
    expect(range.max, shown.map((d) => d.high).reduce((a, b) => a > b ? a : b));
    expect(range.min, shown.map((d) => d.low).reduce((a, b) => a < b ? a : b));
    // Default margins: 20% top, 10% bottom.
    expect(s.priceToCoordinate(range.max), closeTo(paneHeight * 0.2, 1));
    expect(s.priceToCoordinate(range.min), closeTo(paneHeight * 0.9 - 1, 1));
  });

  test('overlay price scale is independent from the right scale', () {
    chart.addCandlestickSeries().setData(_bars(50));
    final vol = chart.addHistogramSeries(const HistogramSeriesOptions(priceScaleId: 'vol'));
    chart.priceScale('vol').applyOptions(const PriceScaleOptions(scaleMargins: ScaleMargins(top: 0.8, bottom: 0)));
    vol.setData([for (var i = 0; i < 50; i++) HistogramData(time: _t0 + i * _day, value: 1000.0 * (i + 1))]);
    layout();
    expect(chart.priceScale('vol').getVisibleRange()!.min, 0); // includes histogram base
    expect(chart.priceScale().getVisibleRange()!.max, lessThan(1000));
    expect(chart.priceScale('vol').width(), 0);
  });

  test('magnet snaps the crosshair to the close price', () {
    final s = chart.addCandlestickSeries();
    s.setData(_bars(50));
    layout();
    final last = s.data().cast<CandlestickData>().last;
    final x = chart.timeScale().timeToCoordinate(last.time)!;
    ChartEventParams? event;
    chart.subscribeCrosshairMove((p) => event = p);
    chart.model.setCrosshairPosition(0, Offset(x, 5));
    final c = chart.model.crosshair!;
    expect(c.y, closeTo(s.priceToCoordinate(last.close)!, 1e-9));
    expect(event!.time, last.time);
    expect(event!.seriesData[s], same(last));
  });

  test('visible logical range listeners fire after changes', () async {
    final s = chart.addCandlestickSeries();
    final ranges = <LogicalRange?>[];
    chart.timeScale().subscribeVisibleLogicalRangeChange(ranges.add);
    s.setData(_bars(100));
    layout();
    await Future<void>.delayed(Duration.zero);
    expect(ranges, hasLength(1));
    chart.timeScale().scrollToPosition(-10);
    layout();
    await Future<void>.delayed(Duration.zero);
    expect(ranges, hasLength(2));
  });

  test('price formatters', () {
    final candles = chart.addCandlestickSeries(
      const CandlestickSeriesOptions(priceFormat: PriceFormat.price(precision: 3, minMove: 0.001)),
    );
    expect(candles.priceScale().options, isNotNull);
    final vol = chart.addHistogramSeries(
      const HistogramSeriesOptions(priceFormat: PriceFormat.volume(), priceScaleId: 'v'),
    );
    chart.model.setSeriesData(chart.model.series.elementAt(0) as dynamic, _bars(1));
    vol.setData([HistogramData(time: _t0, value: 1234567)]);
    final volModel = chart.model.series.elementAt(1);
    expect(chart.model.formatSeriesPrice(volModel, 1234567), '1.23M');
    expect(chart.model.formatSeriesPrice(volModel, 950), '950');
    expect(chart.model.formatSeriesPrice(chart.model.series.elementAt(0), -1.5), '−1.500');
  });
}
