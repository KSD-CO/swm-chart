import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/swm_chart.dart';

const _day = 86400;

CandlestickData _bar(int i) =>
    CandlestickData(time: i * _day, open: 100.0 + i, high: 101.0 + i, low: 99.0 + i, close: 100.5 + i);

List<CandlestickData> _bars(int n) => [for (var i = 0; i < n; i++) _bar(i)];

void main() {
  group('controller', () {
    test('shows the bars before the start, then adds them one at a time', () {
      final pro = ProChartController()..setData(_bars(10), volumes: List.filled(10, 5));
      addTearDown(pro.dispose);
      pro.startReplay(4);
      expect(pro.replaying, isTrue);
      expect(pro.mainSeries.data(), hasLength(4));
      expect(pro.volumeSeries!.data(), hasLength(4));
      expect(pro.replayRemaining, 6);

      expect(pro.replayStep(), isTrue);
      expect(pro.mainSeries.data(), hasLength(5));
      expect(pro.volumeSeries!.data(), hasLength(5));

      pro.stopReplay();
      expect(pro.replaying, isFalse);
      expect(pro.mainSeries.data(), hasLength(10));
    });

    test('new bars wait behind the replay point', () {
      final pro = ProChartController()..setData(_bars(10));
      addTearDown(pro.dispose);
      pro.startReplay(8);
      pro.update(_bar(10));
      expect(pro.mainSeries.data(), hasLength(8));
      expect(pro.replayRemaining, 3);
      pro.setData(_bars(12));
      expect(pro.mainSeries.data(), hasLength(8));
      pro.stopReplay();
      expect(pro.mainSeries.data(), hasLength(12));
    });

    testWidgets('plays at its speed and stops at the end', (tester) async {
      final pro = ProChartController()..setData(_bars(10));
      addTearDown(pro.dispose);
      pro.startReplay(5);
      pro.replaySpeed = 2;
      pro.playReplay();
      expect(pro.replayPlaying, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(pro.mainSeries.data(), hasLength(7));
      await tester.pump(const Duration(seconds: 5));
      expect(pro.mainSeries.data(), hasLength(10));
      expect(pro.replayPlaying, isFalse);
      expect(pro.replayStep(), isFalse);
    });

    test('works on a built chart type', () {
      final pro = ProChartController()
        ..setData(_bars(60))
        ..type = ProChartType.renko;
      addTearDown(pro.dispose);
      final all = pro.mainSeries.data().length;
      pro.startReplay(30);
      expect(pro.mainSeries.data().length, lessThan(all));
      pro.stopReplay();
      expect(pro.mainSeries.data(), hasLength(all));
    });
  });

  testWidgets('the replay button: pick a bar, step, play and exit', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final pro = ProChartController()..setData(_bars(40));
    addTearDown(pro.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SwmProChart(controller: pro)),
      ),
    );

    await tester.tap(find.byTooltip('Bar replay'));
    await tester.pump();
    expect(pro.pickingReplayStart, isTrue);
    expect(find.text('Tap a bar to replay from'), findsOneWidget);

    // Esc cancels the pick.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(pro.pickingReplayStart, isFalse);

    await tester.tap(find.byTooltip('Bar replay'));
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.byType(SwmChart)));
    await tester.pump();
    expect(pro.replaying, isTrue);
    expect(find.byType(ReplayBar), findsOneWidget);
    final shown = pro.mainSeries.data().length;
    expect(shown, lessThan(40));

    await tester.tap(find.byTooltip('Next bar'));
    await tester.pump();
    expect(pro.mainSeries.data(), hasLength(shown + 1));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(pro.mainSeries.data(), hasLength(shown + 2));

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(pro.replayPlaying, isTrue);
    await tester.pump(const Duration(milliseconds: 2100));
    expect(pro.mainSeries.data(), hasLength(shown + 4));

    await tester.tap(find.byTooltip('Exit replay').first);
    await tester.pump();
    expect(pro.replaying, isFalse);
    expect(pro.mainSeries.data(), hasLength(40));
    expect(find.byType(ReplayBar), findsNothing);
  });

  testWidgets('on a phone, replay is in the settings menu', (tester) async {
    tester.view.physicalSize = const Size(420, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final pro = ProChartController()..setData(_bars(40));
    addTearDown(pro.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SwmProChart(controller: pro)),
      ),
    );
    expect(find.byTooltip('Bar replay'), findsNothing);
    await tester.tap(find.byTooltip('Chart settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bar replay'));
    await tester.pumpAndSettle();
    expect(pro.pickingReplayStart, isTrue);
  });
}
