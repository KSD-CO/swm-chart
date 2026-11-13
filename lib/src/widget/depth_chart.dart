import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../renderers/label_cache.dart';

/// One price level of an order book: [size] waiting at [price].
@immutable
class DepthLevel {
  const DepthLevel(this.price, this.size);

  final double price;
  final double size;

  @override
  bool operator ==(Object other) => other is DepthLevel && other.price == price && other.size == size;

  @override
  int get hashCode => Object.hash(price, size);

  @override
  String toString() => 'DepthLevel($price, $size)';
}

/// An order book's depth: the bids piled up to the left of the mid price
/// and the asks to the right, each level adding to the total from the
/// best price out. Hover or drag across it for the total at a price.
///
/// ```dart
/// SwmDepthChart(
///   bids: [DepthLevel(99.5, 12), DepthLevel(99, 30)],
///   asks: [DepthLevel(100.5, 8), DepthLevel(101, 25)],
/// )
/// ```
class SwmDepthChart extends StatefulWidget {
  const SwmDepthChart({
    super.key,
    required this.bids,
    required this.asks,
    this.height = 220,
    this.bidColor = const Color(0xFF26A69A),
    this.askColor = const Color(0xFFEF5350),
    this.areaOpacity = 0.22,
    this.lineWidth = 1.5,
    this.range,
    this.textColor = const Color(0xFF787B86),
    this.gridColor = const Color(0x1F787B86),
    this.fontSize = 11,
    this.showMidPrice = true,
    this.interactive = true,
    this.priceFormatter,
    this.sizeFormatter,
    this.semanticsLabel,
  });

  /// Buy orders and sell orders, in any order; levels without a positive
  /// size are left out.
  final List<DepthLevel> bids;
  final List<DepthLevel> asks;
  final double height;
  final Color bidColor;
  final Color askColor;
  final double areaOpacity;
  final double lineWidth;

  /// How far each side reaches, as a share of the mid price (0.02 shows
  /// ±2%); `null` shows every level.
  final double? range;
  final Color textColor;
  final Color gridColor;
  final double fontSize;

  /// The mid price (and spread) at the top.
  final bool showMidPrice;

  /// A crosshair with the total at the price under the pointer.
  final bool interactive;
  final String Function(double price)? priceFormatter;
  final String Function(double size)? sizeFormatter;

  /// Read by screen readers; nothing is announced when null.
  final String? semanticsLabel;

  @override
  State<SwmDepthChart> createState() => _SwmDepthChartState();
}

class _SwmDepthChartState extends State<SwmDepthChart> {
  final _labels = LabelCache(capacity: 64);
  late DepthBook _book = DepthBook(widget.bids, widget.asks);
  double? _x;

  @override
  void didUpdateWidget(SwmDepthChart old) {
    super.didUpdateWidget(old);
    if (!identical(old.bids, widget.bids) || !identical(old.asks, widget.asks)) {
      _book = DepthBook(widget.bids, widget.asks);
    }
  }

  @override
  void dispose() {
    _labels.clear();
    super.dispose();
  }

  void _at(Offset? p) => setState(() => _x = p?.dx);

  @override
  Widget build(BuildContext context) {
    final w = widget;
    Widget child = CustomPaint(
      painter: DepthChartPainter(
        book: _book,
        bidColor: w.bidColor,
        askColor: w.askColor,
        areaOpacity: w.areaOpacity,
        lineWidth: w.lineWidth,
        range: w.range,
        textColor: w.textColor,
        gridColor: w.gridColor,
        fontSize: w.fontSize,
        showMidPrice: w.showMidPrice,
        priceFormatter: w.priceFormatter,
        sizeFormatter: w.sizeFormatter,
        crosshairX: _x,
        labels: _labels,
      ),
    );
    if (w.interactive) {
      child = MouseRegion(
        onHover: (e) => _at(e.localPosition),
        onExit: (_) => _at(null),
        child: GestureDetector(
          onHorizontalDragStart: (d) => _at(d.localPosition),
          onHorizontalDragUpdate: (d) => _at(d.localPosition),
          onHorizontalDragEnd: (_) => _at(null),
          onTapDown: (d) => _at(d.localPosition),
          onTapUp: (_) => _at(null),
          dragStartBehavior: DragStartBehavior.down,
          child: child,
        ),
      );
    }
    child = RepaintBoundary(
      child: SizedBox(height: w.height, width: double.infinity, child: child),
    );
    final label = w.semanticsLabel;
    return label == null ? ExcludeSemantics(child: child) : Semantics(label: label, image: true, child: child);
  }
}

/// Both sides of a book, best price first, with the running totals.
class DepthBook {
  DepthBook(List<DepthLevel> bids, List<DepthLevel> asks)
    : bids = _side(bids, descending: true),
      asks = _side(asks, descending: false);

  /// Best (highest) bid first; `.$2` is the total from the best bid down
  /// to that level.
  final List<(double price, double total)> bids;

