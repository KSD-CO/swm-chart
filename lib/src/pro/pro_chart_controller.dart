// A ready-made trading chart: the price series in a chosen style, volume,
// indicators from the catalog, drawings, trading lines and a legend — and
// its whole state saved and restored as JSON.
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../api/chart_controller.dart';
import '../data.dart';
import '../indicators/attach.dart';
import '../indicators/catalog.dart';
import '../options.dart';
import '../plugins/drawing_codec.dart';
import '../plugins/drawings.dart';
import '../plugins/legend.dart';
import '../plugins/trading_lines.dart';
import '../plugins/watermark.dart';
import '../series_options.dart';
import '../transforms/transforms.dart';
import 'drawing_tools.dart';

/// How [ProChartController] draws prices.
enum ProChartType {
  candles('Candles'),
  hollowCandles('Hollow candles'),
  bars('Bars'),
  line('Line'),
  area('Area'),
  baseline('Baseline'),
  heikinAshi('Heikin-Ashi');

  const ProChartType(this.label);

  final String label;
}

/// Color, width and visibility of one line of an indicator.
class IndicatorLineStyle {
  const IndicatorLineStyle({required this.color, this.lineWidth = 1.5, this.visible = true});

  final Color color;
  final double lineWidth;
  final bool visible;

  IndicatorLineStyle copyWith({Color? color, double? lineWidth, bool? visible}) => IndicatorLineStyle(
    color: color ?? this.color,
    lineWidth: lineWidth ?? this.lineWidth,
    visible: visible ?? this.visible,
  );

  Map<String, Object?> toJson() => {'color': color.toARGB32(), 'lineWidth': lineWidth, 'visible': visible};

  static IndicatorLineStyle? fromJson(Object? json) {
    if (json is! Map || json['color'] is! int) return null;
    return IndicatorLineStyle(
      color: Color(json['color'] as int),
      lineWidth: (json['lineWidth'] as num?)?.toDouble() ?? 1.5,
      visible: json['visible'] != false,
    );
  }
}

/// An indicator on a [ProChartController]: its catalog entry, inputs and
/// line styles.
class ProIndicator {
  ProIndicator._(this.spec, this.values, this._handle, this.styles, this.visible);

  final IndicatorSpec spec;

  /// Inputs, every parameter of [spec] filled in.
  final Map<String, num> values;
  IndicatorHandle _handle;

  /// One per line of the indicator.
  final List<IndicatorLineStyle> styles;
  bool visible;

  IndicatorHandle get handle => _handle;

  /// Short name with its inputs, e.g. `RSI 14`.
  String get name => _handle.indicator.name;

  Map<String, Object?> toJson() => {
    'id': spec.id,
    'values': values,
    'styles': [for (final s in styles) s.toJson()],
    if (!visible) 'visible': false,
  };
}

/// A trading chart with everything wired up: the price series in any
/// [ProChartType], an optional volume histogram, indicators from
/// [IndicatorCatalog], a [DrawingEditor], [TradingLines] and a legend.
/// [SwmProChart] puts toolbars around it.
///
/// ```dart
/// final pro = ProChartController(symbol: 'BTC/USD', interval: '1h');
/// pro.setData(bars, volumes: volumes);
/// pro.addIndicator(IndicatorCatalog.byId('rsi')!);
/// final saved = jsonEncode(pro.saveState());
/// // later, after setData:
/// pro.restoreState(jsonDecode(saved));
/// ```
class ProChartController extends ChangeNotifier {
  ProChartController({
    ChartOptions options = const ChartOptions(timeScale: TimeScaleOptions(timeVisible: true, rightOffset: 5)),
    ProChartType type = ProChartType.candles,
    bool showVolume = true,
    String? symbol,
    String? interval,
    LegendOptions legend = const LegendOptions(),
    this.drawingKinds = const [],
    this.onTradingLineDragEnd,
    this.onAlert,
  }) : chart = ChartController(options: options),
       _type = type,
       _showVolume = showVolume,
       _symbol = symbol,
       _interval = interval,
       _legendOptions = legend {
    if (showVolume) _addVolume();
    _main = _addMain(type);
    drawings = DrawingEditor(
      chart,
      onCreated: (d) {
        _created = d;
        notifyListeners();
      },
      onSelectionChanged: (_) => notifyListeners(),
    );
    drawings.onHistoryChanged = notifyListeners;
    _trading = _newTrading(const []);
    this.legend = createLegend(chart, _legend());
  }

