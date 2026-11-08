// Picking indicators from the catalog and editing their inputs and styles.
import 'package:flutter/material.dart';

import '../indicators/catalog.dart';
import 'pro_chart.dart' show ColorMenuButton;
import 'pro_chart_controller.dart';
import 'pro_chart_strings.dart';

/// A bottom sheet with the indicators on [pro] (show / hide, settings,
/// remove) and the catalog to add from, searchable.
Future<void> showIndicatorSheet(BuildContext context, ProChartController pro) {
  final strings = ProChartStrings.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => ProChartStringsScope(
      strings: strings,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scroll) => IndicatorPicker(controller: pro, scrollController: scroll),
      ),
    ),
  );
}

/// The content of [showIndicatorSheet]; embed it elsewhere (a side panel
/// on desktop) as you like.
class IndicatorPicker extends StatefulWidget {
  const IndicatorPicker({super.key, required this.controller, this.scrollController});

  final ProChartController controller;
  final ScrollController? scrollController;

  @override
  State<IndicatorPicker> createState() => _IndicatorPickerState();
}

class _IndicatorPickerState extends State<IndicatorPicker> {
  String _query = '';

  ProChartController get _pro => widget.controller;

  @override
  void initState() {
    super.initState();
    _pro.addListener(_changed);
  }

