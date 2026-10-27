// Order, position, take profit / stop loss and alert lines, draggable, with
// P&L labels and price alerts.
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show SystemMouseCursors;

import '../api/chart_controller.dart';
import '../options.dart';
import '../renderers/draw_utils.dart';
import 'primitive.dart';

enum TradingLineKind { position, order, takeProfit, stopLoss, alert }

enum TradeSide { buy, sell }

/// When an alert fires, comparing the previous and the new last price.
enum AlertCondition {
  /// Crosses the alert price in either direction.
  crossing,

  /// Crosses it going up.
  crossingUp,

  /// Crosses it going down.
  crossingDown,
}

/// A horizontal trading line.
class TradingLine {
  TradingLine({
    required this.id,
    required this.price,
    required this.kind,
    this.label,
    this.quantity,
    this.side = TradeSide.buy,
    this.color,
    bool? draggable,
    this.condition = AlertCondition.crossing,
  }) : draggable = draggable ?? kind != TradingLineKind.position;

  final Object id;
  double price;
  final TradingLineKind kind;

  /// Shown in the label box, e.g. `Limit`, `TP`, `Alert`. `null` uses a
  /// default per kind.
  String? label;

  /// Size of the order / position; shown in the label and used for P&L.
  double? quantity;
  TradeSide side;

  /// `null` picks the color of the kind.
  Color? color;

  /// Whether the user can drag the line to a new price. Positions are fixed
  /// by default.
  bool draggable;

  /// For [TradingLineKind.alert].
  AlertCondition condition;

  /// Set once an alert fired; triggered alerts are drawn faded.
  bool triggered = false;

  Color get effectiveColor =>
      color ??
      switch (kind) {
        TradingLineKind.position => side == TradeSide.buy ? const Color(0xFF26A69A) : const Color(0xFFEF5350),
        TradingLineKind.order => const Color(0xFF2962FF),
        TradingLineKind.takeProfit => const Color(0xFF26A69A),
        TradingLineKind.stopLoss => const Color(0xFFEF5350),
        TradingLineKind.alert => const Color(0xFFFF9800),
      };

  String get effectiveLabel =>
      label ??
      switch (kind) {
        TradingLineKind.position => side == TradeSide.buy ? 'Long' : 'Short',
        TradingLineKind.order => side == TradeSide.buy ? 'Buy limit' : 'Sell limit',
        TradingLineKind.takeProfit => 'TP',
        TradingLineKind.stopLoss => 'SL',
        TradingLineKind.alert => 'Alert',
      };

  LineStyle get lineStyle => switch (kind) {
    TradingLineKind.position => LineStyle.solid,
    TradingLineKind.order => LineStyle.solid,
    TradingLineKind.takeProfit || TradingLineKind.stopLoss => LineStyle.dashed,
    TradingLineKind.alert => LineStyle.dotted,
  };
}

/// Draws the lines of a [TradingLines] controller.
class TradingLinesPrimitive extends ChartPrimitive {
  TradingLinesPrimitive(this._owner);

  final TradingLines _owner;
  final Map<String, TextPainter> _text = {};

  static const double _boxPaddingH = 6;
  static const double _boxHeight = 20;
  static const double _left = 8;

  @override
  PrimitiveZOrder get zOrder => PrimitiveZOrder.top;

