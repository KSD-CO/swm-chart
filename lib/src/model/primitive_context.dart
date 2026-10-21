import 'dart:ui';

import '../data.dart';
import '../plugins/primitive.dart';
import 'chart_model.dart';
import 'pane.dart';
import 'series.dart';
import 'time_scale.dart';

/// [PrimitiveContext] for a pane, or for a series when [series] is set.
class PrimitiveContextImpl implements PrimitivePaintContext {
  PrimitiveContextImpl(this.model, this.pane, this.series, [this._canvas]);

  final ChartModel model;
  final Pane pane;
  final SeriesModel? series;
  final Canvas? _canvas;

  @override
  Canvas get canvas => _canvas!;

  @override
  Size get paneSize => Size(model.paneWidth, pane.height);

  @override
  double get pixelRatio => model.pixelRatio;

  @override
  double get barSpacing => model.timeScale.barSpacing;

  @override
  LogicalRange? get visibleLogicalRange => model.timeScale.visibleLogicalRange();

  @override
  double get fontSize => model.options.layout.fontSize;

  @override
  String? get fontFamily => model.options.layout.fontFamily;

  @override
  Color get textColor => model.options.layout.textColor;

  @override
  Color get backgroundColor => model.options.layout.backgroundColor;

  @override
  double? timeToCoordinate(num time) {
    final index = model.timeScale.timeToIndex(time);
    return index == null ? null : model.timeScale.indexToCoordinate(index);
  }

  @override
  double logicalToCoordinate(double logical) => model.timeScale.indexToCoordinate(logical);

  @override
  int? timeToIndex(num time) => model.timeScale.timeToIndex(time);

  @override
  double? priceToCoordinate(double price) {
    final s = series;
    if (s != null) return s.priceScale.isEmpty ? null : s.priceToCoordinate(price);
    final ps = pane.defaultPriceScale;
    return ps.isEmpty ? null : ps.priceToCoordinate(price);
  }

  @override
  bool get priceScaleInverted => (series?.priceScale ?? pane.defaultPriceScale).isInverted;

  @override
  SeriesData? seriesDataAt(int index) => series?.itemAt(index);
}
