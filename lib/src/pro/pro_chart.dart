// A trading screen around a ProChartController: a top bar (symbol,
// interval, chart type, indicators, undo, scale), a drawing toolbar and a
// floating style bar for the selected drawing.
import 'package:flutter/material.dart';

import '../options.dart';
import '../plugins/drawings.dart';
import '../widget/swm_chart.dart';
import 'drawing_tools.dart';
import 'indicator_sheet.dart';
import 'pro_chart_controller.dart';

/// The chart of [controller] with toolbars, like TradingView's:
///
/// * a top bar: the symbol ([onSymbolTap]), the interval ([intervals],
///   [onIntervalChanged] — load the bars there), the chart type,
///   indicators, undo / redo and scale options, then your [actions];
/// * a drawing toolbar on the left, tools in groups, with magnet, keep
///   drawing, hide and remove all;
/// * over the chart, a style bar for the selected drawing: color, width,
///   line style, text, lock, duplicate, delete.
///
/// ```dart
/// SwmProChart(
///   controller: pro,
///   intervals: const ['15m', '1h', '4h', '1D'],
///   onIntervalChanged: (i) async => pro.setData(await api.bars(symbol, i)),
/// )
/// ```
class SwmProChart extends StatefulWidget {
  const SwmProChart({
    super.key,
    required this.controller,
    this.intervals = const ['1m', '5m', '15m', '1h', '4h', '1D', '1W'],
    this.onIntervalChanged,
    this.onSymbolTap,
    this.actions = const [],
    this.showTopBar = true,
    this.showDrawingToolbar = true,
  });

  final ProChartController controller;
  final List<String> intervals;

  /// The user picked an interval ([ProChartController.interval] is set
  /// already); load its bars.
  final void Function(String interval)? onIntervalChanged;
  final VoidCallback? onSymbolTap;

  /// Extra buttons at the end of the top bar.
  final List<Widget> actions;
  final bool showTopBar;
  final bool showDrawingToolbar;

  @override
  State<SwmProChart> createState() => _SwmProChartState();
}

class _SwmProChartState extends State<SwmProChart> {
  ProChartController get _pro => widget.controller;

