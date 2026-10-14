import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

class PetAtlasFrames {
  const PetAtlasFrames({required this.rgba, required this.width,
    required this.height, required this.padding, required this.baselines,
    required this.fitScale, required this.bounds, required this.cellWidth,
    required this.cellHeight});
  final Uint8List rgba;
  final int width, height, padding, cellWidth, cellHeight;
  final List<double> baselines;
  final List<Rect> bounds;
  final double fitScale;
  double get frameScale => (cellWidth + padding * 2) / cellWidth;

  Offset remapPoint(Offset point) => Offset(
    (point.dx * cellWidth + padding) / (cellWidth + padding * 2),
    (point.dy * cellHeight + padding) / (cellHeight + padding * 2));
}

/// Identify complete matte components BEFORE assigning them to animation cells.
/// A paw or ear crossing a grid line still belongs to the same silhouette.
PetAtlasFrames buildPetAtlasFrames(Uint8List color, Uint8List mask,
    int width, int height, {required int columns, required int rows}) {
  if (width % columns != 0 || height % rows != 0 ||
      color.length != width * height * 4 || mask.length != color.length) {
    throw StateError('Invalid pet atlas dimensions');
  }
  final cw = width ~/ columns, ch = height ~/ rows;
  final labels = Int32List(width * height);
  final stack = Int32List(width * height);
  final components = <({Rect bounds, int area, int frame})>[];
  var label = 0;
  for (var pixel = 0; pixel < labels.length; pixel++) {
    if (labels[pixel] != 0 || mask[pixel * 4] <= 8) continue;
    label++;
    var length = 1, area = 0;
    var left = width, right = 0, top = height, bottom = 0;
    var sumX = 0.0, sumY = 0.0;
    labels[pixel] = label;
    stack[0] = pixel;
    while (length > 0) {
      final current = stack[--length];
      final x = current % width, y = current ~/ width;
      area++; sumX += x; sumY += y;
      left = math.min(left, x); right = math.max(right, x);
      top = math.min(top, y); bottom = math.max(bottom, y);
      void visit(int next) {
        if (labels[next] != 0 || mask[next * 4] <= 8) return;
        labels[next] = label;
        stack[length++] = next;
      }
      if (x > 0) visit(current - 1);
      if (x + 1 < width) visit(current + 1);
      if (y > 0) visit(current - width);
      if (y + 1 < height) visit(current + width);
    }
    final col = (sumX / area / cw).floor().clamp(0, columns - 1);
    final row = (sumY / area / ch).floor().clamp(0, rows - 1);
    components.add((bounds: Rect.fromLTRB(left.toDouble(), top.toDouble(),
      (right + 1).toDouble(), (bottom + 1).toDouble()), area: area,
      frame: row * columns + col));
  }
  final frameBounds = List<Rect?>.filled(columns * rows, null);
  final ownership = List<int>.filled(label + 1, -1);
  for (var i = 0; i < components.length; i++) {
    final component = components[i];
    // Isolated matte speckles are not a separate pose or a piece of another pet.
    if (component.area < cw * ch * .01) continue;
    final old = frameBounds[component.frame];
    frameBounds[component.frame] = old == null
        ? component.bounds : old.expandToInclude(component.bounds);
    ownership[i + 1] = component.frame;
  }
  if (frameBounds.any((bounds) => bounds == null)) {
    throw StateError('Pet matte does not contain one complete pose per cell');
  }
  final bounds = frameBounds.cast<Rect>();
  var padding = 2;
  var fitExtent = 1.0;
  for (var i = 0; i < bounds.length; i++) {
    final b = bounds[i];
    final x = (i % columns) * cw, y = (i ~/ columns) * ch;
    padding = math.max(padding, math.max(math.max(x - b.left, b.right - x - cw),
      math.max(y - b.top, b.bottom - y - ch)).ceil() + 2);
    final centerX = x + cw / 2;
    fitExtent = math.max(fitExtent, math.max(b.height / ch,
      2 * math.max((b.left - centerX).abs(), (b.right - centerX).abs()) / cw));
  }
  final pw = cw + padding * 2, ph = ch + padding * 2;
  final packedWidth = pw * columns, packedHeight = ph * rows;
  final rgba = Uint8List(packedWidth * packedHeight * 4);
  final ground = List<int>.filled(bounds.length, -1);
  // Measure grounded paws on the complete silhouette, not on a clipped cell.
  for (var frame = 0; frame < bounds.length; frame++) {
    final b = bounds[frame];
    for (var y = b.bottom.toInt() - 1; y >= b.top.toInt(); y--) {
      var solid = 0;
      for (var x = b.left.toInt(); x < b.right.toInt(); x++) {
        final pixel = y * width + x;
        if (ownership[labels[pixel]] == frame && mask[pixel * 4] > 48) solid++;
      }
      if (solid >= 4) { ground[frame] = y; break; }
    }
    if (ground[frame] < 0) throw StateError('Pet pose has no grounded silhouette');
  }
  for (var pixel = 0; pixel < labels.length; pixel++) {
    final frame = ownership[labels[pixel]];
    if (frame < 0) continue;
    final x = pixel % width, y = pixel ~/ width;
    final col = frame % columns, row = frame ~/ columns;
    final dx = col * pw + x - col * cw + padding;
    final dy = row * ph + y - row * ch + padding;
    final source = pixel * 4, target = (dy * packedWidth + dx) * 4;
    final coverage = mask[source] / 255;
    for (var channel = 0; channel < 4; channel++) {
      rgba[target + channel] = (color[source + channel] * coverage).round();
    }
  }
  return PetAtlasFrames(rgba: rgba, width: packedWidth, height: packedHeight,
    padding: padding, cellWidth: cw, cellHeight: ch, bounds: bounds,
    fitScale: .94 / fitExtent,
    baselines: List.generate(bounds.length,
      (i) => (ground[i] - (i ~/ columns) * ch + padding + 1) / ph));
}
