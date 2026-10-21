// Port of lightweight-charts src/gui/price-axis-widget.ts `_fixLabelOverlap`
// and `recalculateOverlapping`.

/// A price axis label being aligned: [coordinate] is where it belongs,
/// [render] where it ends up.
abstract class AlignableLabel {
  double get coordinate;
  double get render;
  set render(double value);
}

/// Moves overlapping labels apart around [center] (the main series'
/// label): labels above it are pushed up, labels below pushed down, the
/// center label shared by both groups, and groups shifted back inside the
/// scale when they would leave it.
void fixLabelOverlap(List<AlignableLabel> labels, double scaleHeight, double labelHeight, double center) {
  final top = labels.where((l) => l.coordinate <= center).toList()
    ..sort((l, r) => r.coordinate.compareTo(l.coordinate)); // center to top
  final bottom = labels.where((l) => l.coordinate > center).toList();
  // Share the center label.
  if (top.isNotEmpty && bottom.isNotEmpty) bottom.add(top.first);
  bottom.sort((l, r) => l.coordinate.compareTo(r.coordinate));

  final halfHeight = (labelHeight / 2).floorToDouble();
  for (final label in labels) {
    final c = label.coordinate;
    if (c > -halfHeight && c < halfHeight) label.render = halfHeight;
    if (c > scaleHeight - halfHeight && c < scaleHeight + halfHeight) label.render = scaleHeight - halfHeight;
  }

  _recalculateOverlapping(top, 1, scaleHeight, labelHeight);
  _recalculateOverlapping(bottom, -1, scaleHeight, labelHeight);
}

void _recalculateOverlapping(List<AlignableLabel> labels, int direction, double scaleHeight, double height) {
  if (labels.isEmpty) return;
  var groupStart = 0;
  var spaceBeforeGroup = direction == 1
      ? scaleHeight / 2 - (labels[0].render - height / 2)
      : labels[0].render - height / 2 - scaleHeight / 2;
  if (spaceBeforeGroup < 0) spaceBeforeGroup = 0;

  for (var i = 1; i < labels.length; i++) {
    final label = labels[i];
    final prev = labels[i - 1];
    final coordinate = label.render;
    final prevCoordinate = prev.render;
    final overlap = direction == 1 ? coordinate > prevCoordinate - height : coordinate < prevCoordinate + height;
    if (overlap) {
      final render = prevCoordinate - height * direction;
      label.render = render;
      final edge = render - direction * height / 2;
      final outOfViewport = direction == 1 ? edge < 0 : edge > scaleHeight;
      if (outOfViewport && spaceBeforeGroup > 0) {
        // Shift the whole group back towards the center.
        final desired = direction == 1 ? -1 - edge : edge - scaleHeight;
        final shift = desired < spaceBeforeGroup ? desired : spaceBeforeGroup;
        for (var k = groupStart; k < labels.length; k++) {
          labels[k].render = labels[k].render + direction * shift;
        }
        spaceBeforeGroup -= shift;
      }
    } else {
      groupStart = i;
      spaceBeforeGroup = direction == 1 ? prevCoordinate - height - coordinate : coordinate - (prevCoordinate + height);
    }
  }
}
