// Dart counterpart of lightweight-charts' primitives API
// (ISeriesPrimitive / IPanePrimitive).
import 'dart:ui';

import '../data.dart';
import '../model/time_scale.dart';
import '../series_options.dart';

/// Where a primitive is drawn relative to the series.
enum PrimitiveZOrder {
  /// Above the grid, below the series.
  bottom,

  /// Above the series' own drawing.
  normal,

  /// Above everything, including the crosshair.
  top,
}

/// A label a primitive draws on the price or time axis.
class AxisLabel {
  const AxisLabel({
    required this.coordinate,
    required this.text,
    required this.backgroundColor,
    this.textColor,
  });

  /// Y coordinate in the pane (price axis) or X coordinate (time axis), in
  /// logical pixels.
  final double coordinate;
  final String text;
  final Color backgroundColor;

  /// `null` picks black or white for contrast.
  final Color? textColor;
}

/// What a primitive hit is, like upstream's `PrimitiveHoveredItem.itemType`.
enum PrimitiveItemType { marker, primitive }

/// Result of [ChartPrimitive.hitTest], like upstream's `PrimitiveHoveredItem`.
class PrimitiveHitTestResult {
  const PrimitiveHitTestResult({
    required this.externalId,
    this.zOrder = PrimitiveZOrder.normal,
    this.distance = 0,
    this.hitTestPriority,
    this.itemType = PrimitiveItemType.primitive,
  });

  /// Among hits on the same z-order: 0 for ranges, 1 for lines, 2 for
  /// points (higher wins). `null` counts as a point.
  final int? hitTestPriority;

  final PrimitiveItemType itemType;

  /// Reported as `hoveredObjectId` in chart events.
  final Object? externalId;
  final PrimitiveZOrder zOrder;

  /// Distance from the pointer in logical pixels; closer hits win.
  final double distance;
}

/// Coordinate helpers available to a primitive for the current frame.
abstract class PrimitiveContext {
  Size get paneSize;

  double get pixelRatio;

  double get barSpacing;

  /// Visible logical range, `null` when there is no data.
  LogicalRange? get visibleLogicalRange;

  double get fontSize;

  String? get fontFamily;

  Color get textColor;

  Color get backgroundColor;

  /// X of a bar time, `null` when the time isn't on the time scale.
  double? timeToCoordinate(num time);

  /// X of a logical index (may be fractional).
  double logicalToCoordinate(double logical);

  /// Logical index of a time, `null` when the time isn't on the time scale.
  int? timeToIndex(num time);

  /// Y of a price on the series' price scale (series primitives) or the
  /// pane's default price scale (pane primitives).
  double? priceToCoordinate(double price);

  /// Whether the price scale used by [priceToCoordinate] is inverted.
  bool get priceScaleInverted;

  /// Data of the series at a logical index (series primitives only).
  SeriesData? seriesDataAt(int index);
}

/// What a primitive gets to draw one frame.
///
/// [canvas] is in logical pixels with the origin at the top-left of the
/// pane and is clipped to it. Use [pixelRatio] to align to device pixels.
abstract class PrimitivePaintContext implements PrimitiveContext {
  Canvas get canvas;
}

/// Services a primitive gets once attached.
abstract class PrimitiveHost {
  /// Repaints the chart.
  void requestUpdate();

  double get barSpacing;
}

/// Base class of series and pane primitives (plugins).
///
/// Override only what you need. Attach with `SeriesApi.attachPrimitive` or
/// `PaneApi.attachPrimitive`.
abstract class ChartPrimitive {
  PrimitiveHost? _host;

  /// The host while attached.
  PrimitiveHost? get host => _host;

  void attached(PrimitiveHost host) => _host = host;

  void detached() => _host = null;

  /// Asks the chart to repaint.
  void requestUpdate() => _host?.requestUpdate();

  PrimitiveZOrder get zOrder => PrimitiveZOrder.normal;

  void paint(PrimitivePaintContext ctx) {}

  List<AxisLabel> priceAxisLabels(PrimitiveContext ctx) => const [];

  List<AxisLabel> timeAxisLabels(PrimitiveContext ctx) => const [];

  /// Whether the primitive is under ([x], [y]) (pane coordinates). Return
  /// `null` when it is not.
  PrimitiveHitTestResult? hitTest(PrimitiveContext ctx, double x, double y) => null;

  /// Extra autoscale info (series primitives only). [from] and [to] are the
  /// visible logical indices.
  AutoscaleInfo? autoscaleInfo(int from, int to) => null;
}