  @override
  void dispose() {
    _pro.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = ProChartStrings.of(context);
    // Searched in the shown titles too, so a translated name finds it.
    final q = _query.trim().toLowerCase();
    final matches = [
      for (final s in IndicatorCatalog.available)
        if (s.matches(_query) || strings.titleOf(s).toLowerCase().contains(q)) s,
    ];
    final active = _pro.indicators;
    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: strings.searchIndicators,
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (q) => setState(() => _query = q),
          ),
        ),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            children: [
              if (active.isNotEmpty && _query.isEmpty) ...[
                header(strings.onTheChart),
                for (final ind in active)
                  ListTile(
                    dense: true,
                    title: Text(ind.name),
                    subtitle: Text(strings.titleOf(ind.spec)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: ind.visible ? strings.hide : strings.show,
                          icon: Icon(ind.visible ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => _pro.updateIndicator(ind, visible: !ind.visible),
                        ),
                        IconButton(
                          tooltip: strings.settings,
                          icon: const Icon(Icons.settings_outlined),
                          onPressed: () => showIndicatorSettings(context, _pro, ind),
                        ),
                        IconButton(
                          tooltip: strings.remove,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _pro.removeIndicator(ind),
                        ),
                      ],
                    ),
                  ),
              ],
              for (final group in IndicatorGroup.values)
                if (matches.where((s) => s.group == group).toList() case final specs when specs.isNotEmpty) ...[
                  header(strings.groupLabel(group)),
                  for (final spec in specs)
                    ListTile(
                      dense: true,
                      enabled: !spec.needsVolume || _pro.volumeSeries != null,
                      title: Text(strings.titleOf(spec)),
                      subtitle: spec.needsVolume && _pro.volumeSeries == null ? Text(strings.needsVolume) : null,
                      trailing: const Icon(Icons.add),
                      onTap: () {
                        _pro.addIndicator(spec);
                        ScaffoldMessenger.maybeOf(context)
                          ?..hideCurrentSnackBar()
                          ..showSnackBar(
                            SnackBar(
                              content: Text(strings.addedMessage(strings.titleOf(spec))),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                      },
                    ),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A dialog to change [indicator]'s inputs and line styles.
Future<void> showIndicatorSettings(BuildContext context, ProChartController pro, ProIndicator indicator) {
  final strings = ProChartStrings.of(context);
  return showDialog<void>(
    context: context,
    builder: (_) => ProChartStringsScope(
      strings: strings,
      child: IndicatorSettingsDialog(controller: pro, indicator: indicator),
    ),
  );
}

class IndicatorSettingsDialog extends StatefulWidget {
  const IndicatorSettingsDialog({super.key, required this.controller, required this.indicator});

  final ProChartController controller;
  final ProIndicator indicator;

  @override
  State<IndicatorSettingsDialog> createState() => _IndicatorSettingsDialogState();
}

class _IndicatorSettingsDialogState extends State<IndicatorSettingsDialog> {
  late final Map<String, TextEditingController> _fields = {
    for (final p in widget.indicator.spec.params)
      p.key: TextEditingController(text: _format(p, widget.indicator.values[p.key]!)),
  };
  late List<IndicatorLineStyle> _styles = List.of(widget.indicator.styles);

  static String _format(IndicatorParam p, num v) => p.isInteger ? v.round().toString() : v.toString();

  @override
  void dispose() {
    for (final f in _fields.values) {
      f.dispose();
    }
    super.dispose();
  }

  /// The inputs typed in, clamped to each one's range; `null` if one isn't
  /// a number.
  Map<String, num>? _values() {
    final out = <String, num>{};
    for (final p in widget.indicator.spec.params) {
      final v = num.tryParse(_fields[p.key]!.text.trim());
      if (v == null) return null;
      final clamped = v.clamp(p.min, p.max);
      out[p.key] = p.isInteger ? clamped.round() : clamped;
    }
    return out;
  }

  void _resetDefaults() {
    final spec = widget.indicator.spec;
    for (final p in spec.params) {
      _fields[p.key]!.text = _format(p, p.defaultValue);
    }
    final lines = spec.build().lines;
    setState(() => _styles = [for (final l in lines) IndicatorLineStyle(color: l.color, lineWidth: l.lineWidth)]);
  }

  void _apply() {
    final values = _values();
    if (values == null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(ProChartStrings.of(context).inputsMustBeNumbers)));
      return;
    }
    final ind = widget.indicator;
    final changed = values.entries.any((e) => ind.values[e.key] != e.value);
    widget.controller.updateIndicator(ind, values: changed ? values : null, styles: _styles);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final ind = widget.indicator;
    final lines = ind.handle.indicator.lines;
    final theme = Theme.of(context);
    final strings = ProChartStrings.of(context);
    return AlertDialog(
      title: Text(strings.titleOf(ind.spec)),
      scrollable: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ind.spec.params.isNotEmpty) ...[
            Text(strings.inputs, style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            for (final p in ind.spec.params)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: _fields[p.key],
                  keyboardType: TextInputType.numberWithOptions(decimal: !p.isInteger),
                  decoration: InputDecoration(
                    labelText: strings.paramLabelOf(ind.spec, p),
                    helperText: '${_format(p, p.min)} – ${_format(p, p.max)}',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
          ],
          Text(strings.style, style: theme.textTheme.labelLarge),
          for (var i = 0; i < _styles.length && i < lines.length; i++)
            Row(
              children: [
                Checkbox(
                  value: _styles[i].visible,
                  onChanged: (v) => setState(() => _styles[i] = _styles[i].copyWith(visible: v ?? true)),
                ),
                Expanded(child: Text(lines[i].name, overflow: TextOverflow.ellipsis)),
                ColorMenuButton(
                  color: _styles[i].color,
                  onSelected: (c) => setState(() => _styles[i] = _styles[i].copyWith(color: c)),
                ),
                DropdownButton<double>(
                  value: const [1.0, 1.5, 2.0, 3.0, 4.0].contains(_styles[i].lineWidth) ? _styles[i].lineWidth : null,
                  hint: Text('${_styles[i].lineWidth}'),
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final w in const [1.0, 1.5, 2.0, 3.0, 4.0]) DropdownMenuItem(value: w, child: Text('${w}px')),
                  ],
                  onChanged: (w) => setState(() => _styles[i] = _styles[i].copyWith(lineWidth: w)),
                ),
              ],
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: _resetDefaults, child: Text(strings.defaults)),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(strings.cancel)),
        FilledButton(onPressed: _apply, child: Text(strings.ok)),
      ],
    );
  }
}