  final ChartController chart;

  /// Your own drawings ([DrawingKind]s), so [saveState] / [restoreState],
  /// [codec] and duplicating handle them; pair them with your tools in
  /// `DrawingToolbar.groups`.
  final List<DrawingKind> drawingKinds;

  /// After a trading line was dragged to a new price.
  final void Function(TradingLine line)? onTradingLineDragEnd;

  /// When the last price crosses an alert line.
  final void Function(TradingLine alert, double price)? onAlert;

  late final DrawingEditor drawings;
  late final ChartLegend legend;
  late SeriesApi _main;
  HistogramSeriesApi? _volume;
  late TradingLines _trading;

  ProChartType _type;
  bool _showVolume;
  String? _symbol;
  String? _interval;
  LegendOptions _legendOptions;

  List<CandlestickData> _bars = const [];
  List<double>? _volumes;
  HeikinAshi? _heikinAshi;
  final List<ProIndicator> _indicators = [];

  /// The price series, in the current [type].
  SeriesApi get mainSeries => _main;

  /// The volume histogram, `null` when [showVolume] is off.
  HistogramSeriesApi? get volumeSeries => _volume;

  TradingLines get trading => _trading;

  /// The source bars, as given to [setData] and [update].
  List<CandlestickData> get bars => List.unmodifiable(_bars);

  List<ProIndicator> get indicators => List.unmodifiable(_indicators);

  /// Saves and loads drawings, including those that read the price series.
  DrawingCodec get codec =>
      DrawingCodec(custom: drawingKinds, source: _main, volume: _volume, icons: DrawingTools.icons);

  String? get symbol => _symbol;

  set symbol(String? value) {
    _symbol = value;
    legend.options = _legend();
    _applyWatermark(rebuild: true);
    notifyListeners();
  }

  // ---- display ----

  /// The library's default crosshair grey.
  static const defaultCrosshairColor = Color(0xFF9598A1);

  LineStyle _crosshairStyle = LineStyle.largeDashed;
  Color _crosshairColor = defaultCrosshairColor;
  double _crosshairWidth = 1;
  bool _showGrid = true;
  bool _showWatermark = false;
  WatermarkPlugin<TextWatermarkPrimitive>? _watermark;

  /// The crosshair's lines.
  LineStyle get crosshairStyle => _crosshairStyle;

  set crosshairStyle(LineStyle value) => _display(() => _crosshairStyle = value);

  Color get crosshairColor => _crosshairColor;

  set crosshairColor(Color value) => _display(() => _crosshairColor = value);

  double get crosshairWidth => _crosshairWidth;

  set crosshairWidth(double value) => _display(() => _crosshairWidth = value);

  /// The grid behind the bars.
  bool get showGrid => _showGrid;

  set showGrid(bool value) => _display(() => _showGrid = value);

  /// The [symbol] written large and faint across the price pane.
  bool get showWatermark => _showWatermark;

  set showWatermark(bool value) => _display(() => _showWatermark = value);

  /// Back to the default crosshair, grid on, no watermark.
  void resetDisplay() => _display(() {
    _crosshairStyle = LineStyle.largeDashed;
    _crosshairColor = defaultCrosshairColor;
    _crosshairWidth = 1;
    _showGrid = true;
    _showWatermark = false;
  });

  void _display(void Function() change) {
    change();
    _applyDisplay();
    notifyListeners();
  }

  void _applyDisplay() {
    final o = chart.options;
    chart.applyOptions(
      o.copyWith(
        crosshair: o.crosshair.copyWith(
          vertLine: o.crosshair.vertLine.copyWith(
            color: _crosshairColor,
            width: _crosshairWidth,
            style: _crosshairStyle,
          ),
          horzLine: o.crosshair.horzLine.copyWith(
            color: _crosshairColor,
            width: _crosshairWidth,
            style: _crosshairStyle,
          ),
        ),
        grid: o.grid.copyWith(
          vertLines: o.grid.vertLines.copyWith(visible: _showGrid),
          horzLines: o.grid.horzLines.copyWith(visible: _showGrid),
        ),
        // Chart-wide options replace the price scale's; keep its mode.
        rightPriceScale: chart.priceScale().options,
      ),
    );
    _applyWatermark();
  }

