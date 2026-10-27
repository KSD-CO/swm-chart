import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/swm_chart.dart';

const _day = 86400;
const _t0 = 1704067200;

Future<(ChartController, CandlestickSeriesApi)> _pump(WidgetTester tester) async {
  final chart = ChartController();
  final candles = chart.addCandlestickSeries()
    ..setData([
      for (var i = 0; i < 100; i++)
        CandlestickData(time: _t0 + i * _day, open: 100, high: 105, low: 95, close: 100 + (i % 5 - 2.0)),
    ]);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 400, height: 400, child: SwmChart(controller: chart)),
      ),
    ),
  );
  addTearDown(chart.dispose);
  return (chart, candles);
}

void main() {
  testWidgets('dragging an order line moves it and reports the new price', (tester) async {
    final (chart, candles) = await _pump(tester);
    TradingLine? ended;
    var drags = 0;
    final trading = TradingLines(candles, onDrag: (_) => drags++, onDragEnd: (l) => ended = l);
    trading.add(TradingLine(id: 'limit', kind: TradingLineKind.order, price: 98, quantity: 5));
    await tester.pump();
    final y = candles.priceToCoordinate(98)!;
    final scrollBefore = chart.timeScale().scrollPosition();
    await tester.dragFrom(Offset(150, y), const Offset(0, -40));
    await tester.pump();
    expect(drags, greaterThan(0));
    expect(ended?.id, 'limit');
    expect(ended!.price, greaterThan(98));
    // Rounded to the price step (minMove 0.01).
    expect((ended!.price * 100).roundToDouble(), closeTo(ended!.price * 100, 1e-6));
    // The chart didn't scroll.
    expect(chart.timeScale().scrollPosition(), scrollBefore);
  });

  testWidgets('positions are not draggable by default', (tester) async {
    final (_, candles) = await _pump(tester);
    TradingLine? ended;
    final trading = TradingLines(candles, onDragEnd: (l) => ended = l);
    trading.add(TradingLine(id: 'pos', kind: TradingLineKind.position, price: 98, quantity: 2));
    await tester.pump();
    await tester.dragFrom(Offset(150, candles.priceToCoordinate(98)!), const Offset(0, -40));
    await tester.pump();
    expect(ended, isNull);
    expect(trading.byId('pos')!.price, 98);
  });

  test('P&L of a position and its TP / SL', () {
    final chart = ChartController();
    final candles = chart.addCandlestickSeries()
      ..setData([CandlestickData(time: _t0, open: 100, high: 110, low: 90, close: 105)]);
    final trading = TradingLines(candles)
      ..add(TradingLine(id: 'pos', kind: TradingLineKind.position, price: 100, quantity: 10))
      ..add(TradingLine(id: 'tp', kind: TradingLineKind.takeProfit, price: 120, quantity: 10))
      ..add(TradingLine(id: 'sl', kind: TradingLineKind.stopLoss, price: 95, quantity: 10));
    expect(trading.pnlOf(trading.byId('pos')!), 50); // (105 - 100) * 10
    expect(trading.pnlOf(trading.byId('tp')!), 200);
    expect(trading.pnlOf(trading.byId('sl')!), -50);
    expect(trading.primitive.labelOf(trading.byId('sl')!), 'SL  10  −50.00');
    // A short position gains when the price falls.
    trading.byId('pos')!.side = TradeSide.sell;
    expect(trading.pnlOf(trading.byId('pos')!), -50);
    chart.dispose();
  });

  test('alerts fire when the last price crosses them', () {
    final chart = ChartController();
    final candles = chart.addCandlestickSeries()
      ..setData([CandlestickData(time: _t0, open: 100, high: 100, low: 100, close: 100)]);
    final fired = <Object>[];
    final trading = TradingLines(candles, onAlert: (line, price) => fired.add(line.id))
      ..add(TradingLine(id: 'above', kind: TradingLineKind.alert, price: 102, condition: AlertCondition.crossingUp))
      ..add(TradingLine(id: 'below', kind: TradingLineKind.alert, price: 98, condition: AlertCondition.crossingDown))
      ..add(TradingLine(id: 'any', kind: TradingLineKind.alert, price: 101));
    void tick(double close) => candles.update(CandlestickData(time: _t0, open: 100, high: 110, low: 90, close: close));
    tick(101.5); // crosses 101 up
    expect(fired, ['any']);
    tick(103); // crosses 102 up
    expect(fired, ['any', 'above']);
    tick(97); // crosses 98 down (and 101, already fired)
    expect(fired, ['any', 'above', 'below']);
    expect(trading.byId('any')!.triggered, isTrue);
    chart.dispose();
  });

  test('removeTriggeredAlerts drops fired alerts', () {
    final chart = ChartController();
    final candles = chart.addCandlestickSeries()
      ..setData([CandlestickData(time: _t0, open: 100, high: 100, low: 100, close: 100)]);
    final trading = TradingLines(candles, removeTriggeredAlerts: true)
      ..add(TradingLine(id: 'a', kind: TradingLineKind.alert, price: 101));
    candles.update(CandlestickData(time: _t0, open: 100, high: 102, low: 100, close: 102));
    expect(trading.lines, isEmpty);
    chart.dispose();
  });
}