  /// Best (lowest) ask first, with the total up to that level.
  final List<(double price, double total)> asks;

  static List<(double, double)> _side(List<DepthLevel> levels, {required bool descending}) {
    final sorted = [
      for (final l in levels)
        if (l.size > 0 && l.price.isFinite && l.size.isFinite) l,
    ]..sort((a, b) => descending ? b.price.compareTo(a.price) : a.price.compareTo(b.price));
    var total = 0.0;
    return [for (final l in sorted) (l.price, total += l.size)];
  }

  bool get isEmpty => bids.isEmpty && asks.isEmpty;

  /// Halfway between the best bid and ask (or the one there is).
  double? get mid {
    if (bids.isEmpty && asks.isEmpty) return null;
    if (bids.isEmpty) return asks.first.$1;
    if (asks.isEmpty) return bids.first.$1;
    return (bids.first.$1 + asks.first.$1) / 2;
  }

  double? get spread => bids.isEmpty || asks.isEmpty ? null : asks.first.$1 - bids.first.$1;

  /// The bids' total at [price] and above it.
  double bidTotalAt(double price) {
    var total = 0.0;
    for (final (p, t) in bids) {
      if (p < price) break;
      total = t;
    }
    return total;
  }

  /// The asks' total at [price] and below it.
  double askTotalAt(double price) {
    var total = 0.0;
    for (final (p, t) in asks) {
      if (p > price) break;
      total = t;
    }
    return total;
  }
}

/// Paints a [SwmDepthChart].
class DepthChartPainter extends CustomPainter {
  DepthChartPainter({
    required this.book,
    this.bidColor = const Color(0xFF26A69A),
    this.askColor = const Color(0xFFEF5350),
    this.areaOpacity = 0.22,
    this.lineWidth = 1.5,
    this.range,
    this.textColor = const Color(0xFF787B86),
    this.gridColor = const Color(0x1F787B86),
    this.fontSize = 11,
    this.showMidPrice = true,
    this.priceFormatter,
    this.sizeFormatter,
    this.crosshairX,
    LabelCache? labels,
  }) : _labels = labels ?? LabelCache(capacity: 32);

  final DepthBook book;
  final Color bidColor;
  final Color askColor;
  final double areaOpacity;
  final double lineWidth;
  final double? range;
  final Color textColor;
  final Color gridColor;
  final double fontSize;
  final bool showMidPrice;
  final String Function(double price)? priceFormatter;
  final String Function(double size)? sizeFormatter;

  /// Where the pointer is, in the painter's coordinates.
  final double? crosshairX;
  final LabelCache _labels;

  TextPainter _text(String s, {Color? color, FontWeight? weight}) =>
      _labels.text(s, TextStyle(color: color ?? textColor, fontSize: fontSize, fontWeight: weight));

