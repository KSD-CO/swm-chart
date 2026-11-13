import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/swm_chart.dart';

const _bids = [DepthLevel(99, 30), DepthLevel(99.5, 10), DepthLevel(98, 0), DepthLevel(98.5, 20)];
const _asks = [DepthLevel(101, 25), DepthLevel(100.5, 5), DepthLevel(102, 40)];

void main() {
  group('DepthBook', () {
    final book = DepthBook(_bids, _asks);

    test('each side from its best price, with running totals, empty levels out', () {
      expect(book.bids, [(99.5, 10.0), (99.0, 40.0), (98.5, 60.0)]);
      expect(book.asks, [(100.5, 5.0), (101.0, 30.0), (102.0, 70.0)]);
    });

    test('mid, spread and the total at a price', () {
      expect(book.mid, 100);
      expect(book.spread, 1);
      expect(book.bidTotalAt(99.2), 10);
      expect(book.bidTotalAt(98.5), 60);
      expect(book.bidTotalAt(99.8), 0);
      expect(book.askTotalAt(101.5), 30);
      expect(book.askTotalAt(100), 0);
    });

    test('one side, or none', () {
      expect(DepthBook(const [], _asks).mid, 100.5);
      expect(DepthBook(const [], _asks).spread, isNull);
      expect(DepthBook(const [], const []).mid, isNull);
    });
  });

  testWidgets('draws, shows the mid and follows the pointer', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SwmDepthChart(bids: _bids, asks: _asks, semanticsLabel: 'Depth'),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Depth'), findsOneWidget);
    final box = tester.getRect(find.byType(SwmDepthChart));
    final gesture = await tester.startGesture(box.centerLeft + const Offset(80, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(300, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Empty and one-sided books paint nothing broken.
    for (final (bids, asks) in [(const <DepthLevel>[], const <DepthLevel>[]), (_bids, const <DepthLevel>[])]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SwmDepthChart(bids: bids, asks: asks, range: 0.01),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });
}