  void _applyWatermark({bool rebuild = false}) {
    final text = _symbol;
    if (rebuild || !_showWatermark || text == null || text.isEmpty) {
      _watermark?.detach();
      _watermark = null;
    }
    if (!_showWatermark || text == null || text.isEmpty) return;
    _watermark ??= createTextWatermark(
      chart.panes().first,
      TextWatermarkOptions(
        lines: [
          TextWatermarkLine(text: text, color: const Color(0x1F808080), fontSize: 44, fontWeight: FontWeight.w700),
        ],
      ),
    );
  }

  Map<String, Object?> _displayToJson() => {
    'crosshairStyle': _crosshairStyle.name,
    'crosshairColor': _crosshairColor.toARGB32(),
    'crosshairWidth': _crosshairWidth,
    'showGrid': _showGrid,
    'showWatermark': _showWatermark,
  };

  void _displayFromJson(Map<Object?, Object?> json) {
    if (json['crosshairStyle'] case final String name) {
      _crosshairStyle = LineStyle.values.where((v) => v.name == name).firstOrNull ?? _crosshairStyle;
    }
    if (json['crosshairColor'] case final int c) _crosshairColor = Color(c);
    if (json['crosshairWidth'] case final num w) _crosshairWidth = w.toDouble();
    if (json['showGrid'] case final bool v) _showGrid = v;
    if (json['showWatermark'] case final bool v) _showWatermark = v;
    _applyDisplay();
  }

  /// A label for the bars' interval (`1h`, `1D`…); shown and saved, the data
  /// is up to you.
  String? get interval => _interval;

  set interval(String? value) {
    _interval = value;
    legend.options = _legend();
    notifyListeners();
  }

  set legendOptions(LegendOptions value) {
    _legendOptions = value;
    legend.options = _legend();
  }

  LegendOptions _legend() {
    final title = [?_symbol, ?_interval].join(' · ');
    return LegendOptions(
      mode: _legendOptions.mode,
      title: _legendOptions.title ?? (title.isEmpty ? null : title),
      showOhlc: _legendOptions.showOhlc,
      showChange: _legendOptions.showChange,
      fontSize: _legendOptions.fontSize,
      textColor: _legendOptions.textColor,
      backgroundColor: _legendOptions.backgroundColor,
      formatTime: _legendOptions.formatTime,
    );
  }

  // ---- data ----

  /// Replaces the bars, and their [volumes] (one per bar) when the volume
  /// histogram is shown.
  void setData(List<CandlestickData> bars, {List<double>? volumes}) {
    assert(volumes == null || volumes.length == bars.length, 'one volume per bar');
    _bars = List.of(bars);
    _volumes = volumes == null ? null : List.of(volumes);
    _volume?.setData(_volumeData());
    _setMainData();
  }

  /// Adds a bar, or replaces the last one when it has the same time.
  void update(CandlestickData bar, {double? volume}) {
    final replace = _bars.isNotEmpty && _bars.last.time == bar.time;
    if (replace) {
      _bars[_bars.length - 1] = bar;
    } else {
      _bars.add(bar);
    }
    final vols = _volumes;
    if (vols != null) {
      final v = volume ?? (replace ? vols.last : 0);
      if (replace) {
        vols[vols.length - 1] = v;
      } else {
        vols.add(v);
      }
      _volume?.update(_volumeBar(bar, v));
    }
    _main.update(_mainPoint(bar));
  }

  static const _upVolume = Color(0x8026A69A);
  static const _downVolume = Color(0x80EF5350);

  HistogramData _volumeBar(CandlestickData b, double v) =>
      HistogramData(time: b.time, value: v, color: b.close >= b.open ? _upVolume : _downVolume);

  List<HistogramData> _volumeData() {
    final v = _volumes;
    if (v == null) return const [];
    return [for (var i = 0; i < _bars.length; i++) _volumeBar(_bars[i], v[i])];
  }

  void _setMainData() {
    if (_type == ProChartType.heikinAshi) {
      final converter = _heikinAshi = HeikinAshi();
      _main.setData([for (final b in _bars) converter.add(b)]);
      return;
    }
    _heikinAshi = null;
    _main.setData([for (final b in _bars) _mainPoint(b)]);
  }

  SeriesData _mainPoint(CandlestickData b) => switch (_type) {
    ProChartType.candles || ProChartType.hollowCandles => b,
    ProChartType.heikinAshi => (_heikinAshi ??= HeikinAshi()).add(b),
    ProChartType.bars => BarData(time: b.time, open: b.open, high: b.high, low: b.low, close: b.close),
    ProChartType.line => LineData(time: b.time, value: b.close),
    ProChartType.area => AreaData(time: b.time, value: b.close),
    ProChartType.baseline => BaselineData(time: b.time, value: b.close),
  };