  @override
  void paint(Canvas canvas, Size size) {
    final mid = book.mid;
    if (size.isEmpty || mid == null) return;

    // The prices shown.
    var lo = book.bids.isEmpty ? mid : book.bids.last.$1;
    var hi = book.asks.isEmpty ? mid : book.asks.last.$1;
    final r = range;
    if (r != null) {
      lo = math.max(lo, mid * (1 - r));
      hi = math.min(hi, mid * (1 + r));
    }
    // Keep the mid in the middle.
    final half = math.max(mid - lo, hi - mid);
    lo = mid - (half == 0 ? mid.abs() * 0.01 + 1e-9 : half);
    hi = mid + (mid - lo);

    var top = 0.0;
    for (final (p, t) in book.bids) {
      if (p < lo) break;
      top = math.max(top, t);
    }
    for (final (p, t) in book.asks) {
      if (p > hi) break;
      top = math.max(top, t);
    }
    if (top <= 0) top = 1;
    final sizeStep = _niceStep(top / 3);
    top = (top * 1.08 / sizeStep).ceil() * sizeStep;

    // Room for the axes.
    final sizeTicks = [for (var v = sizeStep; v <= top; v += sizeStep) v];
    final axisW = sizeTicks.map((v) => _text(_size(v)).width).fold(0.0, (double a, double b) => math.max(a, b)) + 10;
    final labelH = _text('0').height;
    final topPad = showMidPrice ? labelH + 8 : 4.0;
    final plot = Rect.fromLTRB(0, topPad, size.width - axisW, size.height - labelH - 6);
    if (plot.width <= 0 || plot.height <= 0) return;

    double x(double price) => plot.left + (price - lo) / (hi - lo) * plot.width;
    double y(double total) => plot.bottom - total / top * plot.height;
    double priceAt(double px) => lo + (px - plot.left) / plot.width * (hi - lo);

    // Grid and the size axis.
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final v in sizeTicks) {
      final yy = y(v);
      canvas.drawLine(Offset(plot.left, yy), Offset(plot.right, yy), grid);
      final t = _text(_size(v));
      t.paint(canvas, Offset(plot.right + 6, yy - t.height / 2));
    }
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, grid);

    // The price axis.
    final priceStep = _niceStep((hi - lo) / 4);
    var lastRight = -double.infinity;
    for (var p = (lo / priceStep).ceil() * priceStep; p <= hi; p += priceStep) {
      final t = _text(_price(p, priceStep));
      final left = (x(p) - t.width / 2).clamp(0.0, plot.right - t.width);
      if (left < lastRight + 8) continue;
      t.paint(canvas, Offset(left, plot.bottom + 4));
      lastRight = left + t.width;
    }

    // The two sides.
    canvas.save();
    canvas.clipRect(plot);
    _side(canvas, plot, book.bids, bidColor, x, y, edge: plot.left);
    _side(canvas, plot, book.asks, askColor, x, y, edge: plot.right);
    canvas.restore();

    if (showMidPrice) {
      final spread = book.spread;
      final label = spread == null
          ? _price(mid, priceStep / 100)
          : '${_price(mid, priceStep / 100)}  ·  ${_price(spread, priceStep / 100)}';
      final t = _text(label, weight: FontWeight.w600);
      t.paint(canvas, Offset(x(mid) - t.width / 2, 2));
    }

    // The crosshair.
    final cx = crosshairX;
    if (cx != null && cx >= plot.left && cx <= plot.right) {
      final price = priceAt(cx);
      final bid = price <= mid;
      final total = bid ? book.bidTotalAt(price) : book.askTotalAt(price);
      final color = bid ? bidColor : askColor;
      canvas.drawLine(
        Offset(cx, plot.top),
        Offset(cx, plot.bottom),
        Paint()
          ..color = textColor.withValues(alpha: 0.6)
          ..strokeWidth = 1,
      );
      final dot = Offset(cx, y(total));
      canvas.drawCircle(dot, 4, Paint()..color = color);
      final tip = _text('${_price(price, priceStep / 100)}  ${_size(total)}', color: const Color(0xFFFFFFFF));
      final box = Rect.fromLTWH(
        (cx + 8 + tip.width + 12 > plot.right ? cx - 8 - tip.width - 12 : cx + 8),
        (dot.dy - tip.height - 14).clamp(plot.top, plot.bottom - tip.height - 8),
        tip.width + 12,
        tip.height + 8,
      );
      canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(4)), Paint()..color = color);
      tip.paint(canvas, box.topLeft + const Offset(6, 4));
    }
  }

  /// A side as steps from its best price out to [edge], filled down to 0.
  void _side(
    Canvas canvas,
    Rect plot,
    List<(double, double)> levels,
    Color color,
    double Function(double) x,
    double Function(double) y, {
    required double edge,
  }) {
    if (levels.isEmpty) return;
    final line = Path()..moveTo(x(levels.first.$1), y(0));
    var last = 0.0;
    for (final (p, t) in levels) {
      final xx = x(p);
      line
        ..lineTo(xx, y(last))
        ..lineTo(xx, y(t));
      last = t;
      // Past the edge the rest is clipped anyway.
      if (xx < plot.left || xx > plot.right) break;
    }
    line.lineTo(edge, y(last));
    final area = Path.from(line)
      ..lineTo(edge, y(0))
      ..close();
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: areaOpacity));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = lineWidth
        ..strokeJoin = StrokeJoin.miter,
    );
  }

  String _price(double v, double step) {
    final f = priceFormatter;
    if (f != null) return f(v);
    final decimals = step >= 1 ? 0 : math.min(8, (-math.log(step) / math.ln10).ceil());
    return v.toStringAsFixed(decimals);
  }

  String _size(double v) {
    final f = sizeFormatter;
    if (f != null) return f(v);
    final a = v.abs();
    String trim(double n) => n.toStringAsFixed(n < 10 ? 2 : (n < 100 ? 1 : 0)).replaceFirst(RegExp(r'\.?0+$'), '');
    if (a >= 1e9) return '${trim(v / 1e9)}B';
    if (a >= 1e6) return '${trim(v / 1e6)}M';
    if (a >= 1e3) return '${trim(v / 1e3)}K';
    return trim(v);
  }

  /// 1, 2 or 5 times a power of ten, at least [raw].
  static double _niceStep(double raw) {
    if (raw <= 0 || !raw.isFinite) return 1;
    final p = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final m = raw / p;
    return p * (m <= 1 ? 1 : (m <= 2 ? 2 : (m <= 5 ? 5 : 10)));
  }

  @override
  bool shouldRepaint(DepthChartPainter old) =>
      old.book != book ||
      old.crosshairX != crosshairX ||
      old.range != range ||
      old.bidColor != bidColor ||
      old.askColor != askColor ||
      old.areaOpacity != areaOpacity ||
      old.lineWidth != lineWidth ||
      old.textColor != textColor ||
      old.gridColor != gridColor ||
      old.fontSize != fontSize ||
      old.showMidPrice != showMidPrice;
}
