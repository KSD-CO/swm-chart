import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../api/chart_controller.dart';
import '../model/chart_model.dart';
import '../model/price_scale.dart';
import 'chart_painter.dart';

enum _Region { pane, priceAxis, timeAxis }

enum _DragMode { none, scroll, pinch, priceAxisScale, timeAxisScale }

/// Renders a [ChartController]. Give it bounded constraints (e.g. wrap it in
/// a `SizedBox` or `Expanded`).
///
/// Touch gestures, following lightweight-charts on mobile:
/// * drag the pane to scroll (with kinetic scrolling), pinch to zoom;
/// * long-press then move to track the crosshair; tap to show/hide it;
/// * drag the price axis to scale prices, double-tap it to re-enable auto-scale;
/// * drag the time axis to change bar spacing, double-tap it to reset.
class SwmChart extends StatefulWidget {
  const SwmChart({super.key, required this.controller});

  final ChartController controller;

  @override
  State<SwmChart> createState() => _SwmChartState();
}

class _SwmChartState extends State<SwmChart> with SingleTickerProviderStateMixin {
  final TextCache _textCache = TextCache();
  late final Ticker _kineticTicker = createTicker(_onKineticTick);
  FrictionSimulation? _kinetic;

  _DragMode _mode = _DragMode.none;
  double _pinchStartBarSpacing = 0;
  double _pinchAnchorIndex = 0;
  bool _crosshairPinned = false;

  _Region? _lastTapRegion;
  Duration? _lastTapTime;
  final Stopwatch _clock = Stopwatch()..start();

  ChartModel get _model => widget.controller.model;

