// Port of lightweight-charts src/plugins/series-markers.
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/painting.dart';

import '../api/chart_controller.dart';
import '../data.dart';
import '../series_options.dart';
import 'primitive.dart';

enum SeriesMarkerPosition {
  aboveBar,
  belowBar,
  inBar,

  /// At [SeriesMarker.price], the shape's top touching the price.
  atPriceTop,

  /// At [SeriesMarker.price], the shape's bottom touching the price.
  atPriceBottom,

  /// Centered on [SeriesMarker.price].
  atPriceMiddle,
}

enum SeriesMarkerShape { circle, square, arrowUp, arrowDown }

class SeriesMarker {
  const SeriesMarker({
    required this.time,
    required this.position,
    required this.shape,
    required this.color,
    this.text,
    this.size = 1,
    this.price,
    this.id,
  });

  /// Time of the bar the marker belongs to.
  final num time;
  final SeriesMarkerPosition position;
  final SeriesMarkerShape shape;
  final Color color;
  final String? text;

  /// Size multiplier.
  final double size;

  /// Required for the `atPrice*` positions.
  final double? price;
  final String? id;

  bool get _isPriceMarker =>
      position == SeriesMarkerPosition.atPriceTop ||
      position == SeriesMarkerPosition.atPriceBottom ||
      position == SeriesMarkerPosition.atPriceMiddle;
}

const double _minShapeSize = 12;
const double _maxShapeSize = 30;
const double _minShapeMargin = 3;
const double _textMargin = 0.1;

int _ceiledEven(double x) {
  final c = x.ceil();
  return c.isOdd ? c - 1 : c;
}

int _ceiledOdd(double x) {
  final c = x.ceil();
  return c.isEven ? c - 1 : c;
}

int _size(double barSpacing, double coeff) =>
    _ceiledOdd(math.min(math.max(barSpacing, _minShapeSize), _maxShapeSize) * coeff);

int _shapeSize(SeriesMarkerShape shape, double originalSize) {
  final coeff = switch (shape) {
    SeriesMarkerShape.circle => 0.8,
    SeriesMarkerShape.square => 0.7,
    _ => 1.0,
  };
  return _ceiledOdd(math.max(originalSize, _minShapeSize) * coeff);
}

int _calculateShapeHeight(double barSpacing) => _ceiledEven(_size(barSpacing, 1).toDouble());

double _shapeMargin(double barSpacing) => math.max(_size(barSpacing, 0.1).toDouble(), _minShapeMargin);

/// Draws markers on a series. Create with [createSeriesMarkers].
class SeriesMarkersPrimitive extends ChartPrimitive {
  SeriesMarkersPrimitive(List<SeriesMarker> markers, {this.autoscale = true}) {
    setMarkers(markers);
  }

  List<SeriesMarker> _markers = const [];

  /// Shapes drawn in the last frame, for [hitTest].
  final List<(Rect, SeriesMarker)> _drawn = [];

  /// Reserve room above/below the data so markers stay visible.
  bool autoscale;

  List<SeriesMarker> get markers => _markers;

  void setMarkers(List<SeriesMarker> markers) {
    _markers = List.of(markers)..sort((a, b) => a.time.compareTo(b.time));
    requestUpdate();
  }

  @override
  AutoscaleInfo? autoscaleInfo(int from, int to) {
    if (!autoscale || _markers.isEmpty) return null;
    final barSpacing = host?.barSpacing ?? 6;
    var aboveBar = false, belowBar = false, inBar = false;
    for (final m in _markers) {
      switch (m.position) {
        case SeriesMarkerPosition.aboveBar:
          aboveBar = true;
        case SeriesMarkerPosition.belowBar:
          belowBar = true;
        case SeriesMarkerPosition.inBar:
          inBar = true;
        default:
          break;
      }
    }
    final margin = _calculateShapeHeight(barSpacing) * 1.5 + _shapeMargin(barSpacing) * 2;
    double adjusted(bool side) => side ? margin : (inBar ? (margin / 2).ceilToDouble() : 0);
    return AutoscaleInfo(
      margins: AutoscaleMargins(above: adjusted(aboveBar), below: adjusted(belowBar)),
    );
  }

  /// Center Y of the first marker drawn in the last frame (tests only).
  @visibleForTesting
  double? get hitTestCenterForTest => _drawn.isEmpty ? null : _drawn.first.$1.center.dy;

  @override
  PrimitiveHitTestResult? hitTest(PrimitiveContext ctx, double x, double y) {
    PrimitiveHitTestResult? best;
    for (final (rect, marker) in _drawn) {
      if (!rect.inflate(2).contains(Offset(x, y))) continue;
      final distance = (rect.center - Offset(x, y)).distance;
      if (best == null || distance < best.distance) {
        best = PrimitiveHitTestResult(
          externalId: marker.id ?? marker,
          distance: distance,
          itemType: PrimitiveItemType.marker,
        );
      }
    }
    return best;
  }