  void _addVolume() {
    _volume = chart.addHistogramSeries(
      const HistogramSeriesOptions(
        priceScaleId: 'volume',
        priceFormat: PriceFormat.volume(),
        lastValueVisible: false,
        priceLineVisible: false,
        title: 'Volume',
      ),
    );
    chart.priceScale('volume').applyOptions(const PriceScaleOptions(scaleMargins: ScaleMargins(top: 0.8, bottom: 0)));
  }

  SeriesApi _addMain(ProChartType type) {
    final title = _symbol ?? '';
    return switch (type) {
      ProChartType.candles || ProChartType.heikinAshi => chart.addCandlestickSeries(
        CandlestickSeriesOptions(title: title, borderVisible: false),
      ),
      ProChartType.hollowCandles => chart.addCandlestickSeries(
        CandlestickSeriesOptions(title: title, upColor: const Color(0x00000000)),
      ),
      ProChartType.bars => chart.addBarSeries(BarSeriesOptions(title: title)),
      ProChartType.line => chart.addLineSeries(LineSeriesOptions(title: title, lineWidth: 2)),
      ProChartType.area => chart.addAreaSeries(AreaSeriesOptions(title: title, lineWidth: 2)),
      ProChartType.baseline => chart.addBaselineSeries(
        BaselineSeriesOptions(title: title, baseValue: _bars.isEmpty ? 0 : _bars.first.close),
      ),
    };
  }

  // ---- type and scale ----

  ProChartType get type => _type;

  /// Redraws the prices as [value]. Indicators and trading lines move to
  /// the new series (indicators read it: on Heikin-Ashi they follow its
  /// candles, as on TradingView).
  set type(ProChartType value) {
    if (value == _type) return;
    final configs = [for (final i in _indicators) i.toJson()];
    for (final i in _indicators) {
      i.handle.remove();
    }
    _indicators.clear();
    final lines = _trading.lines;
    _trading.dispose();

    _type = value;
    // The new series first: pane 0 never goes empty (and away).
    final old = _main;
    _main = _addMain(value);
    chart.removeSeries(old);
    _setMainData();

    for (final c in configs) {
      _restoreIndicator(c);
    }
    _trading = _newTrading(lines);
    for (final d in drawings.drawings) {
      if (d is AnchoredVwapDrawing) d.source = _main;
      if (d is RegressionTrendDrawing) d.source = _main;
      if (d is RangeVolumeProfileDrawing) d.source = _main;
    }
    drawings.layer.requestUpdate();
    notifyListeners();
  }

  bool get showVolume => _showVolume;

  /// Shows or hides the volume histogram. Volume indicators keep reading it
  /// while it is hidden.
  set showVolume(bool value) {
    if (value == _showVolume) return;
    _showVolume = value;
    if (_volume == null) {
      _addVolume();
      _volume!.setData(_volumeData());
    }
    _volume!.applyOptions(_volume!.options.copyWith(visible: value));
    notifyListeners();
  }

  PriceScaleMode get scaleMode => chart.priceScale().options.mode;

  set scaleMode(PriceScaleMode value) {
    final scale = chart.priceScale();
    scale.applyOptions(scale.options.copyWith(mode: value));
    notifyListeners();
  }

  // ---- drawing tools ----

  DrawingToolSpec? _tool;
  bool _magnet = false;
  Drawing? _created;

  /// The tool new drawings come from; `null` while selecting and editing.
  /// Back to `null` once a drawing is placed, unless [keepDrawing].
  DrawingToolSpec? get activeTool => drawings.tool == null ? null : _tool;

  set activeTool(DrawingToolSpec? spec) {
    _tool = spec;
    drawings.tool = spec == null ? null : (id, anchors) => spec.create(this, id, anchors);
    notifyListeners();
  }

  /// Keep the tool after placing a drawing, to draw several in a row.
  bool get keepDrawing => drawings.keepTool;

  set keepDrawing(bool value) {
    drawings.keepTool = value;
    notifyListeners();
  }

  /// Anchors snap to the nearest open, high, low or close.
  bool get magnet => _magnet;

  set magnet(bool value) {
    _magnet = value;
    drawings.snap = value ? _snap : null;
    notifyListeners();
  }

