// The chart's look beyond its data: crosshair, grid and watermark.
import 'package:flutter/material.dart';

import '../options.dart';
import 'drawing_tools.dart';
import 'pro_chart_controller.dart';
import 'pro_chart_strings.dart';

/// A bottom sheet with [pro]'s display settings: grid lines, the symbol in
/// the background and the crosshair's line style, color and width. Picks
/// apply at once; they're saved with `saveState`.
Future<void> showChartDisplaySheet(BuildContext context, ProChartController pro) {
  final strings = ProChartStrings.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => ProChartStringsScope(
      strings: strings,
      child: ChartDisplaySettings(controller: pro),
    ),
  );
}

/// The content of [showChartDisplaySheet]; embed it elsewhere as you like.
class ChartDisplaySettings extends StatelessWidget {
  const ChartDisplaySettings({super.key, required this.controller});

  final ProChartController controller;

  static const _styles = [LineStyle.solid, LineStyle.dashed, LineStyle.largeDashed, LineStyle.dotted];

  static const _widths = [1.0, 1.5, 2.0];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final pro = controller;
      final strings = ProChartStrings.of(context);
      final theme = Theme.of(context);
      final label = theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant);
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    strings.chartDisplay,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(onPressed: pro.resetDisplay, child: Text(strings.reset)),
              ],
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(strings.gridLines),
              value: pro.showGrid,
              onChanged: (v) => pro.showGrid = v,
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(strings.symbolInBackground),
              value: pro.showWatermark,
              onChanged: (v) => pro.showWatermark = v,
            ),
            const SizedBox(height: 12),
            Text(strings.crosshair, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text(strings.lineStyle, style: label),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in _styles)
                  ChoiceChip(
                    label: Text(strings.lineStyleLabel(s)),
                    selected: pro.crosshairStyle == s,
                    onSelected: (_) => pro.crosshairStyle = s,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(strings.color, style: label),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final c in [ProChartController.defaultCrosshairColor, ...DrawingTools.palette])
                  _Swatch(
                    color: c,
                    selected: pro.crosshairColor.toARGB32() == c.toARGB32(),
                    onTap: () => pro.crosshairColor = c,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(strings.width, style: label),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final w in _widths)
                  ChoiceChip(
                    label: Text(w == w.roundToDouble() ? '${w.round()}' : '$w'),
                    selected: pro.crosshairWidth == w,
                    onSelected: (_) => pro.crosshairWidth = w,
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 3 : 1),
        ),
      ),
    );
  }
}