  @override
  void paint(PrimitivePaintContext ctx) {
    _drawn.clear();
    final range = ctx.visibleLogicalRange;
    if (range == null || _markers.isEmpty) return;
    final from = range.from.floor(), to = range.to.ceil();
    final barSpacing = ctx.barSpacing;
    final shapeMargin = _shapeMargin(barSpacing);
    final textHeight = ctx.fontSize;

    int? prevIndex;
    var aboveOffset = shapeMargin, belowOffset = shapeMargin;
    for (final m in _markers) {
      final index = ctx.timeToIndex(m.time);
      if (index == null || index < from || index > to) continue;
      if (index != prevIndex) {
        // New bar: reset the stacking offsets.
        aboveOffset = shapeMargin;
        belowOffset = shapeMargin;
        prevIndex = index;
      }
      final data = ctx.seriesDataAt(index);
      if (data == null) continue;
      final price = _priceFor(m, data, ctx.priceScaleInverted);
      if (price == null) continue;
      final priceY = ctx.priceToCoordinate(price);
      if (priceY == null) continue;

      final shapeSize = _calculateShapeHeight(barSpacing) * math.max(m.size, 0);
      final halfSize = shapeSize / 2;
      final hasText = m.text != null && m.text!.isNotEmpty;
      final ignoreOffset = m._isPriceMarker;
      double y;
      double? textY;
      switch (m.position) {
        case SeriesMarkerPosition.inBar:
        case SeriesMarkerPosition.atPriceMiddle:
          y = priceY;
          if (hasText) textY = y + halfSize + shapeMargin + textHeight * (0.5 + _textMargin);
        case SeriesMarkerPosition.aboveBar:
        case SeriesMarkerPosition.atPriceTop:
          y = priceY - halfSize - (ignoreOffset ? 0 : aboveOffset);
          if (hasText) {
            textY = y - halfSize - textHeight * (0.5 + _textMargin);
            aboveOffset += textHeight * (1 + 2 * _textMargin);
          }
          if (!ignoreOffset) aboveOffset += shapeSize + shapeMargin;
        case SeriesMarkerPosition.belowBar:
        case SeriesMarkerPosition.atPriceBottom:
          y = priceY + halfSize + (ignoreOffset ? 0 : belowOffset);
          if (hasText) {
            textY = y + halfSize + shapeMargin + textHeight * (0.5 + _textMargin);
            belowOffset += textHeight * (1 + 2 * _textMargin);
          }
          if (!ignoreOffset) belowOffset += shapeSize + shapeMargin;
      }

      final x = ctx.logicalToCoordinate(index.toDouble());
      _drawShape(ctx.canvas, m.shape, x, y, shapeSize.toDouble(), m.color);
      _drawn.add((Rect.fromCenter(center: Offset(x, y), width: shapeSize.toDouble(), height: shapeSize.toDouble()), m));
      if (textY != null) {
        final tp = TextPainter(
          text: TextSpan(
            text: m.text,
            style: TextStyle(color: m.color, fontSize: ctx.fontSize, fontFamily: ctx.fontFamily, height: 1),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(ctx.canvas, Offset(x - tp.width / 2, textY - tp.height / 2));
        tp.dispose();
      }
    }
  }

  double? _priceFor(SeriesMarker m, SeriesData data, bool inverted) {
    if (m._isPriceMarker && m.price != null) return m.price;
    if (data is SingleValueData) return data.value;
    if (data is OhlcData) {
      switch (m.position) {
        case SeriesMarkerPosition.inBar:
          return data.close;
        case SeriesMarkerPosition.aboveBar:
          return inverted ? data.low : data.high;
        case SeriesMarkerPosition.belowBar:
          return inverted ? data.high : data.low;
        default:
          return null;
      }
    }
    return null;
  }

  void _drawShape(Canvas canvas, SeriesMarkerShape shape, double x, double y, double size, Color color) {
    final paint = Paint()..color = color;
    switch (shape) {
      case SeriesMarkerShape.circle:
        final s = _shapeSize(shape, size);
        canvas.drawCircle(Offset(x, y), (s - 1) / 2, paint);
      case SeriesMarkerShape.square:
        final s = _shapeSize(shape, size).toDouble();
        canvas.drawRect(Rect.fromCenter(center: Offset(x, y), width: s - 1, height: s - 1), paint);
      case SeriesMarkerShape.arrowUp:
      case SeriesMarkerShape.arrowDown:
        final up = shape == SeriesMarkerShape.arrowUp;
        final halfArrow = (_shapeSize(shape, size) - 1) / 2;
        final halfBase = (_ceiledOdd(size / 2) - 1) / 2;
        final dir = up ? -1 : 1;
        final path = Path()
          ..moveTo(x - halfArrow, y)
          ..lineTo(x, y + dir * halfArrow)
          ..lineTo(x + halfArrow, y)
          ..lineTo(x + halfBase, y)
          ..lineTo(x + halfBase, y - dir * halfArrow)
          ..lineTo(x - halfBase, y - dir * halfArrow)
          ..lineTo(x - halfBase, y)
          ..close();
        canvas.drawPath(path, paint);
    }
  }
}

/// Handle returned by [createSeriesMarkers].
class SeriesMarkersPlugin {
  SeriesMarkersPlugin._(this._series, this.primitive);

  final SeriesApi _series;
  final SeriesMarkersPrimitive primitive;

  List<SeriesMarker> markers() => primitive.markers;

  void setMarkers(List<SeriesMarker> markers) => primitive.setMarkers(markers);

  /// Removes the markers from the series.
  void detach() => _series.detachPrimitive(primitive);
}

/// Adds markers to [series], like lightweight-charts' `createSeriesMarkers`.
SeriesMarkersPlugin createSeriesMarkers(SeriesApi series, [List<SeriesMarker> markers = const []]) {
  final primitive = SeriesMarkersPrimitive(markers);
  series.attachPrimitive(primitive);
  return SeriesMarkersPlugin._(series, primitive);
}