  @override
  void initState() {
    super.initState();
    _pro.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(SwmProChart old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    _pro.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    // A new text or callout: ask for its text.
    final created = _pro.takeCreated();
    if (created is TextDrawing || created is CalloutDrawing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) editDrawingText(context, _pro, created!);
      });
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final selected = _pro.drawings.selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showTopBar) ...[
          ProChartTopBar(
            controller: _pro,
            intervals: widget.intervals,
            onIntervalChanged: widget.onIntervalChanged,
            onSymbolTap: widget.onSymbolTap,
            actions: widget.actions,
          ),
          const Divider(height: 1),
        ],
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.showDrawingToolbar) ...[DrawingToolbar(controller: _pro), const VerticalDivider(width: 1)],
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: SwmChart(controller: _pro.chart)),
                    if (selected != null)
                      Positioned(
                        top: 6,
                        left: 6,
                        right: 70,
                        child: Center(
                          child: DrawingStyleBar(controller: _pro, drawing: selected),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---- top bar ----

/// Symbol, interval, chart type, indicators, undo / redo and scale options.
class ProChartTopBar extends StatelessWidget {
  const ProChartTopBar({
    super.key,
    required this.controller,
    this.intervals = const ['1m', '5m', '15m', '1h', '4h', '1D', '1W'],
    this.onIntervalChanged,
    this.onSymbolTap,
    this.actions = const [],
  });

  final ProChartController controller;
  final List<String> intervals;
  final void Function(String interval)? onIntervalChanged;
  final VoidCallback? onSymbolTap;
  final List<Widget> actions;

  static IconData typeIcon(ProChartType type) => switch (type) {
    ProChartType.candles => Icons.candlestick_chart,
    ProChartType.hollowCandles => Icons.candlestick_chart_outlined,
    ProChartType.bars => Icons.bar_chart,
    ProChartType.line => Icons.show_chart,
    ProChartType.area => Icons.area_chart,
    ProChartType.baseline => Icons.ssid_chart,
    ProChartType.heikinAshi => Icons.view_week,
  };

  @override
  Widget build(BuildContext context) {
    final pro = controller;
    final theme = Theme.of(context);
    final symbol = pro.symbol;
    // On a phone the indicators button goes icon-only, so undo and the
    // settings stay on screen.
    final compact = MediaQuery.sizeOf(context).width < 520;
    return SizedBox(
      height: 44,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            if (symbol != null)
              TextButton(
                onPressed: onSymbolTap,
                child: Text(symbol, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
            if (intervals.isNotEmpty)
              PopupMenuButton<String>(
                tooltip: 'Interval',
                initialValue: pro.interval,
                onSelected: (i) {
                  pro.interval = i;
                  onIntervalChanged?.call(i);
                },
                itemBuilder: (_) => [for (final i in intervals) PopupMenuItem(value: i, child: Text(i))],
                child: _BarLabel(pro.interval ?? intervals.first, trailing: Icons.arrow_drop_down),
              ),
            PopupMenuButton<ProChartType>(
              tooltip: 'Chart type',
              initialValue: pro.type,
              onSelected: (t) => pro.type = t,
              itemBuilder: (_) => [
                for (final t in ProChartType.values)
                  PopupMenuItem(
                    value: t,
                    child: Row(children: [Icon(typeIcon(t), size: 20), const SizedBox(width: 12), Text(t.label)]),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Icon(typeIcon(pro.type), size: 22),
              ),
            ),
            if (compact)
              IconButton(
                tooltip: 'Indicators',
                icon: const Icon(Icons.functions),
                onPressed: () => showIndicatorSheet(context, pro),
              )
            else
              TextButton.icon(
                onPressed: () => showIndicatorSheet(context, pro),
                icon: const Icon(Icons.functions, size: 20),
                label: const Text('Indicators'),
              ),
            const SizedBox(height: 24, child: VerticalDivider(width: 8)),
            IconButton(
              tooltip: 'Undo',
              icon: const Icon(Icons.undo),
              onPressed: pro.drawings.canUndo ? pro.drawings.undo : null,
            ),
            IconButton(
              tooltip: 'Redo',
              icon: const Icon(Icons.redo),
              onPressed: pro.drawings.canRedo ? pro.drawings.redo : null,
            ),
            PopupMenuButton<String>(
              tooltip: 'Chart settings',
              icon: const Icon(Icons.tune),
              onSelected: (v) {
                switch (v) {
                  case 'log':
                    pro.scaleMode = pro.scaleMode == PriceScaleMode.logarithmic
                        ? PriceScaleMode.normal
                        : PriceScaleMode.logarithmic;
                  case 'percent':
                    pro.scaleMode = pro.scaleMode == PriceScaleMode.percentage
                        ? PriceScaleMode.normal
                        : PriceScaleMode.percentage;
                  case 'volume':
                    pro.showVolume = !pro.showVolume;
                }
              },
              itemBuilder: (_) => [
                CheckedPopupMenuItem(
                  value: 'log',
                  checked: pro.scaleMode == PriceScaleMode.logarithmic,
                  child: const Text('Log scale'),
                ),
                CheckedPopupMenuItem(
                  value: 'percent',
                  checked: pro.scaleMode == PriceScaleMode.percentage,
                  child: const Text('Percent scale'),
                ),
                CheckedPopupMenuItem(value: 'volume', checked: pro.showVolume, child: const Text('Volume')),
              ],
            ),
            ...actions,
          ],
        ),
      ),
    );
  }
}

class _BarLabel extends StatelessWidget {
  const _BarLabel(this.text, {this.trailing});

  final String text;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
        if (trailing != null) Icon(trailing, size: 18),
      ],
    ),
  );
}

// ---- drawing toolbar ----

/// The drawing tools in groups, down the left side: tap a group to pick
/// one of its tools.
class DrawingToolbar extends StatefulWidget {
  const DrawingToolbar({super.key, required this.controller, this.groups});

  final ProChartController controller;

  /// `null` for [DrawingTools.groups].
  final List<DrawingToolGroup>? groups;

  @override
  State<DrawingToolbar> createState() => _DrawingToolbarState();
}

