// Frame-timing benchmark. Run in profile mode on a real device or desktop:
//
//   flutter drive -d macos --profile \
//     --driver=test_driver/perf_driver.dart --target=integration_test/perf_test.dart
//
// Results land in build/<scenario>.json (frame build/raster times).
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:swm_chart/swm_chart.dart';

const int barCount = 100000;
const Duration scenarioLength = Duration(seconds: 3);

List<CandlestickData> generateBars(int count) {
  final random = math.Random(1);
  final bars = <CandlestickData>[];
  var close = 100.0;
  const t0 = 1500000000;
  for (var i = 0; i < count; i++) {
    final open = close;
    close = math.max(1, open + (random.nextDouble() - 0.5) * 2);
    bars.add(CandlestickData(
      time: t0 + i * 60,
      open: open,
      high: math.max(open, close) + random.nextDouble(),
      low: math.min(open, close) - random.nextDouble(),
      close: close,
    ));
  }
  return bars;
}

class BenchChart extends StatefulWidget {
  const BenchChart({super.key, required this.chart});

  final ChartController chart;

  @override
  State<BenchChart> createState() => _BenchChartState();
}

class _BenchChartState extends State<BenchChart> {
  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(body: SizedBox(width: 800, height: 600, child: SwmChart(controller: widget.chart))),
      );
}

/// Runs [onFrame] every frame for [scenarioLength].
Future<void> drive(void Function(double t) onFrame) async {
  final done = Completer<void>();
  Duration? start;
  void tick(Duration now) {
    start ??= now;
    final t = (now - start!).inMicroseconds / scenarioLength.inMicroseconds;
    if (t >= 1) {
      done.complete();
      return;
    }
    onFrame(t);
    SchedulerBinding.instance.scheduleFrameCallback(tick);
  }

  SchedulerBinding.instance.scheduleFrameCallback(tick);
  SchedulerBinding.instance.scheduleFrame();
  await done.future;
}

void main() {
  const only = String.fromEnvironment('ONLY');
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final bars = generateBars(barCount);
  final volumes = [
    for (final b in bars) HistogramData(time: b.time, value: (b.high - b.low) * 1000, color: b.isUp ? Colors.teal : Colors.red),
  ];
  final timings = <String, Object?>{};

  Future<(ChartController, CandlestickSeriesApi)> setUp(WidgetTester tester, {bool conflation = false}) async {
    final chart = ChartController(
      options: ChartOptions(timeScale: TimeScaleOptions(enableConflation: conflation, minBarSpacing: 0.001)),
    );
    final candles = chart.addCandlestickSeries();
    final volume = chart.addHistogramSeries(const HistogramSeriesOptions(priceScaleId: 'vol'));
    chart.priceScale('vol').applyOptions(const PriceScaleOptions(scaleMargins: ScaleMargins(top: 0.8, bottom: 0)));
    final sw = Stopwatch()..start();
    candles.setData(bars);
    volume.setData(volumes);
    timings['setData_100k_x2_ms'] = sw.elapsedMilliseconds;
    await tester.pumpWidget(BenchChart(chart: chart));
    await tester.pump(const Duration(milliseconds: 200));
    return (chart, candles);
  }

  testWidgets('scroll (bar spacing 6)', skip: only.isNotEmpty && !'scroll (bar spacing 6)'.contains(only), (tester) async {
    final (chart, _) = await setUp(tester);
    await binding.watchPerformance(() async {
      await drive((t) => chart.timeScale().scrollToPosition(-t * 5000));
    }, reportKey: 'scroll');
    chart.dispose();
  });

  testWidgets('zoomed out, 100k visible, no conflation', skip: only.isNotEmpty && !'zoomed out, 100k visible, no conflation'.contains(only), (tester) async {
    final (chart, _) = await setUp(tester);
    chart.timeScale().fitContent();
    await binding.watchPerformance(() async {
      // Small jitter so every frame repaints and re-autoscales.
      await drive((t) => chart.timeScale().scrollToPosition(math.sin(t * 20) * 50));
    }, reportKey: 'zoomed_out');
    chart.dispose();
  });

  testWidgets('zoomed out, 100k visible, conflation', skip: only.isNotEmpty && !'zoomed out, 100k visible, conflation'.contains(only), (tester) async {
    final (chart, _) = await setUp(tester, conflation: true);
    chart.timeScale().fitContent();
    await binding.watchPerformance(() async {
      await drive((t) => chart.timeScale().scrollToPosition(math.sin(t * 20) * 50));
    }, reportKey: 'zoomed_out_conflation');
    chart.dispose();
  });

  testWidgets('realtime updates every frame', skip: only.isNotEmpty && !'realtime updates every frame'.contains(only), (tester) async {
    final (chart, candles) = await setUp(tester);
    var last = bars.last;
    var i = 0;
    await binding.watchPerformance(() async {
      await drive((t) {
        i++;
        if (i % 30 == 0) {
          last = CandlestickData(time: last.time + 60, open: last.close, high: last.close, low: last.close, close: last.close);
        } else {
          final c = last.close + math.sin(i / 3);
          last = CandlestickData(
            time: last.time,
            open: last.open,
            high: math.max(last.high, c),
            low: math.min(last.low, c),
            close: c,
          );
        }
        candles.update(last);
      });
    }, reportKey: 'realtime');
    chart.dispose();
  });

  testWidgets('crosshair moving', skip: only.isNotEmpty && !'crosshair moving'.contains(only), (tester) async {
    final (chart, candles) = await setUp(tester);
    await binding.watchPerformance(() async {
      await drive((t) {
        final bar = bars[barCount - 1 - (t * 100).floor()];
        chart.setCrosshairPosition(bar.close, bar.time, candles);
      });
    }, reportKey: 'crosshair');
    chart.dispose();
    binding.reportData = {...?binding.reportData, 'misc': timings};
  });
}
