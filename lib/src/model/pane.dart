// Port of the layout-related parts of lightweight-charts src/model/pane.ts
import '../options.dart';
import '../plugins/primitive.dart';
import 'price_scale.dart';
import 'series.dart';

const String rightPriceScaleId = 'right';
const String leftPriceScaleId = 'left';

/// Minimum pane height while resizing with the separator, like upstream.
const double minPaneHeight = 30;

/// Height of the separator between panes.
const double paneSeparatorHeight = 1;

class Pane {
  Pane(ChartOptions options, {this.preserveEmpty = false}) {
    priceScales[rightPriceScaleId] = PriceScale(rightPriceScaleId, options.rightPriceScale);
    priceScales[leftPriceScaleId] = PriceScale(leftPriceScaleId, options.leftPriceScale);
  }

  final Map<String, PriceScale> priceScales = {};
  final List<SeriesModel> series = [];
  final List<ChartPrimitive> primitives = [];

  /// Keep the pane when its last series is removed.
  bool preserveEmpty;

  double stretchFactor = 1;

  /// Layout, in logical pixels relative to the chart.
  double top = 0;
  double height = 0;

  PriceScale get rightScale => priceScales[rightPriceScaleId]!;

  PriceScale get leftScale => priceScales[leftPriceScaleId]!;

  bool isOverlay(PriceScale scale) => scale != rightScale && scale != leftScale;

  PriceScale priceScale(String id, ChartOptions options) =>
      priceScales.putIfAbsent(id, () => PriceScale(id, options.overlayPriceScales.copyWith(visible: false)));

  bool _hasSeriesOn(PriceScale scale) => series.any((s) => s.priceScale == scale);

  /// Scale used for the grid, crosshair label and magnet: the right scale
  /// unless only the left one has series.
  PriceScale get defaultPriceScale {
    if (!_hasSeriesOn(rightScale) && _hasSeriesOn(leftScale)) return leftScale;
    return rightScale;
  }

  void applyChartOptions(ChartOptions options) {
    rightScale.options = options.rightPriceScale;
    leftScale.options = options.leftPriceScale;
  }
}
