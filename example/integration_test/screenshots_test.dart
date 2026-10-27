// Poses the demo for the pub.dev / README screenshots. Run on a simulator
// and capture the screen at each CHECKPOINT (see tool/screenshots.sh).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:swm_chart/swm_chart.dart';
import 'package:swm_chart_example/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const hold = Duration(seconds: int.fromEnvironment('HOLD_SECONDS', defaultValue: 4));

  Future<void> checkpoint(WidgetTester tester, String name) async {
    // Render the posed frame first: the capture happens during the hold.
    await tester.pump(const Duration(milliseconds: 300));
    debugPrint('CHECKPOINT $name');
    await tester.pump(hold);
  }

  testWidgets('screenshots', (tester) async {
    await tester.pumpWidget(const DemoApp());
    await tester.pump(const Duration(seconds: 2));
    final controller = (tester.widget(find.byType(SwmChart).first) as SwmChart).controller;
    final rect = tester.getRect(find.byType(SwmChart).first);

    // Zoom in a bit and show the crosshair on a candle.
    controller.timeScale().applyOptions(controller.timeScale().options.copyWith(barSpacing: 9));
    await tester.pump();
    final press = await tester.startGesture(rect.center.translate(-60, -40));
    await tester.pump(const Duration(milliseconds: 700));
    await press.up();
    await checkpoint(tester, 'trading_light');

    await tester.tap(find.byIcon(Icons.dark_mode));
    await checkpoint(tester, 'trading_dark');

    controller.clearCrosshairPosition();
    await tester.tap(find.byTooltip('Series type'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('area').last);
    await tester.pump(const Duration(milliseconds: 600));
    await checkpoint(tester, 'area_dark');

    await tester.tap(find.byIcon(Icons.light_mode));
    await tester.tap(find.widgetWithText(NavigationDestination, 'Yield curve'));
    await checkpoint(tester, 'yield_curve');

    await tester.tap(find.widgetWithText(NavigationDestination, 'Options'));
    await checkpoint(tester, 'options_chain');

    await tester.tap(find.widgetWithText(NavigationDestination, 'Tools'));
    await checkpoint(tester, 'drawing_tools');

    await tester.tap(find.text('Overlays'));
    await checkpoint(tester, 'overlays');

    for (final (chip, name) in [
      ('Indicators', 'indicators'),
      ('Orders', 'orders'),
      ('Heikin-Ashi', 'heikin_ashi'),
      ('Renko', 'renko'),
      ('Compare', 'compare'),
    ]) {
      await tester.ensureVisible(find.text(chip));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(chip));
      await checkpoint(tester, name);
    }

    await tester.tap(find.widgetWithText(NavigationDestination, 'Watchlist'));
    await checkpoint(tester, 'watchlist');
  });
}