class _DrawingToolbarState extends State<DrawingToolbar> {
  // The tool each group shows: the one picked last.
  final Map<int, DrawingToolSpec> _shown = {};

  List<DrawingToolGroup> get _groups => widget.groups ?? DrawingTools.groups;

  Future<void> _pick(BuildContext buttonContext, int index) async {
    final group = _groups[index];
    final box = buttonContext.findRenderObject()! as RenderBox;
    final overlay = Overlay.of(buttonContext).context.findRenderObject()! as RenderBox;
    final at = box.localToGlobal(Offset(box.size.width, 0), ancestor: overlay);
    final pro = widget.controller;
    final tool = await showMenu<DrawingToolSpec>(
      context: buttonContext,
      position: RelativeRect.fromLTRB(at.dx, at.dy, overlay.size.width - at.dx, 0),
      items: [
        PopupMenuItem(enabled: false, height: 32, child: Text(group.label)),
        for (final t in group.tools)
          PopupMenuItem(
            value: t,
            child: Row(
              children: [
                Icon(t.icon, size: 20, color: pro.activeTool == t ? Theme.of(buttonContext).colorScheme.primary : null),
                const SizedBox(width: 12),
                Text(t.label),
              ],
            ),
          ),
      ],
    );
    if (tool == null) return;
    setState(() => _shown[index] = tool);
    pro.activeTool = tool;
  }

  @override
  Widget build(BuildContext context) {
    final pro = widget.controller;
    final active = pro.activeTool;
    final scheme = Theme.of(context).colorScheme;
    Widget button(IconData icon, String tooltip, VoidCallback? onPressed, {bool selected = false}) => IconButton(
      tooltip: tooltip,
      isSelected: selected,
      icon: Icon(icon, size: 22),
      color: selected ? scheme.primary : null,
      style: IconButton.styleFrom(
        backgroundColor: selected ? scheme.primaryContainer.withValues(alpha: 0.6) : null,
        minimumSize: const Size(40, 40),
        padding: EdgeInsets.zero,
      ),
      onPressed: onPressed,
    );
    return SizedBox(
      width: 46,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            button(Icons.near_me_outlined, 'Cursor', () => pro.activeTool = null, selected: active == null),
            for (var i = 0; i < _groups.length; i++)
              Builder(
                builder: (buttonContext) {
                  final group = _groups[i];
                  final inGroup = active != null && group.tools.contains(active);
                  final shown = inGroup ? active : (_shown[i] ?? group.tools.first);
                  return button(shown.icon, group.label, () => _pick(buttonContext, i), selected: inGroup);
                },
              ),
            const Divider(indent: 8, endIndent: 8),
            button(Icons.adjust, 'Magnet', () => pro.magnet = !pro.magnet, selected: pro.magnet),
            button(
              Icons.push_pin_outlined,
              'Keep drawing',
              () => pro.keepDrawing = !pro.keepDrawing,
              selected: pro.keepDrawing,
            ),
            button(
              pro.drawingsHidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              pro.drawingsHidden ? 'Show drawings' : 'Hide drawings',
              pro.drawings.drawings.isEmpty ? null : () => pro.drawingsHidden = !pro.drawingsHidden,
            ),
            button(
              Icons.delete_sweep_outlined,
              'Remove drawings',
              pro.drawings.drawings.isEmpty ? null : pro.drawings.clear,
            ),
          ],
        ),
      ),
    );
  }
}

// ---- style bar ----

/// Edits the selected [drawing]: color, width, line style, text, lock,
/// duplicate and delete. Each change can be undone.
class DrawingStyleBar extends StatelessWidget {
  const DrawingStyleBar({super.key, required this.controller, required this.drawing});

  final ProChartController controller;
  final Drawing drawing;

  void _style(DrawingStyle Function(DrawingStyle s) change) =>
      controller.drawings.update(drawing.id, (d) => d.style = change(d.style));