  @override
  void didUpdateWidget(SwmChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) _stopKinetic();
  }

  @override
  void dispose() {
    _kineticTicker.dispose();
    _textCache.dispose();
    super.dispose();
  }

  _Region _regionAt(Offset p) {
    final pane = _model.paneSize;
    if (p.dy >= pane.height) return _Region.timeAxis;
    if (p.dx >= pane.width) return _Region.priceAxis;
    return _Region.pane;
  }

  PriceScale get _rightScale => _model.rightPriceScale;

  // ---- pan / pinch / axis drag ----

  void _onScaleStart(ScaleStartDetails d) {
    _stopKinetic();
    _model.cancelAnimations();
    final interaction = _model.options.interaction;
    final region = _regionAt(d.localFocalPoint);

    if (region == _Region.pane) {
      if (_model.hasCrosshair) _model.setCrosshairPosition(null);
      _crosshairPinned = false;
      if (d.pointerCount >= 2 && interaction.handleScale) {
        _mode = _DragMode.pinch;
        _pinchStartBarSpacing = _model.timeScale.barSpacing;
        _pinchAnchorIndex = _model.timeScale.coordinateToFloatIndex(d.localFocalPoint.dx);
      } else if (interaction.handleScroll) {
        _mode = _DragMode.scroll;
        _model.timeScale.startScroll(d.localFocalPoint.dx);
        _rightScale.startScroll(d.localFocalPoint.dy);
      } else {
        _mode = _DragMode.none;
      }
    } else if (interaction.axisDragScale && region == _Region.priceAxis) {
      _mode = _DragMode.priceAxisScale;
      _rightScale.startScale(d.localFocalPoint.dy);
    } else if (interaction.axisDragScale && region == _Region.timeAxis) {
      _mode = _DragMode.timeAxisScale;
      _model.timeScale.startScale(d.localFocalPoint.dx);
    } else {
      _mode = _DragMode.none;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final ts = _model.timeScale;
    switch (_mode) {
      case _DragMode.none:
        return;
      case _DragMode.scroll:
        ts.scrollTo(d.localFocalPoint.dx);
        _rightScale.scrollTo(d.localFocalPoint.dy);
      case _DragMode.pinch:
        ts.zoomAnchored(_pinchStartBarSpacing * d.horizontalScale, _pinchAnchorIndex, d.localFocalPoint.dx);
      case _DragMode.priceAxisScale:
        _rightScale.scaleTo(d.localFocalPoint.dy);
      case _DragMode.timeAxisScale:
        ts.scaleTo(d.localFocalPoint.dx);
    }
    _model.invalidate();
  }

  void _onScaleEnd(ScaleEndDetails d) {
    final ts = _model.timeScale;
    switch (_mode) {
      case _DragMode.scroll:
        ts.endScroll();
        _rightScale.endScroll();
        final vx = d.velocity.pixelsPerSecond.dx;
        // Like upstream's KineticAnimation, ignore slow flings.
        if (_model.options.interaction.kineticScroll && d.pointerCount == 0 && vx.abs() > 200) {
          _startKinetic(vx);
        }
      case _DragMode.priceAxisScale:
        _rightScale.endScale();
      case _DragMode.timeAxisScale:
        ts.endScale();
      case _DragMode.none:
      case _DragMode.pinch:
        break;
    }
    _mode = _DragMode.none;
  }

  void _startKinetic(double velocity) {
    _kinetic = FrictionSimulation(0.135, 0, velocity);
    _model.timeScale.startScroll(0);
    _kineticTicker.start();
  }

  void _onKineticTick(Duration elapsed) {
    final sim = _kinetic;
    if (sim == null) return;
    final t = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final before = _model.timeScale.rightOffset;
    _model.timeScale.scrollTo(sim.x(t));
    _model.invalidate();
    // Stop at the end of the simulation or when the scroll hit an edge.
    if (sim.isDone(t) || (t > 0.05 && before == _model.timeScale.rightOffset)) _stopKinetic();
  }

  void _stopKinetic() {
    if (_kinetic == null) return;
    _kinetic = null;
    _kineticTicker.stop();
    _model.timeScale.endScroll();
  }

  // ---- crosshair ----

  void _onLongPressStart(LongPressStartDetails d) {
    if (_regionAt(d.localPosition) != _Region.pane) return;
    _stopKinetic();
    _crosshairPinned = true;
    _model.setCrosshairPosition(d.localPosition);
  }

  void _onLongPressMove(LongPressMoveUpdateDetails d) {
    if (!_crosshairPinned) return;
    _model.setCrosshairPosition(d.localPosition);
  }

  void _onTapUp(TapUpDetails d) {
    final region = _regionAt(d.localPosition);
    final now = _clock.elapsed;
    final isDoubleTap = _lastTapRegion == region &&
        _lastTapTime != null &&
        now - _lastTapTime! < kDoubleTapTimeout;
    _lastTapRegion = region;
    _lastTapTime = now;

    switch (region) {
      case _Region.priceAxis:
        if (isDoubleTap) {
          _rightScale.options = _rightScale.options.copyWith(autoScale: true);
          _model.invalidate();
        }
      case _Region.timeAxis:
        if (isDoubleTap) {
          _model.timeScale.restoreDefault();
          _model.invalidate();
        }
      case _Region.pane:
        _stopKinetic();
        if (_model.hasCrosshair) {
          _model.setCrosshairPosition(null);
          _crosshairPinned = false;
        } else {
          _model.setCrosshairPosition(d.localPosition);
          _crosshairPinned = true;
        }
        _model.click(d.localPosition);
    }
  }

  // ---- mouse wheel (desktop / web) ----

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_model.options.interaction.handleScale) return;
    if (_regionAt(event.localPosition) != _Region.pane) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      final scroll = e as PointerScrollEvent;
      _model.timeScale.zoom(scroll.localPosition.dx, -scroll.scrollDelta.dy / 100);
      _model.invalidate();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          ScaleGestureRecognizer: GestureRecognizerFactoryWithHandlers<ScaleGestureRecognizer>(
            () => ScaleGestureRecognizer(debugOwner: this),
            (r) => r
              ..onStart = _onScaleStart
              ..onUpdate = _onScaleUpdate
              ..onEnd = _onScaleEnd,
          ),
          LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(debugOwner: this),
            (r) => r
              ..onLongPressStart = _onLongPressStart
              ..onLongPressMoveUpdate = _onLongPressMove,
          ),
          TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            () => TapGestureRecognizer(debugOwner: this),
            (r) => r.onTapUp = _onTapUp,
          ),
        },
        child: RepaintBoundary(
          child: SizedBox.expand(
            child: CustomPaint(
              painter: ChartPainter(model: _model, pixelRatio: pixelRatio, textCache: _textCache),
            ),
          ),
        ),
      ),
    );
  }
}
