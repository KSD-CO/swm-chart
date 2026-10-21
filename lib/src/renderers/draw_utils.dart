// Port of lightweight-charts src/renderers/draw-line.ts helpers.
import 'dart:typed_data';
import 'dart:ui';

import '../options.dart';

List<double> dashPattern(LineStyle style, double lineWidth) {
  switch (style) {
    case LineStyle.solid:
      return const [];
    case LineStyle.dotted:
      return [lineWidth, lineWidth];
    case LineStyle.dashed:
      return [2 * lineWidth, 2 * lineWidth];
    case LineStyle.largeDashed:
      return [6 * lineWidth, 6 * lineWidth];
    case LineStyle.sparseDotted:
      return [lineWidth, 4 * lineWidth];
  }
}

/// Horizontal line in bitmap coordinates. [width] is in physical pixels.
void drawHorizontalLine(
  Canvas canvas,
  Paint paint,
  double y,
  double left,
  double right,
  double width,
  LineStyle style,
) {
  final correction = (width.round() % 2 == 1) ? 0.5 : 0.0;
  final yy = y + correction;
  paint
    ..strokeWidth = width
    ..style = PaintingStyle.stroke;
  final dash = dashPattern(style, width);
  if (dash.isEmpty) {
    canvas.drawLine(Offset(left, yy), Offset(right, yy), paint);
    return;
  }
  for (var x = left, i = 0; x < right; i++) {
    final len = dash[i % dash.length];
    if (i.isEven) {
      canvas.drawLine(Offset(x, yy), Offset((x + len).clamp(left, right), yy), paint);
    }
    x += len;
  }
}

/// Vertical line in bitmap coordinates. [width] is in physical pixels.
void drawVerticalLine(
  Canvas canvas,
  Paint paint,
  double x,
  double top,
  double bottom,
  double width,
  LineStyle style,
) {
  final correction = (width.round() % 2 == 1) ? 0.5 : 0.0;
  final xx = x + correction;
  paint
    ..strokeWidth = width
    ..style = PaintingStyle.stroke;
  final dash = dashPattern(style, width);
  if (dash.isEmpty) {
    canvas.drawLine(Offset(xx, top), Offset(xx, bottom), paint);
    return;
  }
  for (var y = top, i = 0; y < bottom; i++) {
    final len = dash[i % dash.length];
    if (i.isEven) {
      canvas.drawLine(Offset(xx, y), Offset(xx, (y + len).clamp(top, bottom)), paint);
    }
    y += len;
  }
}

/// Returns [path] cut into dashes.
Path dashPath(Path path, List<double> pattern) {
  if (pattern.isEmpty) return path;
  final result = Path();
  for (final metric in path.computeMetrics()) {
    var distance = 0.0;
    var i = 0;
    while (distance < metric.length) {
      final len = pattern[i % pattern.length];
      if (i.isEven) {
        result.addPath(metric.extractPath(distance, distance + len), Offset.zero);
      }
      distance += len;
      i++;
    }
  }
  return result;
}

/// `fillRect` with integer bitmap coordinates, like CanvasRenderingContext2D.
void fillRect(Canvas canvas, Paint paint, double x, double y, double w, double h) {
  if (w <= 0 || h <= 0) return;
  canvas.drawRect(Rect.fromLTWH(x, y, w, h), paint);
}

void fillRectInnerBorder(Canvas canvas, Paint paint, double x, double y, double width, double height, double borderWidth) {
  fillRect(canvas, paint, x + borderWidth, y, width - borderWidth * 2, borderWidth);
  fillRect(canvas, paint, x + borderWidth, y + height - borderWidth, width - borderWidth * 2, borderWidth);
  fillRect(canvas, paint, x, y, borderWidth, height);
  fillRect(canvas, paint, x + width - borderWidth, y, borderWidth, height);
}

/// Collects axis-aligned rectangles with per-rectangle colors and draws
/// them in a single `drawVertices` call. Drawing 100k candles as separate
/// `drawRect` calls costs over a second of raster time; one vertex batch
/// costs a few milliseconds. Rectangles are drawn in insertion order.
class RectBatch {
  RectBatch._();