  @override
  Widget build(BuildContext context) {
    final d = drawing;
    final hasText = d is TextDrawing || d is CalloutDrawing;
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(8),
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ColorMenuButton(
              color: d.style.color,
              tooltip: 'Color',
              onSelected: (c) => _style((s) => s.copyWith(color: c, fillColor: _fillFor(s.fillColor, c))),
            ),
            PopupMenuButton<double>(
              tooltip: 'Width',
              icon: const Icon(Icons.line_weight, size: 20),
              initialValue: d.style.lineWidth,
              onSelected: (w) => _style((s) => s.copyWith(lineWidth: w)),
              itemBuilder: (_) => [
                for (final w in const [1.0, 1.5, 2.0, 3.0, 4.0])
                  PopupMenuItem(
                    value: w,
                    child: Row(
                      children: [
                        Container(width: 32, height: w, color: d.style.color),
                        const SizedBox(width: 12),
                        Text('${w}px'),
                      ],
                    ),
                  ),
              ],
            ),
            PopupMenuButton<LineStyle>(
              tooltip: 'Line style',
              icon: const Icon(Icons.more_horiz, size: 20),
              initialValue: d.style.lineStyle,
              onSelected: (v) => _style((s) => s.copyWith(lineStyle: v)),
              itemBuilder: (_) => [
                for (final v in DrawingTools.lineStyles)
                  PopupMenuItem(value: v, child: Text(v.name[0].toUpperCase() + v.name.substring(1))),
              ],
            ),
            if (hasText)
              IconButton(
                tooltip: 'Text',
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: () => editDrawingText(context, controller, d),
              ),
            IconButton(
              tooltip: d.locked ? 'Unlock' : 'Lock',
              icon: Icon(d.locked ? Icons.lock : Icons.lock_open, size: 20),
              onPressed: () => controller.drawings.update(d.id, (x) => x.locked = !x.locked),
            ),
            IconButton(
              tooltip: 'Duplicate',
              icon: const Icon(Icons.copy, size: 20),
              onPressed: () => controller.drawings.duplicate(d.id, codec: controller.codec),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => controller.drawings.remove(d.id),
            ),
          ],
        ),
      ),
    );
  }

  /// A fill follows the line color, keeping its transparency.
  static Color? _fillFor(Color? fill, Color color) => fill == null ? null : color.withValues(alpha: fill.a);
}

/// A round swatch of [color] that opens [DrawingTools.palette].
class ColorMenuButton extends StatelessWidget {
  const ColorMenuButton({super.key, required this.color, required this.onSelected, this.tooltip, this.size = 20});

  final Color color;
  final ValueChanged<Color> onSelected;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final border = Theme.of(context).colorScheme.outline;
    Widget swatch(Color c, double s) => Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        border: Border.all(color: border, width: 1),
      ),
    );
    return PopupMenuButton<Color>(
      tooltip: tooltip,
      onSelected: onSelected,
      itemBuilder: (menuContext) => [
        PopupMenuItem(
          enabled: false,
          child: SizedBox(
            width: 196,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in DrawingTools.palette)
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.pop(menuContext, c),
                    child: swatch(c, 26),
                  ),
              ],
            ),
          ),
        ),
      ],
      child: Padding(padding: const EdgeInsets.all(12), child: swatch(color, size)),
    );
  }
}

/// Asks for a new text for a [TextDrawing] or [CalloutDrawing].
Future<void> editDrawingText(BuildContext context, ProChartController pro, Drawing drawing) async {
  final current = switch (drawing) {
    final TextDrawing d => d.text,
    final CalloutDrawing d => d.text,
    _ => null,
  };
  if (current == null) return;
  final text = await showDialog<String>(context: context, builder: (_) => _TextDialog(current));
  if (text == null || text == current) return;
  pro.drawings.update(drawing.id, (d) {
    if (d is TextDrawing) d.text = text;
    if (d is CalloutDrawing) d.text = text;
  });
}

class _TextDialog extends StatefulWidget {
  const _TextDialog(this.text);

  final String text;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  // Owned here: the dialog still builds while it animates out.
  late final TextEditingController _field = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Text'),
    content: TextField(
      controller: _field,
      autofocus: true,
      maxLines: null,
      onSubmitted: (v) => Navigator.pop(context, v),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, _field.text), child: const Text('OK')),
    ],
  );
}
