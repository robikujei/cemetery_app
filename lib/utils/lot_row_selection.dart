import 'dart:math' as math;
import 'dart:ui';

class RowSelectionLot {
  const RowSelectionLot({
    required this.id,
    required this.block,
    required this.center,
    this.outline = const [],
  });
  final String id;
  final String block;
  final Offset center;
  final List<Offset> outline;
}

/// Nearest aligned neighbor in a screen direction. Selected neighbors are
/// intentionally not excluded: the caller must not jump over them.
String? nextLotInDirection(
  List<RowSelectionLot> lots,
  String currentId,
  Offset direction,
) {
  final current = lots.where((lot) => lot.id == currentId).firstOrNull;
  if (current == null ||
      current.block.trim().isEmpty ||
      direction.distance == 0) {
    return null;
  }
  final axis = direction / direction.distance;
  final normal = Offset(-axis.dy, axis.dx);
  double dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;
  final neighbors = lots
      .where(
        (lot) =>
            lot.id != currentId && lot.block.trim() == current.block.trim(),
      )
      .toList();
  if (neighbors.isEmpty) return null;
  final distances = neighbors
      .map((lot) => (lot.center - current.center).distance)
      .where((distance) => distance > 0)
      .toList();
  if (distances.isEmpty) return null;
  var maximumStep = distances.reduce(math.min) * 1.8;
  if (current.outline.length >= 3) {
    final projections = current.outline
        .map((point) => dot(point - current.center, axis))
        .toList();
    maximumStep = math.max(
      maximumStep,
      (projections.reduce(math.max) - projections.reduce(math.min)) * 2,
    );
  }
  String? next;
  var best = double.infinity;
  for (final lot in neighbors) {
    final delta = lot.center - current.center;
    final forward = dot(delta, axis);
    final sideways = dot(delta, normal).abs();
    if (forward <= 0 ||
        sideways > forward * 0.6 ||
        delta.distance > maximumStep) {
      continue;
    }
    final score = forward + sideways * 2;
    if (score < best) {
      best = score;
      next = lot.id;
    }
  }
  return next;
}

/// Select centers along the straight row between the endpoints, ordered from
/// start to end. Width comes from endpoint polygons rather than screen pixels,
/// so zoom and map rotation do not change the selection.
List<String> selectLotRow(
  List<RowSelectionLot> lots,
  String startId,
  String endId,
) {
  final byId = {for (final lot in lots) lot.id: lot};
  final start = byId[startId];
  final end = byId[endId];
  if (start == null || end == null) {
    throw const FormatException('Select two existing lots.');
  }
  if (start.block.trim().isEmpty || start.block.trim() != end.block.trim()) {
    throw const FormatException(
      'The start and end lots must be in the same block.',
    );
  }
  if (startId == endId) return [startId];
  final delta = end.center - start.center;
  final length = delta.distance;
  if (length < 0.000001) {
    throw const FormatException(
      'These lots overlap. Use Adjust lots to select them individually.',
    );
  }
  final direction = delta / length;
  final normal = Offset(-direction.dy, direction.dx);
  double dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

  double halfWidth(RowSelectionLot lot) {
    if (lot.outline.length < 3) return 0;
    final distances = lot.outline
        .map((point) => dot(point - lot.center, normal))
        .toList();
    return (distances.reduce(math.max) - distances.reduce(math.min)) / 2;
  }

  final widths = [
    halfWidth(start),
    halfWidth(end),
  ].where((width) => width > 0).toList();
  // Without polygons, keep the corridor narrower than neighboring lot spacing.
  final neighbors = byId.values
      .where(
        (lot) => lot.block.trim() == start.block.trim() && lot.id != startId,
      )
      .map((lot) => (lot.center - start.center).distance)
      .where((distance) => distance > 0)
      .toList();
  final tolerance = widths.isNotEmpty
      ? widths.reduce(math.min) * 0.65
      : neighbors.reduce(math.min) * 0.3;
  final selected = byId.values.where((lot) {
    if (lot.block.trim() != start.block.trim()) return false;
    if (lot.id == startId || lot.id == endId) return true;
    final relative = lot.center - start.center;
    final along = dot(relative, direction);
    return along >= 0 &&
        along <= length &&
        dot(relative, normal).abs() <= tolerance;
  }).toList();
  selected.sort(
    (a, b) => dot(
      a.center - start.center,
      direction,
    ).compareTo(dot(b.center - start.center, direction)),
  );
  // Explicit endpoints remain first and last even if other centers coincide.
  return [
    startId,
    ...selected
        .where((lot) => lot.id != startId && lot.id != endId)
        .map((lot) => lot.id),
    endId,
  ];
}
