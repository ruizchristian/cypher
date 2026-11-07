import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;

/// Usage: icontool <source.png> <outDir>
/// Writes icon.png (white square, logo 62% tall), icon_foreground.png and
/// icon_monochrome.png (transparent, logo 46% tall to fit the adaptive-icon
/// safe circle).
void main(List<String> args) {
  final src = img.decodePng(File(args[0]).readAsBytesSync())!;
  final out = Directory(args[1])..createSync(recursive: true);

  // Ink = opaque and dark. The source background is transparent (stored as
  // black with alpha 0), so alpha must be part of it.
  double ink(img.Pixel p) =>
      (p.a / p.maxChannelValue) * (1 - p.luminanceNormalized);

  // Logo bounds: pixels with real ink.
  var minX = src.width, minY = src.height, maxX = 0, maxY = 0;
  for (final p in src) {
    if (ink(p) > 0.25) {
      minX = min(minX, p.x); maxX = max(maxX, p.x);
      minY = min(minY, p.y); maxY = max(maxY, p.y);
    }
  }
  final logo = img.copyCrop(src, x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1);
  stdout.writeln('source ${src.width}x${src.height}, logo bounds ($minX,$minY)-($maxX,$maxY) = ${logo.width}x${logo.height}');

  // Coverage: 0 = background, 1 = full ink, from luminance (keeps antialiasing).
  img.Image place(double heightFraction, {required bool opaque}) {
    const size = 1024;
    final h = (size * heightFraction).round();
    final w = (logo.width * h / logo.height).round();
    final scaled = img.copyResize(logo, width: w, height: h, interpolation: img.Interpolation.cubic);
    final canvas = img.Image(width: size, height: size, numChannels: 4);
    img.fill(canvas, color: opaque ? img.ColorRgba8(255, 255, 255, 255) : img.ColorRgba8(0, 0, 0, 0));
    final ox = (size - w) ~/ 2, oy = (size - h) ~/ 2;
    for (final p in scaled) {
      final coverage = ink(p).clamp(0.0, 1.0);
      if (coverage <= 0) continue;
      final a = (coverage * 255).round();
      if (opaque) {
        final v = 255 - a;
        canvas.setPixelRgba(ox + p.x, oy + p.y, v, v, v, 255);
      } else {
        canvas.setPixelRgba(ox + p.x, oy + p.y, 0, 0, 0, a);
      }
    }
    return canvas;
  }

  File('${out.path}/icon.png').writeAsBytesSync(img.encodePng(place(0.62, opaque: true)));
  final fg = img.encodePng(place(0.46, opaque: false));
  File('${out.path}/icon_foreground.png').writeAsBytesSync(fg);
  File('${out.path}/icon_monochrome.png').writeAsBytesSync(fg);
  stdout.writeln('wrote icon.png, icon_foreground.png, icon_monochrome.png to ${out.path}');
}
