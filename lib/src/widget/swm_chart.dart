import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../api/chart_controller.dart';
import '../model/chart_model.dart';
import '../model/pane.dart';
import '../model/price_scale.dart';
import '../model/series.dart';
import '../options.dart';
import 'attribution_logo.dart';
import 'chart_painter.dart';

enum _Region { pane, leftAxis, rightAxis, timeAxis, separator }

/// What is under a pointer: the region, the pane index (or separator index)
/// and the position relative to the pane.
class _Hit {
  const _Hit(this.region, this.index, this.local);

  final _Region region;
  final int index;
  final Offset local;
}

enum _DragMode { none, scroll, pinch, priceAxisScale, timeAxisScale, separator, captured, crosshair }

/// Touch area around a pane separator, in logical pixels.
const double _separatorHitSlop = 8;

/// Renders a [ChartController]. Give it bounded constraints (e.g. wrap it in
/// a `SizedBox` or `Expanded`).
///
/// Gestures follow lightweight-charts:
/// * drag a pane to scroll (with kinetic scrolling), pinch or wheel to zoom;
/// * touch: long-press then move to track the crosshair, tap to show/hide it;
/// * mouse: the crosshair follows the pointer, clicks only emit events;
/// * drag a price axis to scale prices, double-tap it to re-enable auto-scale;
/// * drag the time axis to change bar spacing, double-tap it to reset;
/// * drag the separator between panes to resize them.
///
/// Drawing and editing tools can take over pane drags (and, with
/// [TrackingModeOptions.longPressCrosshair] off, long presses) through
/// [ChartController.subscribePointer].
///
/// With a mouse the cursor shows what a drag would do: `resizeRow` on
/// separators, `resizeUpDown` on price axes, `resizeLeftRight` on the time
/// axis, or the cursor of the hovered primitive / custom series.
class SwmChart extends StatefulWidget {
  const SwmChart({super.key, required this.controller, this.onAttributionLogoTap, this.semanticsLabel = 'Chart'});

  final ChartController controller;

  /// Accessibility label read by screen readers. The semantics value is a
  /// summary of each series' last value, refreshed at most once a second.
  final String semanticsLabel;

  /// Called when the TradingView attribution logo is tapped; open
  /// https://www.tradingview.com/ here (e.g. with `url_launcher`).
  final VoidCallback? onAttributionLogoTap;

  @override
  State<SwmChart> createState() => _SwmChartState();
}

class _SwmChartState extends State<SwmChart> with SingleTickerProviderStateMixin {
  final TextCache _textCache = TextCache();
  final GlobalKey _boundaryKey = GlobalKey();
  late final Ticker _kineticTicker = createTicker(_onKineticTick);
  FrictionSimulation? _kinetic;

  _DragMode _mode = _DragMode.none;
  _Hit? _dragHit;

  /// Where the first finger touched down. Scale gestures only start after
  /// the touch slop, so hit testing uses this point instead.
  Offset? _downPosition;
  int _pointersDown = 0;
  double _dragStartY = 0;
  double _pinchStartBarSpacing = 0;
  double _pinchAnchorIndex = 0;
  bool _crosshairPinned = false;
  bool _scrollTime = true;
  bool _scrollPrice = true;
  bool _dragIsMouse = false;

  /// Touch pans lock to their dominant direction once it is clear, so a
  /// horizontal swipe doesn't drift a manual price scale (and vice versa).
  Axis? _panAxis;
  Offset _panStart = Offset.zero;
  int? _activeSeparator;

  /// Mouse hover state (desktop / web).
  int? _hoverSeparator;
  MouseCursor _cursor = MouseCursor.defer;
  bool _mouseCrosshair = false;

  /// Pane of the drag / long press a pointer handler took, and where the
  /// pointer last was in it.
  int? _capturedPane;
  Offset _capturedPoint = Offset.zero;
  bool _longPressCaptured = false;