  DrawingAnchor _snap(DrawingAnchor a) {
    final i = a.logical.round();
    final prices = switch (_main.dataByIndex(i)) {
      final OhlcData d => [d.open, d.high, d.low, d.close],
      final SingleValueData d => [d.value],
      _ => const <double>[],
    };
    if (prices.isEmpty) return a;
    var best = prices.first;
    for (final p in prices) {
      if ((p - a.price).abs() < (best - a.price).abs()) best = p;
    }
    return DrawingAnchor(i.toDouble(), best);
  }

  /// Whether every drawing is hidden.
  bool get drawingsHidden => drawings.drawings.isNotEmpty && drawings.drawings.every((d) => !d.visible);

  set drawingsHidden(bool value) {
    for (final d in drawings.drawings) {
      d.visible = !value;
    }
    if (value) drawings.select(null);
    drawings.layer.requestUpdate();
    notifyListeners();
  }

  /// The drawing placed last, once: [SwmProChart] asks for the text of a
  /// new text or callout.
  Drawing? takeCreated() {
    final d = _created;
    _created = null;
    return d;
  }

  // ---- trading lines ----

  TradingLines _newTrading(List<TradingLine> lines) {
    final t = TradingLines(_main, onDragEnd: onTradingLineDragEnd, onAlert: onAlert);
    for (final l in lines) {
      t.add(l);
    }
    return t;
  }

  // ---- indicators ----

  /// Adds [spec] with [values] (defaults for the rest) and, optionally, its
  /// line [styles].
  ProIndicator addIndicator(
    IndicatorSpec spec, {
    Map<String, num> values = const {},
    List<IndicatorLineStyle>? styles,
    bool visible = true,
  }) {
    final full = spec.withDefaults(values);
    final handle = chart.addIndicator(spec.create(full), source: _main, volume: _volume);
    final ind = ProIndicator._(spec, full, handle, styles ?? _stylesOf(handle), visible);
    _applyStyles(ind);
    _indicators.add(ind);
    notifyListeners();
    return ind;
  }

  /// Changes an indicator's inputs, line styles or visibility. New inputs
  /// recompute it in place (same position in the list and the legend).
  void updateIndicator(
    ProIndicator indicator, {
    Map<String, num>? values,
    List<IndicatorLineStyle>? styles,
    bool? visible,
  }) {
    if (!_indicators.contains(indicator)) return;
    if (styles != null) {
      indicator.styles
        ..clear()
        ..addAll(styles);
    }
    if (visible != null) indicator.visible = visible;
    if (values != null) {
      final full = indicator.spec.withDefaults(values);
      indicator.values
        ..clear()
        ..addAll(full);
      // The new one first, into the old one's pane, so that pane stays.
      final old = indicator.handle;
      indicator._handle = chart.addIndicator(
        indicator.spec.create(full),
        source: _main,
        volume: _volume,
        // Where it is now: panes above it may have gone since it was added.
        paneIndex: old.series.isEmpty ? null : old.series.first.getPane().paneIndex(),
      );
      old.remove();
      final defaults = _stylesOf(indicator._handle);
      if (indicator.styles.length != defaults.length) {
        indicator.styles
          ..clear()
          ..addAll(defaults);
      }
    }
    _applyStyles(indicator);
    notifyListeners();
  }

  void removeIndicator(ProIndicator indicator) {
    if (!_indicators.remove(indicator)) return;
    indicator.handle.remove();
    notifyListeners();
  }

  static List<IndicatorLineStyle> _stylesOf(IndicatorHandle h) => [
    for (final (i, line) in h.indicator.lines.indexed)
      IndicatorLineStyle(color: line.color, lineWidth: line.lineWidth, visible: h.series[i].options.visible),
  ];

  void _applyStyles(ProIndicator ind) {
    final series = ind.handle.series;
    for (var i = 0; i < series.length && i < ind.styles.length; i++) {
      final s = ind.styles[i];
      final visible = ind.visible && s.visible;
      final o = series[i].options;
      final next = switch (o) {
        LineSeriesOptions() => o.copyWith(color: s.color, lineWidth: s.lineWidth, visible: visible),
        HistogramSeriesOptions() => o.copyWith(color: s.color, visible: visible),
        _ => null,
      };
      if (next != null) series[i].applyOptions(next);
    }
  }

