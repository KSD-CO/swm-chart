// Dart counterpart of lightweight-charts' custom series
// (ICustomSeriesPaneView / ICustomSeriesPaneRenderer).
import 'dart:ui';

import 'package:flutter/services.dart' show MouseCursor;

import '../data.dart';
import '../series_options.dart';

/// A visible bar of a custom series.
class CustomBarItem<T extends SeriesData> {
  const CustomBarItem({required this.x, required this.index, required this.data});

  /// Center of the bar in logical pixels.
  final double x;

  /// Logical index on the time scale.
  final int index;
  final T data;
}

/// What a custom series view gets to draw one frame.
class CustomSeriesDrawContext<T extends SeriesData> {
  const CustomSeriesDrawContext({
    required this.canvas,
    required this.paneSize,
    required this.pixelRatio,
    required this.barSpacing,
    required this.bars,
    required this.options,
    required this.priceToCoordinate,
  });

  /// Logical pixels, origin at the pane's top-left, clipped to the pane.
  final Canvas canvas;
  final Size paneSize;
  final double pixelRatio;
  final double barSpacing;

  /// Visible bars plus one on each side.
  final List<CustomBarItem<T>> bars;
  final CustomSeriesOptions options;

  /// Y of a price on the series' price scale.
  final double Function(double price) priceToCoordinate;
}

/// An item passed to [CustomSeriesView.conflationReducer].
class CustomConflationContext<T extends SeriesData> {
  const CustomConflationContext({required this.data, required this.index, required this.priceValues});

  final T data;

  /// Logical index of the item (of the first merged item for conflated ones).
  final int index;

  /// [CustomSeriesView.priceValues] of [data].
  final List<double> priceValues;

  num get time => data.time;
}

/// Result of [CustomSeriesView.hitTest], like `CustomSeriesHitTestResult`.
class CustomSeriesHitTestResult {
  const CustomSeriesHitTestResult({required this.distance, this.objectId, this.cursor});

  /// Mouse cursor while hovering it (desktop/web); `null` keeps the default.
  final MouseCursor? cursor;

  /// Distance from the pointer in logical pixels; closer hits win.
  final double distance;

  /// Reported as `hoveredObjectId` (objectKind `customObject`).
  final Object? objectId;
}

/// Defines how a custom series is drawn, like upstream's
/// `ICustomSeriesPaneView`. Add it with `ChartController.addCustomSeries`.
abstract class CustomSeriesView<T extends SeriesData> {
  /// Prices of [item] used for autoscale; the **last** one is the current
  /// value (last value label, price line, crosshair magnet).
  List<double> priceValues(T item);

  /// Whether [item] has no value and should be treated as whitespace.
  bool isWhitespace(T item) => false;

  void draw(CustomSeriesDrawContext<T> ctx);

  /// Merges two consecutive items into one when the time scale conflates
  /// bars, like upstream's `conflationReducer`. `null` (the default) means
  /// this series is never conflated.
  T Function(CustomConflationContext<T> a, CustomConflationContext<T> b)? get conflationReducer => null;

  /// Whether the series is under ([x], [y]) (pane coordinates). `null`
  /// (the default) means not hit.
  CustomSeriesHitTestResult? hitTest(CustomSeriesDrawContext<T> ctx, double x, double y) => null;
}