  _Hit? _lastTap;
  Duration? _lastTapTime;
  final Stopwatch _clock = Stopwatch()..start();

  ChartModel get _model => widget.controller.model;

  String _semanticsValue = '';
  Timer? _semanticsTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.screenshotDelegate = _screenshot;
    _model.addListener(_scheduleSemantics);
    _semanticsValue = _summary();
  }

  /// Last value of every visible series, e.g. "Candlestick 101.00, RSI 55.29".
  String _summary() {
    final parts = <String>[];
    for (final s in _model.series) {
      final last = s.lastItem;
      if (!s.visible || last == null) continue;
      final name = s.options.title.isNotEmpty ? s.options.title : _typeName(s);
      parts.add('$name ${_model.formatSeriesPrice(s, s.closeValue(last))}');
    }
    return parts.join(', ');
  }

  static String _typeName(SeriesModel s) => switch (s) {
    CandlestickSeriesModel() => 'Candlestick',
    BarSeriesModel() => 'Bar',
    LineSeriesModel() => 'Line',
    AreaSeriesModel() => 'Area',
    BaselineSeriesModel() => 'Baseline',
    HistogramSeriesModel() => 'Histogram',
    _ => 'Series',
  };

  // Realtime data repaints every frame; screen readers only need a
  // summary now and then.
  void _scheduleSemantics() {
    if (_semanticsTimer != null) return;
    _semanticsTimer = Timer(const Duration(seconds: 1), () {
      _semanticsTimer = null;
      if (!mounted) return;
      final value = _summary();
      if (value != _semanticsValue) setState(() => _semanticsValue = value);
    });
  }

  @override
  void didUpdateWidget(SwmChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _stopKinetic();
      oldWidget.controller.model.removeListener(_scheduleSemantics);
      _model.addListener(_scheduleSemantics);
      if (oldWidget.controller.screenshotDelegate == _screenshot) oldWidget.controller.screenshotDelegate = null;
      widget.controller.screenshotDelegate = _screenshot;
    }
  }

  @override
  void dispose() {
    _semanticsTimer?.cancel();
    _model.removeListener(_scheduleSemantics);
    if (widget.controller.screenshotDelegate == _screenshot) widget.controller.screenshotDelegate = null;
    _kineticTicker.dispose();
    _textCache.dispose();
    super.dispose();
  }

  Future<ui.Image> _screenshot() {
    final boundary = _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) throw StateError('The chart is not mounted');
    return boundary.toImage(pixelRatio: MediaQuery.devicePixelRatioOf(context));
  }

  _Hit _hitTest(Offset p) {
    final m = _model;
    final panes = m.panes;
    if (m.options.layout.panes.enableResize) {
      for (var i = 0; i < panes.length - 1; i++) {
        final y = panes[i].top + panes[i].height + paneSeparatorHeight / 2;
        if ((p.dy - y).abs() <= _separatorHitSlop) return _Hit(_Region.separator, i, p);
      }
    }
    if (p.dy >= m.size.height - m.timeAxisHeight || panes.isEmpty) {
      return _Hit(_Region.timeAxis, -1, Offset(p.dx - m.leftAxisWidth, 0));
    }
    var index = panes.length - 1;
    for (var i = 0; i < panes.length; i++) {
      if (p.dy < panes[i].top + panes[i].height) {
        index = i;
        break;
      }
    }
    final local = Offset(p.dx - m.leftAxisWidth, p.dy - panes[index].top);
    if (p.dx < m.leftAxisWidth) return _Hit(_Region.leftAxis, index, local);
    if (p.dx >= m.leftAxisWidth + m.paneWidth) return _Hit(_Region.rightAxis, index, local);
    return _Hit(_Region.pane, index, local);
  }

  /// Upstream only scales price axes by dragging outside the percentage modes.
  bool _canScalePriceAxis(_Hit hit) =>
      _model.options.handleScale.axisPressedMouseMove.price && !_axisScale(hit).isPercentLike;

  PriceScale _axisScale(_Hit hit) {
    final pane = _model.panes[hit.index];
    return hit.region == _Region.leftAxis ? pane.leftScale : pane.rightScale;
  }

  Iterable<PriceScale> _paneScales(int index) {
    final pane = _model.panes[index];
    return [pane.leftScale, pane.rightScale];
  }

  // ---- pan / pinch / axis drag ----

  void _onScaleStart(ScaleStartDetails d) {
    _stopKinetic();
    _model.cancelAnimations();
    final o = _model.options;
    final isMouse = d.kind == PointerDeviceKind.mouse;
    _dragIsMouse = isMouse;
    final start = d.pointerCount == 1 && _downPosition != null ? _downPosition! : d.localFocalPoint;
    final hit = _hitTest(start);
    _dragHit = hit;

    switch (hit.region) {
      case _Region.separator:
        _mode = _DragMode.separator;
        _dragStartY = start.dy;
        _model.startPaneResize(hit.index);
        setState(() => _activeSeparator = hit.index);
      case _Region.pane:
        final crosshairShown = _crosshairPinned && _model.hasCrosshair;
        // A drawing / editing tool may take a one-pointer drag.
        if (d.pointerCount == 1 &&
            widget.controller.hasPointerHandlers &&
            widget.controller.handlePointer(ChartPointerPhase.down, ChartPointerSource.drag, hit.index, hit.local)) {
          if (_model.hasCrosshair) _model.setCrosshairPosition(null, null);
          _crosshairPinned = false;
          _mode = _DragMode.captured;
          _capturedPane = hit.index;
          _capturedPoint = hit.local;
          return;
        }
        // With the crosshair shown (after a tap or a long press), one finger
        // moves it across the bars instead of scrolling, like TradingView's
        // mobile app; a tap hides it again.
        if (crosshairShown && !isMouse && d.pointerCount == 1) {
          _mode = _DragMode.crosshair;
          _model.setCrosshairPosition(hit.index, hit.local);
          return;
        }
        if (_model.hasCrosshair) _model.setCrosshairPosition(null, null);
        _crosshairPinned = false;
        _scrollTime = isMouse ? o.handleScroll.pressedMouseMove : o.handleScroll.horzTouchDrag;
        _scrollPrice = isMouse ? o.handleScroll.pressedMouseMove : o.handleScroll.vertTouchDrag;
        if (d.pointerCount >= 2 && o.handleScale.pinch) {
          _mode = _DragMode.pinch;
          _pinchStartBarSpacing = _model.timeScale.barSpacing;
          _pinchAnchorIndex = _model.timeScale.coordinateToFloatIndex(hit.local.dx);
        } else if (_scrollTime || _scrollPrice) {
          _mode = _DragMode.scroll;
          _panAxis = null;
          _panStart = start;
          _model.timeScale.startScroll(hit.local.dx);
          for (final ps in _paneScales(hit.index)) {
            ps.startScroll(hit.local.dy);
          }
        } else {
          _mode = _DragMode.none;
        }
      case _Region.leftAxis:
      case _Region.rightAxis:
        if (_canScalePriceAxis(hit)) {
          _mode = _DragMode.priceAxisScale;
          _axisScale(hit).startScale(hit.local.dy);
        } else {
          _mode = _DragMode.none;
        }
      case _Region.timeAxis:
        if (o.handleScale.axisPressedMouseMove.time) {
          _mode = _DragMode.timeAxisScale;
          _model.timeScale.startScale(hit.local.dx);
        } else {
          _mode = _DragMode.none;
        }
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final ts = _model.timeScale;
    final hit = _dragHit;
    if (hit == null) return;
    final x = d.localFocalPoint.dx - _model.leftAxisWidth;
    final paneTop = hit.index >= 0 && hit.index < _model.panes.length ? _model.panes[hit.index].top : 0.0;
    final y = d.localFocalPoint.dy - paneTop;
    switch (_mode) {
      case _DragMode.none:
        return;
      case _DragMode.crosshair:
        // A second finger (a pinch) drops the crosshair.
        if (d.pointerCount > 1) {
          _model.setCrosshairPosition(null, null);
          _crosshairPinned = false;
          _mode = _DragMode.none;
          return;
        }
        final at = _hitTest(d.localFocalPoint);
        if (at.region == _Region.pane) _model.setCrosshairPosition(at.index, at.local);
        return;
      case _DragMode.captured:
        final pane = _capturedPane;
        if (pane == null || pane >= _model.panes.length) return;
        if (d.pointerCount > 1) {
          widget.controller.handlePointer(ChartPointerPhase.cancel, ChartPointerSource.drag, pane, _capturedPoint);
          _mode = _DragMode.none;
          _capturedPane = null;
          return;
        }
        _capturedPoint = Offset(x, d.localFocalPoint.dy - _model.panes[pane].top);
        widget.controller.handlePointer(ChartPointerPhase.move, ChartPointerSource.drag, pane, _capturedPoint);
        return;
      case _DragMode.separator:
        _model.resizePane(hit.index, d.localFocalPoint.dy - _dragStartY);
      case _DragMode.scroll:
        if (!_dragIsMouse && _panAxis == null) {
          final delta = d.localFocalPoint - _panStart;
          if (delta.distance > kTouchSlop) {
            _panAxis = delta.dx.abs() >= delta.dy.abs() ? Axis.horizontal : Axis.vertical;
          }
        }
        final timeAllowed = _dragIsMouse || _panAxis != Axis.vertical;
        final priceAllowed = _dragIsMouse || _panAxis == Axis.vertical;
        if (_scrollTime && timeAllowed) ts.scrollTo(x);
        if (_scrollPrice && priceAllowed) {
          for (final ps in _paneScales(hit.index)) {
            ps.scrollTo(y);
          }
        }
      case _DragMode.pinch:
        ts.zoomAnchored(_pinchStartBarSpacing * d.horizontalScale, _pinchAnchorIndex, x);
      case _DragMode.priceAxisScale:
        _axisScale(hit).scaleTo(y);
      case _DragMode.timeAxisScale:
        ts.scaleTo(x);
    }
    _model.invalidate();
  }

  void _onScaleEnd(ScaleEndDetails d) {
    final ts = _model.timeScale;
    final hit = _dragHit;
    switch (_mode) {
      case _DragMode.scroll:
        ts.endScroll();
        if (hit != null) {
          for (final ps in _paneScales(hit.index)) {
            ps.endScroll();
          }
        }
        final vx = d.velocity.pixelsPerSecond.dx;
        // Like upstream's KineticAnimation, ignore slow flings.
        final kinetic = _dragIsMouse ? _model.options.kineticScroll.mouse : _model.options.kineticScroll.touch;
        if (kinetic && _scrollTime && d.pointerCount == 0 && vx.abs() > 200) {
          _startKinetic(vx);
        }
      case _DragMode.priceAxisScale:
        if (hit != null) _axisScale(hit).endScale();
      case _DragMode.timeAxisScale:
        ts.endScale();
      case _DragMode.separator:
        _model.endPaneResize();
        setState(() => _activeSeparator = null);
      case _DragMode.captured:
        final pane = _capturedPane;
        if (pane != null) {
          widget.controller.handlePointer(ChartPointerPhase.up, ChartPointerSource.drag, pane, _capturedPoint);
        }
        _capturedPane = null;
      case _DragMode.none:
      case _DragMode.pinch:
      // The crosshair stays where it was left.
      case _DragMode.crosshair:
        break;
    }
    _mode = _DragMode.none;
    _dragHit = null;
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
    final hit = _hitTest(d.localPosition);
    if (hit.region != _Region.pane) return;
    _stopKinetic();
    if (!_model.options.trackingMode.longPressCrosshair) {
      // Offered to pointer handlers instead of showing the crosshair.
      _longPressCaptured =
          widget.controller.hasPointerHandlers &&
          widget.controller.handlePointer(ChartPointerPhase.down, ChartPointerSource.longPress, hit.index, hit.local);
      if (_longPressCaptured) {
        _capturedPane = hit.index;
        _capturedPoint = hit.local;
      }
      return;
    }
    _crosshairPinned = true;
    _model.setCrosshairPosition(hit.index, hit.local);
  }

  void _onLongPressEnd(LongPressEndDetails d) {
    if (_longPressCaptured) {
      final pane = _capturedPane;
      if (pane != null) {
        widget.controller.handlePointer(ChartPointerPhase.up, ChartPointerSource.longPress, pane, _capturedPoint);
      }
      _longPressCaptured = false;
      _capturedPane = null;
      return;
    }
    if (_model.options.trackingMode.exitMode == TrackingModeExitMode.onTouchEnd) {
      _model.setCrosshairPosition(null, null);
      _crosshairPinned = false;
    }
  }

  void _onLongPressMove(LongPressMoveUpdateDetails d) {
    if (_longPressCaptured) {
      final pane = _capturedPane;
      if (pane == null || pane >= _model.panes.length) return;
      _capturedPoint = Offset(d.localPosition.dx - _model.leftAxisWidth, d.localPosition.dy - _model.panes[pane].top);
      widget.controller.handlePointer(ChartPointerPhase.move, ChartPointerSource.longPress, pane, _capturedPoint);
      return;
    }
    if (!_crosshairPinned) return;
    final hit = _hitTest(d.localPosition);
    if (hit.region == _Region.pane) _model.setCrosshairPosition(hit.index, hit.local);
  }

  void _onTapUp(TapUpDetails d) {
    final isMouse = d.kind == PointerDeviceKind.mouse;
    if (_model.options.layout.attributionLogo && _model.panes.isNotEmpty) {
      final logo = attributionLogoRect(_model.paneRect(_model.panes.length - 1)).inflate(4);
      if (logo.contains(d.localPosition)) {
        widget.onAttributionLogoTap?.call();
        return;
      }
    }
    final hit = _hitTest(d.localPosition);
    final now = _clock.elapsed;
    final last = _lastTap;
    final isDoubleTap =
        last != null &&
        last.region == hit.region &&
        last.index == hit.index &&
        _lastTapTime != null &&
        now - _lastTapTime! < kDoubleTapTimeout;
    _lastTap = isDoubleTap ? null : hit;
    _lastTapTime = now;
    final reset = _model.options.handleScale.axisDoubleClickReset;

    switch (hit.region) {
      case _Region.leftAxis:
      case _Region.rightAxis:
        if (isDoubleTap && reset.price) {
          final ps = _axisScale(hit);
          ps.options = ps.options.copyWith(autoScale: true);
          _model.invalidate();
        }
      case _Region.timeAxis:
        if (isDoubleTap && reset.time) {
          _model.timeScale.restoreDefault();
          _model.invalidate();
        }
      case _Region.separator:
        break;
      case _Region.pane:
        _stopKinetic();
        // With a mouse the crosshair follows hovering; a click only emits events.
        if (!isMouse) {
          if (_model.hasCrosshair) {
            _model.setCrosshairPosition(null, null);
            _crosshairPinned = false;
          } else {
            _model.setCrosshairPosition(hit.index, hit.local);
            _crosshairPinned = true;
          }
        }
        _model.click(hit.index, hit.local);
        if (isDoubleTap) _model.click(hit.index, hit.local, doubleClick: true);
    }
  }

  // ---- mouse hover (desktop / web) ----

  void _onHover(PointerHoverEvent e) {
    final hit = _hitTest(e.localPosition);
    final o = _model.options;
    if (hit.region == _Region.pane && _mode == _DragMode.none) {
      _model.setCrosshairPosition(hit.index, hit.local);
      _mouseCrosshair = true;
    } else if (_mouseCrosshair) {
      _model.setCrosshairPosition(null, null);
      _mouseCrosshair = false;
    }
    final cursor = switch (hit.region) {
      _Region.separator => SystemMouseCursors.resizeRow,
      _Region.leftAxis ||
      _Region.rightAxis => _canScalePriceAxis(hit) ? SystemMouseCursors.resizeUpDown : SystemMouseCursors.basic,
      _Region.timeAxis =>
        o.handleScale.axisPressedMouseMove.time ? SystemMouseCursors.resizeLeftRight : SystemMouseCursors.basic,
      _Region.pane => _model.hovered?.cursor ?? SystemMouseCursors.basic,
    };
    final separator = hit.region == _Region.separator ? hit.index : null;
    if (cursor != _cursor || separator != _hoverSeparator) {
      setState(() {
        _cursor = cursor;
        _hoverSeparator = separator;
      });
    }
  }

  void _onExit(PointerExitEvent e) {
    if (_mouseCrosshair && _mode == _DragMode.none) {
      _model.setCrosshairPosition(null, null);
      _mouseCrosshair = false;
    }
    if (_hoverSeparator != null || _cursor != MouseCursor.defer) {
      setState(() {
        _hoverSeparator = null;
        _cursor = MouseCursor.defer;
      });
    }
  }

  // ---- mouse wheel (desktop / web) ----

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final o = _model.options;
    final hit = _hitTest(event.localPosition);
    if (hit.region != _Region.pane) return;
    final delta = event.scrollDelta;
    final zoom = o.handleScale.mouseWheel && delta.dy != 0;
    final scroll = o.handleScroll.mouseWheel && delta.dx != 0;
    if (!zoom && !scroll) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      final ts = _model.timeScale;
      if (scroll) ts.setRightOffset(ts.rightOffset + delta.dx / ts.barSpacing);
      if (zoom) ts.zoom(hit.local.dx, -delta.dy / 100);
      _model.invalidate();
    });
  }

  @override
  Widget build(BuildContext context) =>
      Semantics(container: true, label: widget.semanticsLabel, value: _semanticsValue, child: _buildChart(context));

  Widget _buildChart(BuildContext context) {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return MouseRegion(
      cursor: _cursor,
      onHover: _onHover,
      onExit: _onExit,
      child: Listener(
        onPointerSignal: _onPointerSignal,
        onPointerDown: (e) {
          if (_pointersDown++ == 0) _downPosition = e.localPosition;
        },
        onPointerUp: (_) => _pointersDown = (_pointersDown - 1).clamp(0, 100),
        onPointerCancel: (_) => _pointersDown = (_pointersDown - 1).clamp(0, 100),
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
              // Touch only: with a mouse the crosshair already follows hovering.
              () => LongPressGestureRecognizer(
                debugOwner: this,
                supportedDevices: const {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.stylus,
                  PointerDeviceKind.invertedStylus,
                  PointerDeviceKind.unknown,
                },
              ),
              (r) => r
                ..onLongPressStart = _onLongPressStart
                ..onLongPressMoveUpdate = _onLongPressMove
                ..onLongPressEnd = _onLongPressEnd,
            ),
            TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              () => TapGestureRecognizer(debugOwner: this),
              (r) => r.onTapUp = _onTapUp,
            ),
          },
          child: RepaintBoundary(
            key: _boundaryKey,
            child: SizedBox.expand(
              child: CustomPaint(
                painter: ChartPainter(
                  model: _model,
                  pixelRatio: pixelRatio,
                  textCache: _textCache,
                  activeSeparator: _activeSeparator ?? _hoverSeparator,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
