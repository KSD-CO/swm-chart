import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/swm_chart.dart';

const _day = 86400;

List<CandlestickData> _bars() => [
  for (var i = 0; i < 50; i++) CandlestickData(time: i * _day, open: 100, high: 102, low: 98, close: 101),
];

DrawingToolSpec _tool(String id) => DrawingTools.groups.expand((g) => g.tools).firstWhere((t) => t.id == id);

const _anchors = [DrawingAnchor(10, 100), DrawingAnchor(20, 101)];

const _red = DrawingStyle(color: Color(0xFFF23645), lineWidth: 3, lineStyle: LineStyle.dashed);

void main() {
  test('new drawings of a kind take its saved style, until it is reset', () {
    final pro = ProChartController()..setData(_bars());
    addTearDown(pro.dispose);
    final line = TrendLineDrawing(id: 'a', anchors: _anchors, style: _red);
    pro.saveDefaultStyle(line);
    expect(pro.defaultStyleOf(line), same(_red));

    pro.activeTool = _tool('trendLine');
    final next = pro.drawings.tool!('b', _anchors);
    expect(next.style.color, _red.color);
    expect(next.style.lineWidth, 3);

    // Another kind keeps its own.
    pro.activeTool = _tool('horizontalLine');
    expect(pro.drawings.tool!('c', _anchors).style.color, isNot(_red.color));

    pro.resetDefaultStyle(line);
    pro.activeTool = _tool('trendLine');
    expect(pro.drawings.tool!('d', _anchors).style.color, isNot(_red.color));
  });

  test('kept in the chart state and on their own', () {
    final pro = ProChartController()..setData(_bars());
    addTearDown(pro.dispose);
    pro.saveDefaultStyle(TrendLineDrawing(id: 'a', anchors: _anchors, style: _red));
    final state = jsonDecode(jsonEncode(pro.saveState())) as Map<String, Object?>;
    final own = jsonDecode(jsonEncode(pro.saveDefaultStyles())) as Map<String, Object?>;

    for (final restore in [
      (ProChartController p) => p.restoreState(state),
      (ProChartController p) => p.restoreDefaultStyles(own),
    ]) {
      final other = ProChartController()..setData(_bars());
      addTearDown(other.dispose);
      restore(other);
      final style = other.defaultStyleOf(TrendLineDrawing(id: 'x', anchors: _anchors))!;
      expect((style.color, style.lineWidth, style.lineStyle), (_red.color, 3.0, LineStyle.dashed));
    }
  });

  testWidgets('the style bar saves and resets it', (tester) async {
    final pro = ProChartController()..setData(_bars());
    addTearDown(pro.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SwmProChart(controller: pro)),
      ),
    );
    final line = TrendLineDrawing(id: 'a', anchors: _anchors, style: _red);
    pro.drawings.add(line);
    pro.drawings.select('a');
    await tester.pump();

    await tester.tap(find.byTooltip('Save as default style'));
    await tester.pumpAndSettle();
    expect(find.text('Reset default style'), findsNothing);
    await tester.tap(find.text('Save as default style').last);
    await tester.pumpAndSettle();
    expect(pro.defaultStyleOf(line), isNotNull);

    await tester.tap(find.byTooltip('Save as default style'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset default style'));
    await tester.pumpAndSettle();
    expect(pro.defaultStyleOf(line), isNull);
  });
}