  TextPainter _painter(String text, Color color) {
    final key = '$text|${color.toARGB32()}';
    return _text[key] ??= TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600, height: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  /// Label box text of [line]: label, quantity, P&L.
  String labelOf(TradingLine line) {
    final parts = <String>[line.effectiveLabel];
    final q = line.quantity;
    if (q != null) parts.add(_owner.formatQuantity(q));
    final pnl = _owner.pnlOf(line);
    if (pnl != null) parts.add(_owner.formatPnl(pnl));
    return parts.join('  ');
  }

  @override
  void paint(PrimitivePaintContext ctx) {
    if (_text.length > 200) _text.clear();
    final canvas = ctx.canvas;
    final pr = ctx.pixelRatio;
    final width = ctx.paneSize.width;
    for (final line in _owner.lines) {
      final y = ctx.priceToCoordinate(line.price);
      if (y == null || y < -_boxHeight || y > ctx.paneSize.height + _boxHeight) continue;
      final color = line.triggered ? line.effectiveColor.withValues(alpha: 0.35) : line.effectiveColor;
      final dragging = _owner.dragging?.id == line.id;
      final lineWidth = math.max(1, (dragging ? 2 : 1) * pr).floorToDouble();
      canvas.save();
      canvas.scale(1 / pr);
      drawHorizontalLine(
        canvas,
        Paint()..color = color,
        (y * pr).roundToDouble(),
        0,
        width * pr,
        lineWidth,
        line.lineStyle,
      );
      canvas.restore();

      final text = _painter(labelOf(line), const Color(0xFFFFFFFF));
      final box = Rect.fromLTWH(_left, y - _boxHeight / 2, text.width + _boxPaddingH * 2, _boxHeight);
      final rrect = RRect.fromRectAndRadius(box, const Radius.circular(3));
      canvas.drawRRect(rrect, Paint()..color = color);
      text.paint(canvas, Offset(box.left + _boxPaddingH, y - text.height / 2));
      if (line.draggable) {
        // A grip to the right of the box hints that the line can be dragged.
        final grip = Paint()..color = color;
        for (var i = 0; i < 3; i++) {
          canvas.drawCircle(Offset(box.right + 6 + i * 4, y), 1.4, grip);
        }
      }
    }
  }

  @override
  List<AxisLabel> priceAxisLabels(PrimitiveContext ctx) => [
    for (final line in _owner.lines)
      if (ctx.priceToCoordinate(line.price) case final y?)
        AxisLabel(
          coordinate: y,
          text: _owner.series.formatPrice(line.price),
          backgroundColor: line.triggered ? line.effectiveColor.withValues(alpha: 0.35) : line.effectiveColor,
        ),
  ];

  @override
  PrimitiveHitTestResult? hitTest(PrimitiveContext ctx, double x, double y) {
    PrimitiveHitTestResult? best;
    for (final line in _owner.lines) {
      final ly = ctx.priceToCoordinate(line.price);
      if (ly == null) continue;
      final d = (ly - y).abs();
      if (d > _owner.hitTolerance) continue;
      if (best == null || d < best.distance) {
        best = PrimitiveHitTestResult(
          externalId: TradingLineHit(line.id),
          distance: d,
          hitTestPriority: 1,
          cursor: line.draggable ? SystemMouseCursors.resizeUpDown : null,
        );
      }
    }
    return best;
  }
}

/// `hoveredObjectId` of a trading line.
class TradingLineHit {
  const TradingLineHit(this.id);

  final Object id;

  @override
  bool operator ==(Object other) => other is TradingLineHit && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Order, position, TP / SL and alert lines on a price series.
///
/// ```dart
/// final trading = TradingLines(candles,
///     onDragEnd: (line) => api.modifyOrder(line.id, line.price),
///     onAlert: (line, price) => notify('${line.id} hit $price'));
/// trading.add(TradingLine(id: 'pos', kind: TradingLineKind.position, price: 101.2, quantity: 10));
/// trading.add(TradingLine(id: 'tp', kind: TradingLineKind.takeProfit, price: 110, quantity: 10));
/// trading.add(TradingLine(id: 'a1', kind: TradingLineKind.alert, price: 95));
/// ```
class TradingLines {
  TradingLines(
    this.series, {
    this.onDrag,
    this.onDragEnd,
    this.onAlert,
    this.removeTriggeredAlerts = false,
    this.hitTolerance = 8,
    this.formatPnl = _defaultPnl,
    this.formatQuantity = _defaultQuantity,
  }) {
    primitive = TradingLinesPrimitive(this);
    series.attachPrimitive(primitive);
    series.chart.subscribePointer(_onPointer);
    series.subscribeDataChanged(_onData);
    _lastPrice = _currentPrice();
  }

  final SeriesApi series;

  /// While a line is dragged; the line already has the new price.
  final void Function(TradingLine line)? onDrag;

  /// When a drag ends, with the final price (e.g. to modify the order).
  final void Function(TradingLine line)? onDragEnd;

  /// When an alert's condition is met by a new last price.
  final void Function(TradingLine alert, double price)? onAlert;

  /// Drop alerts once they fired instead of fading them.
  final bool removeTriggeredAlerts;

  /// Distance in logical pixels within which a line can be grabbed.
  final double hitTolerance;

  final String Function(double pnl) formatPnl;
  final String Function(double quantity) formatQuantity;

  late final TradingLinesPrimitive primitive;
  final List<TradingLine> _lines = [];
  TradingLine? _dragging;
  double? _dragFrom;
  double? _lastPrice;

  static String _defaultPnl(double pnl) => '${pnl >= 0 ? '+' : '−'}${pnl.abs().toStringAsFixed(2)}';

