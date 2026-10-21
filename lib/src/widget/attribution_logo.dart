// Port of lightweight-charts src/gui/attribution-logo-widget.ts: the
// TradingView attribution required by the NOTICE file, drawn at the bottom
// left of the last pane.
import 'dart:ui';

const double attributionLogoWidth = 35;
const double attributionLogoHeight = 19;

/// Distance from the left and bottom edges of the last pane.
const double attributionLogoMargin = 10;

const String _strokePath =
    'M2 0H0v10h6v9h21.4l.5-1.3 6-15 1-2.7H23.7l-.5 1.3-.2.6a5 5 0 0 0-7-.9V0H2Zm20 17h4l5.2-13 .8-2h-7l-1 '
    '2.5-.2.5-1.5 3.8-.3.7V17Zm-.8-10a3 3 0 0 0 .7-2.7A3 3 0 1 0 16.8 7h4.4ZM14 7V2H2v6h6v9h4V7h2Z';
const String _fillPath = 'M14 2H2v6h6v9h6V2Zm12 15h-7l6-15h7l-6 15Zm-7-9a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z';

Path? _strokeCache;
Path? _fillCache;

/// Draws the logo with its top-left corner at [origin]. [darkBackground]
/// picks the light-on-dark variant, as upstream does from the text color.
void paintAttributionLogo(Canvas canvas, Offset origin, {required bool darkBackground}) {
  final stroke = _strokeCache ??= parseSvgPath(_strokePath)..fillType = PathFillType.evenOdd;
  final fill = _fillCache ??= parseSvgPath(_fillPath)..fillType = PathFillType.evenOdd;
  canvas.save();
  canvas.translate(origin.dx, origin.dy);
  canvas.clipRect(const Rect.fromLTWH(0, 0, attributionLogoWidth, attributionLogoHeight));
  canvas.drawPath(stroke, Paint()..color = darkBackground ? const Color(0xFF131722) : const Color(0xFFFFFFFF));
  canvas.drawPath(fill, Paint()..color = darkBackground ? const Color(0xFFD1D4DC) : const Color(0xFF131722));
  canvas.restore();
}

/// Parses the subset of SVG path data used by the logo: M, L, H, V, A, Z in
/// absolute and relative forms.
Path parseSvgPath(String data) {
  final tokens = RegExp(r'[MmLlHhVvAaZz]|-?(?:\d+\.?\d*|\.\d+)(?:e-?\d+)?')
      .allMatches(data)
      .map((m) => m.group(0)!)
      .toList();
  final path = Path();
  var i = 0;
  var command = 'M';
  var x = 0.0, y = 0.0, startX = 0.0, startY = 0.0;

  bool isCommand(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
  double next() => double.parse(tokens[i++]);

  while (i < tokens.length) {
    if (isCommand(tokens[i])) command = tokens[i++];
    final relative = command == command.toLowerCase();
    switch (command.toUpperCase()) {
      case 'M':
        final nx = next(), ny = next();
        x = relative ? x + nx : nx;
        y = relative ? y + ny : ny;
        path.moveTo(x, y);
        startX = x;
        startY = y;
        // Further pairs after a moveto are linetos.
        command = relative ? 'l' : 'L';
      case 'L':
        final nx = next(), ny = next();
        x = relative ? x + nx : nx;
        y = relative ? y + ny : ny;
        path.lineTo(x, y);
      case 'H':
        final nx = next();
        x = relative ? x + nx : nx;
        path.lineTo(x, y);
      case 'V':
        final ny = next();
        y = relative ? y + ny : ny;
        path.lineTo(x, y);
      case 'A':
        final rx = next(), ry = next(), rotation = next();
        final largeArc = next() != 0;
        final sweep = next() != 0;
        final nx = next(), ny = next();
        x = relative ? x + nx : nx;
        y = relative ? y + ny : ny;
        path.arcToPoint(
          Offset(x, y),
          radius: Radius.elliptical(rx, ry),
          rotation: rotation,
          largeArc: largeArc,
          clockwise: sweep,
        );
      case 'Z':
        path.close();
        x = startX;
        y = startY;
      default:
        throw FormatException('Unsupported SVG path command $command');
    }
  }
  return path;
}

/// Whether the logo should use the dark variant for [textColor], like
/// upstream's grayscale > 160 check.
bool isDarkTheme(Color textColor) {
  final gray = 0.199 * textColor.r * 255 + 0.687 * textColor.g * 255 + 0.114 * textColor.b * 255;
  return gray > 160;
}

/// Hit area of the logo in chart coordinates.
Rect attributionLogoRect(Rect lastPaneRect) => Rect.fromLTWH(
      lastPaneRect.left + attributionLogoMargin,
      lastPaneRect.bottom - attributionLogoMargin - attributionLogoHeight,
      attributionLogoWidth,
      attributionLogoHeight,
    );
