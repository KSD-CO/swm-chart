import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:swm_chart/swm_chart.dart';
import 'package:swm_chart_example/main.dart';

/// Drives real gestures on a device/simulator:
/// `flutter test integration_test -d <device>`.
/// Set HOLD_SECONDS to pause at checkpoints (for screenshots).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const hold = Duration(seconds: int.fromEnvironment('HOLD_SECONDS'));

  Future<void> checkpoint(WidgetTester tester, String name) async {
    debugPrint('CHECKPOINT $name');
    await tester.pump(hold);
  }

  testWidgets('pinch, long-press crosshair, dark mode', (tester) async {
    await tester.pumpWidget(const DemoApp());
    await tester.pump(const Duration(seconds: 1));
    final chartFinder = find.byType(SwmChart);
    final state = tester.state<State<StatefulWidget>>(chartFinder);
    final controller = (state.widget as SwmChart).controller;
    final rect = tester.getRect(chartFinder);
    final center = rect.center.translate(-40, 0);

    // Pinch out (zoom in).
    double visibleBars() {
      final r = controller.timeScale().getVisibleLogicalRange()!;
      return r.to - r.from;
    }

    final barsBefore = visibleBars();
    final f1 = await tester.startGesture(center.translate(-20, 0));
    final f2 = await tester.startGesture(center.translate(20, 0), pointer: 2);
    for (var i = 0; i < 10; i++) {
      await f1.moveBy(const Offset(-8, 0));
      await f2.moveBy(const Offset(8, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await f1.up();
    await f2.up();
    await tester.pump();
    expect(visibleBars(), lessThan(barsBefore / 1.5));
    await checkpoint(tester, 'pinched');

    // Long-press crosshair; the legend follows it.
    ChartEventParams? crosshair;
    controller.subscribeCrosshairMove((p) => crosshair = p);
    final press = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 700));
    await press.moveBy(const Offset(-60, 30));
    await tester.pump();
    await press.up();
    await tester.pump();
    expect(crosshair?.point, isNotNull);
    expect(crosshair!.seriesData, isNotEmpty);
    await checkpoint(tester, 'crosshair');

    // Dark mode toggle.
    await tester.tap(find.byIcon(Icons.dark_mode));
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.options.layout.backgroundColor, const Color(0xFF131722));
    await checkpoint(tester, 'dark');
  });
}
