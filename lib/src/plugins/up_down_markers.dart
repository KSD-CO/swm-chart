// Port of lightweight-charts src/plugins/up-down-markers-plugin: a dot on
// the point whose value changed, with an arrow showing the direction,
// fading out after `updateVisibilityDuration`.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import '../api/chart_controller.dart';
import '../data.dart';
import '../series_options.dart';
import 'primitive.dart';

enum MarkerSign { negative, neutral, positive }

class SeriesUpDownMarker {
  const SeriesUpDownMarker({required this.time, required this.value, required this.sign});

  final num time;
  final double value;
  final MarkerSign sign;
}

class UpDownMarkersOptions {
  const UpDownMarkersOptions({
    this.positiveColor = const Color(0xFF22AB94),
    this.negativeColor = const Color(0xFFF7525F),
    this.updateVisibilityDuration = const Duration(seconds: 5),
  });

  final Color positiveColor;
  final Color negativeColor;

  /// How long a marker created by [UpDownMarkersPlugin.update] stays.
  final Duration updateVisibilityDuration;
}

const double _radius = 4;
const double _arrowSize = 4.7;
const double _arrowOffset = 7;
const double _arrowLineWidth = 2;
const double _verticalScale = 0.5;

class UpDownMarkersPrimitive extends ChartPrimitive {
  UpDownMarkersPrimitive(this._options, this._neutralColor);

  UpDownMarkersOptions _options;
  final Color Function() _neutralColor;
  final Map<num, (SeriesUpDownMarker, Timer?)> _markers = {};

  UpDownMarkersOptions get options => _options;

  set options(UpDownMarkersOptions value) {
    _options = value;
    requestUpdate();
  }

  List<SeriesUpDownMarker> get markers => [for (final m in _markers.values) m.$1];

  void setMarker(SeriesUpDownMarker marker, [Duration? timeout]) {
    clearMarker(marker.time, update: false);
    final timer = timeout == null
        ? null
        : Timer(timeout, () {
            _markers.remove(marker.time);
            requestUpdate();
          });
    _markers[marker.time] = (marker, timer);
    requestUpdate();
  }

  void clearMarker(num time, {bool update = true}) {
    _markers.remove(time)?.$2?.cancel();
    if (update) requestUpdate();
  }

  void clearAll() {
    for (final m in _markers.values) {
      m.$2?.cancel();
    }
    _markers.clear();
    requestUpdate();
  }

  @override
  void detached() {
    clearAll();
    super.detached();
  }

  Color _color(MarkerSign sign) => switch (sign) {
    MarkerSign.positive => _options.positiveColor,
    MarkerSign.negative => _options.negativeColor,
    MarkerSign.neutral => _neutralColor(),
  };

  @override
  void paint(PrimitivePaintContext ctx) {
    final pr = ctx.pixelRatio;
    final tickWidth = math.max(1, pr.floor());
    final correction = (tickWidth % 2) / 2 / pr;
    final canvas = ctx.canvas;
    for (final (marker, _) in _markers.values) {
      final x = ctx.timeToCoordinate(marker.time);
      final y = ctx.priceToCoordinate(marker.value);
      if (x == null || y == null) continue;
      final cx = (x * pr).round() / pr + correction;
      final color = _color(marker.sign);
      canvas.drawCircle(Offset(cx, y), _radius + correction, Paint()..color = color);
      if (marker.sign == MarkerSign.neutral) continue;
      final sign = marker.sign == MarkerSign.positive ? 1 : -1;
      final path = Path()
        ..moveTo(cx - _arrowSize, y - _arrowOffset * sign)
        ..lineTo(cx, y - _arrowOffset * sign - _arrowOffset * sign * _verticalScale)
        ..lineTo(cx + _arrowSize, y - _arrowOffset * sign);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = color
          ..strokeWidth = (_arrowLineWidth * pr).floorToDouble() / pr,
      );
    }
  }
}

/// Handle returned by [createUpDownMarkers]. Feed data through it so it can
/// compare new values with old ones.
class UpDownMarkersPlugin<T extends SingleValueData, O extends LineLikeSeriesOptions> {
  UpDownMarkersPlugin._(this._series, this.primitive);

  final SeriesApi<T, O> _series;
  final UpDownMarkersPrimitive primitive;
  final Map<num, double> _values = {};

  List<SeriesUpDownMarker> markers() => primitive.markers;

  /// Shows [markers] until cleared.
  void setMarkers(List<SeriesUpDownMarker> markers) {
    primitive.clearAll();
    for (final m in markers) {
      primitive.setMarker(m);
    }
  }

  void clearMarkers() => primitive.clearAll();

  void applyOptions(UpDownMarkersOptions options) => primitive.options = options;

  /// Sets the series data and remembers the values for comparison.
  void setData(List<SeriesData> data) {
    _values
      ..clear()
      ..addEntries([
        for (final d in data)
          if (d is SingleValueData) MapEntry(d.time, d.value),
      ]);
    _series.setData(data);
  }

  /// Updates the series; when an existing point's value changes, shows a
  /// marker for `updateVisibilityDuration`.
  void update(SeriesData item) {
    if (item is WhitespaceData) _values.remove(item.time);
    if (item is SingleValueData) {
      final previous = _values[item.time];
      if (previous != null) {
        final sign = item.value == previous
            ? MarkerSign.neutral
            : (item.value > previous ? MarkerSign.positive : MarkerSign.negative);
        primitive.setMarker(
          SeriesUpDownMarker(time: item.time, value: item.value, sign: sign),
          primitive.options.updateVisibilityDuration,
        );
      }
      _values[item.time] = item.value;
    }
    _series.update(item);
  }

  void detach() => _series.detachPrimitive(primitive);
}

/// Up/down markers for a line or area series, like upstream's
/// `createUpDownMarkers`.
UpDownMarkersPlugin<T, O> createUpDownMarkers<T extends SingleValueData, O extends LineLikeSeriesOptions>(
  SeriesApi<T, O> series, [
  UpDownMarkersOptions options = const UpDownMarkersOptions(),
]) {
  final type = series.seriesType();
  if (type != SeriesType.line && type != SeriesType.area) {
    throw UnsupportedError('Up/down markers are only supported for line and area series');
  }
  final primitive = UpDownMarkersPrimitive(options, () {
    final o = series.options;
    return o is LineSeriesOptions ? o.color : (o as AreaSeriesOptions).lineColor;
  });
  series.attachPrimitive(primitive);
  return UpDownMarkersPlugin._(series, primitive);
}