  static String _defaultQuantity(double q) => q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toString();

  List<TradingLine> get lines => List.unmodifiable(_lines);

  /// The line being dragged, if any.
  TradingLine? get dragging => _dragging;

  TradingLine? byId(Object id) => _lines.where((l) => l.id == id).firstOrNull;

  void add(TradingLine line) {
    _lines.removeWhere((l) => l.id == line.id);
    _lines.add(line);
    primitive.requestUpdate();
  }

  void remove(Object id) {
    _lines.removeWhere((l) => l.id == id);
    primitive.requestUpdate();
  }

  void clear() {
    _lines.clear();
    primitive.requestUpdate();
  }

  /// Moves a line programmatically (e.g. after the broker confirms).
  void setPrice(Object id, double price) {
    byId(id)?.price = price;
    primitive.requestUpdate();
  }

  void dispose() {
    series.chart.unsubscribePointer(_onPointer);
    series.unsubscribeDataChanged(_onData);
    series.detachPrimitive(primitive);
  }

  // ---- P&L ----

  double? _currentPrice() {
    final last = series.lastValueData();
    return last == null || last.noData ? null : last.price;
  }

  /// Profit or loss shown on [line]: a position against the last price,
  /// TP / SL against the position they protect (the first position line).
  double? pnlOf(TradingLine line) {
    final q = line.quantity;
    if (q == null) return null;
    double sign(TradeSide s) => s == TradeSide.buy ? 1 : -1;
    switch (line.kind) {
      case TradingLineKind.position:
        final price = _currentPrice();
        return price == null ? null : (price - line.price) * q * sign(line.side);
      case TradingLineKind.takeProfit:
      case TradingLineKind.stopLoss:
        final position = _lines.where((l) => l.kind == TradingLineKind.position).firstOrNull;
        if (position == null) return null;
        return (line.price - position.price) * q * sign(position.side);
      case TradingLineKind.order:
      case TradingLineKind.alert:
        return null;
    }
  }

  // ---- alerts ----

  void _onData() {
    final price = _currentPrice();
    final previous = _lastPrice;
    _lastPrice = price;
    if (price == null || previous == null || price == previous) return;
    var changed = false;
    for (final line in List.of(_lines)) {
      if (line.kind != TradingLineKind.alert || line.triggered) continue;
      final up = previous < line.price && price >= line.price;
      final down = previous > line.price && price <= line.price;
      final hit = switch (line.condition) {
        AlertCondition.crossing => up || down,
        AlertCondition.crossingUp => up,
        AlertCondition.crossingDown => down,
      };
      if (!hit) continue;
      line.triggered = true;
      changed = true;
      onAlert?.call(line, price);
      if (removeTriggeredAlerts) _lines.remove(line);
    }
    // P&L labels follow the last price.
    if (changed || _lines.any((l) => l.kind == TradingLineKind.position)) primitive.requestUpdate();
  }

  // ---- dragging ----

  bool _onPointer(ChartPointerEvent e) {
    switch (e.phase) {
      case ChartPointerPhase.down:
        if (e.paneIndex != series.getPane().paneIndex()) return false;
        final hit = e.hoveredInfo?.objectId;
        if (hit is! TradingLineHit) return false;
        final line = byId(hit.id);
        if (line == null || !line.draggable) return false;
        _dragging = line;
        _dragFrom = line.price;
        primitive.requestUpdate();
        return true;
      case ChartPointerPhase.move:
        final line = _dragging;
        if (line == null) return true;
        final price = series.coordinateToPrice(e.point.dy);
        if (price == null) return true;
        line.price = _round(price);
        if (line.kind == TradingLineKind.alert) line.triggered = false;
        primitive.requestUpdate();
        onDrag?.call(line);
        return true;
      case ChartPointerPhase.up:
      case ChartPointerPhase.cancel:
        final line = _dragging;
        if (line != null) {
          if (e.phase == ChartPointerPhase.cancel) {
            line.price = _dragFrom!;
          } else if (line.price != _dragFrom) {
            onDragEnd?.call(line);
          }
        }
        _dragging = null;
        _dragFrom = null;
        primitive.requestUpdate();
        return true;
    }
  }

  /// Rounds to the series' price step (its `minMove`).
  double _round(double price) {
    final minMove = series.options.priceFormat.minMove;
    if (minMove <= 0) return price;
    return (price / minMove).round() * minMove;
  }
}
