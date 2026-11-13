import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/swm_chart.dart';

List<CandlestickData> _bars(int n, {double last = 0}) => [
  for (var i = 0; i < n; i++)
    CandlestickData(time: i * 60, open: 10, high: 12, low: 9, close: i == n - 1 && last != 0 ? last : 11),
];

void main() {
  late ChartController chart;
  late SeriesApi series;

  setUp(() {
    chart = ChartController();
    series = chart.addCandlestickSeries();
  });
  tearDown(() => chart.dispose());

  // A full setData stores the new list's items; an update keeps the old
  // ones in front.
  bool keptFirst(List<SeriesData> before) => identical(series.data().first, before.first);

  test('a tick on the last bar, or one new bar, only updates', () {
    final first = _bars(5);
    series.syncData(first);
    expect(series.data(), hasLength(5));

    series.syncData(_bars(5, last: 13));
    expect(keptFirst(first), isTrue);
    expect((series.data().last as CandlestickData).close, 13);

    series.syncData(_bars(6, last: 14));
    expect(keptFirst(first), isTrue);
    expect(series.data(), hasLength(6));
    expect((series.data().last as CandlestickData).close, 14);
  });

  test('anything else is a setData', () {
    final first = _bars(5);
    series.syncData(first);

    // An older bar changed.
    final edited = _bars(5)..[1] = const CandlestickData(time: 60, open: 1, high: 2, low: 0, close: 1);
    series.syncData(edited);
    expect(keptFirst(first), isFalse);
    expect((series.data()[1] as CandlestickData).close, 1);

    // Two bars at once, fewer bars, a last bar with another time.
    for (final data in [
      _bars(7),
      _bars(3),
      [..._bars(2), const CandlestickData(time: 999, open: 1, high: 2, low: 0, close: 1)],
    ]) {
      final before = series.data();
      series.syncData(data);
      expect(series.data().map((d) => d.time), data.map((d) => d.time));
      expect(keptFirst(before), isFalse);
    }
  });

  test('stays right after the series is changed directly', () {
    series.syncData(_bars(5));
    series.setData(_bars(2));
    series.syncData(_bars(5, last: 20));
    expect(series.data(), hasLength(5));
    expect((series.data().last as CandlestickData).close, 20);
  });
}