  ProIndicator? _restoreIndicator(Object? json) {
    if (json is! Map) return null;
    final spec = IndicatorCatalog.byId('${json['id']}');
    if (spec == null) return null;
    final values = <String, num>{
      for (final e in ((json['values'] as Map?) ?? const {}).entries)
        if (e.value is num) '${e.key}': e.value as num,
    };
    final styles = [for (final s in (json['styles'] as List?) ?? const []) ?IndicatorLineStyle.fromJson(s)];
    return addIndicator(
      spec,
      values: values,
      styles: styles.isEmpty ? null : styles,
      visible: json['visible'] != false,
    );
  }

  /// The indicators as JSON: a template to apply to another chart.
  List<Map<String, Object?>> saveIndicators() => [for (final i in _indicators) i.toJson()];

  /// Replaces the indicators with those of a [saveIndicators] template.
  /// Unknown ids are skipped.
  void restoreIndicators(List<Object?> template) {
    for (final i in _indicators) {
      i.handle.remove();
    }
    _indicators.clear();
    for (final t in template) {
      _restoreIndicator(t);
    }
    notifyListeners();
  }

  // ---- whole chart ----

  /// Everything on the chart as JSON-ready maps: the type, scale, volume,
  /// symbol, interval, indicators, drawings (anchored by time) and trading
  /// lines. The bars aren't included.
  Map<String, Object?> saveState() => {
    'version': 1,
    'type': _type.name,
    'scaleMode': scaleMode.name,
    'showVolume': _showVolume,
    'symbol': ?_symbol,
    'interval': ?_interval,
    'indicators': saveIndicators(),
    'drawings': codec.encodeAll(drawings.drawings, chart.timeScale().logicalToTime),
    'tradingLines': [for (final l in _trading.lines) _lineToJson(l)],
    'display': _displayToJson(),
  };

  /// Puts back what [saveState] saved. Call it after [setData], so drawings
  /// find their times. Parts missing from [state] are left as they are.
  void restoreState(Map<String, Object?> state) {
    if (state['type'] case final String name) {
      type = ProChartType.values.where((t) => t.name == name).firstOrNull ?? _type;
    }
    if (state['scaleMode'] case final String name) {
      scaleMode = PriceScaleMode.values.where((m) => m.name == name).firstOrNull ?? scaleMode;
    }
    if (state['showVolume'] case final bool v) showVolume = v;
    if (state['symbol'] case final String s) _symbol = s;
    if (state['interval'] case final String i) _interval = i;
    legend.options = _legend();
    if (state['display'] case final Map<Object?, Object?> display) {
      _displayFromJson(display);
    } else {
      _applyWatermark(rebuild: true);
    }
    if (state['indicators'] case final List<Object?> list) restoreIndicators(list);
    if (state['drawings'] case final List<Object?> list) {
      drawings.select(null);
      drawings.layer.drawings = codec.decodeAll(list, chart.timeScale().timeToLogical);
    }
    if (state['tradingLines'] case final List<Object?> list) {
      _trading.clear();
      for (final l in list) {
        if (_lineFromJson(l) case final line?) _trading.add(line);
      }
    }
    notifyListeners();
  }

  static Map<String, Object?> _lineToJson(TradingLine l) => {
    'id': l.id is String || l.id is num ? l.id : '${l.id}',
    'kind': l.kind.name,
    'price': l.price,
    'label': ?l.label,
    'quantity': ?l.quantity,
    'side': l.side.name,
    if (l.color != null) 'color': l.color!.toARGB32(),
    'draggable': l.draggable,
    'condition': l.condition.name,
    if (l.triggered) 'triggered': true,
  };

  static TradingLine? _lineFromJson(Object? json) {
    if (json is! Map || json['price'] is! num) return null;
    final kind = TradingLineKind.values.where((k) => k.name == json['kind']).firstOrNull;
    if (kind == null) return null;
    return TradingLine(
      id: json['id'] ?? Object(),
      kind: kind,
      price: (json['price'] as num).toDouble(),
      label: json['label'] as String?,
      quantity: (json['quantity'] as num?)?.toDouble(),
      side: TradeSide.values.where((s) => s.name == json['side']).firstOrNull ?? TradeSide.buy,
      color: json['color'] is int ? Color(json['color'] as int) : null,
      draggable: json['draggable'] as bool?,
      condition: AlertCondition.values.where((c) => c.name == json['condition']).firstOrNull ?? AlertCondition.crossing,
    )..triggered = json['triggered'] == true;
  }

  @override
  void dispose() {
    _watermark?.detach();
    legend.dispose();
    _trading.dispose();
    drawings.dispose();
    chart.dispose();
    super.dispose();
  }
}
