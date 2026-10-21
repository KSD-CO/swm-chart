import 'dart:ui';

import '../model/time_scale.dart';

/// Everything a series renderer needs for one frame.
///
/// [canvas] is in *bitmap* coordinates (1 unit = 1 physical pixel) with the
/// origin at the top-left of the pane, mirroring lightweight-charts'
/// `BitmapCoordinatesRenderingScope`. Model coordinates are in logical pixels
/// and must be multiplied by [pixelRatio].
class SeriesPaintContext {
  const SeriesPaintContext({
    required this.canvas,
    required this.pixelRatio,
    required this.timeScale,
    required this.visibleRange,
    required this.paneSize,
    required this.backgroundColor,
    this.conflationFactor = 1,
  });

  /// Bars merged per drawn item (1 = none).
  final int conflationFactor;

  SeriesPaintContext withConflationFactor(int factor) => SeriesPaintContext(
        canvas: canvas,
        pixelRatio: pixelRatio,
        timeScale: timeScale,
        visibleRange: visibleRange,
        paneSize: paneSize,
        backgroundColor: backgroundColor,
        conflationFactor: factor,
      );

  final Canvas canvas;
  final double pixelRatio;
  final TimeScale timeScale;
  final IndexRange visibleRange;
  final Size paneSize;
  final Color backgroundColor;
}