  /// Shared buffer: painting is single-threaded, so one batch is reused
  /// for every series to avoid allocations per frame.
  static final RectBatch shared = RectBatch._();

  Float32List _positions = Float32List(12 * 1024);
  Int32List _colors = Int32List(6 * 1024);
  int _count = 0;

  bool get isEmpty => _count == 0;

  int get count => _count;

  /// Starts a batch with room for [expected] rectangles, so [add] doesn't
  /// have to grow the buffers one rectangle at a time.
  void reset([int expected = 0]) {
    _count = 0;
    _ensureCapacity(expected);
  }

  void _ensureCapacity(int rects) {
    if (rects * 12 <= _positions.length) return;
    var capacity = _positions.length ~/ 12;
    while (capacity < rects) {
      capacity *= 2;
    }
    _positions = Float32List(capacity * 12)..setRange(0, _count * 12, _positions);
    _colors = Int32List(capacity * 6)..setRange(0, _count * 6, _colors);
  }

  /// Adds a rectangle in bitmap coordinates, like `fillRect`.
  ///
  /// When the previous rectangle has the same column, the same opaque color
  /// and touches this one vertically, it is extended instead: painting an
  /// opaque color twice gives the same pixels, and at small bar spacings
  /// thousands of candles share a column.
  void add(double x, double y, double w, double h, int argb) {
    if (w <= 0 || h <= 0) return;
    // Int32List stores colors signed; compare and store in the same form.
    final color = argb.toSigned(32);
    final p = _positions;
    final bottom = y + h;
    if (_count > 0 && (color >> 24) & 0xFF == 0xFF) {
      final i = (_count - 1) * 12;
      if (p[i] == x && p[i + 2] == x + w && _colors[(_count - 1) * 6] == color) {
        final top0 = p[i + 1], bottom0 = p[i + 5];
        if (y <= bottom0 && bottom >= top0) {
          final top = y < top0 ? y : top0;
          final b = bottom > bottom0 ? bottom : bottom0;
          p[i + 1] = top;
          p[i + 3] = top;
          p[i + 7] = top;
          p[i + 5] = b;
          p[i + 9] = b;
          p[i + 11] = b;
          return;
        }
      }
    }
    if ((_count + 1) * 12 > p.length) _ensureCapacity(_count + 1);
    final pos = _positions;
    final i = _count * 12;
    final right = x + w;
    // Two triangles: (x,y) (r,y) (x,b) and (r,y) (r,b) (x,b).
    pos[i] = x;
    pos[i + 1] = y;
    pos[i + 2] = right;
    pos[i + 3] = y;
    pos[i + 4] = x;
    pos[i + 5] = bottom;
    pos[i + 6] = right;
    pos[i + 7] = y;
    pos[i + 8] = right;
    pos[i + 9] = bottom;
    pos[i + 10] = x;
    pos[i + 11] = bottom;
    final c = _count * 6;
    final colors = _colors;
    colors[c] = color;
    colors[c + 1] = color;
    colors[c + 2] = color;
    colors[c + 3] = color;
    colors[c + 4] = color;
    colors[c + 5] = color;
    _count++;
  }

  void addInnerBorder(double x, double y, double width, double height, double borderWidth, int argb) {
    add(x + borderWidth, y, width - borderWidth * 2, borderWidth, argb);
    add(x + borderWidth, y + height - borderWidth, width - borderWidth * 2, borderWidth, argb);
    add(x, y, borderWidth, height, argb);
    add(x + width - borderWidth, y, borderWidth, height, argb);
  }

  /// Draws and clears the batch.
  void flush(Canvas canvas) {
    if (_count == 0) return;
    final vertices = Vertices.raw(
      VertexMode.triangles,
      Float32List.sublistView(_positions, 0, _count * 12),
      colors: Int32List.sublistView(_colors, 0, _count * 6),
    );
    // BlendMode.dst keeps the vertex colors and ignores the paint's color.
    canvas.drawVertices(vertices, BlendMode.dst, Paint()..isAntiAlias = false);
    vertices.dispose();
    _count = 0;
  }
}
