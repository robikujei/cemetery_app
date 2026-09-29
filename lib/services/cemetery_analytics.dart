import 'dart:collection';
import 'dart:math' as math;

/// Calendar dates and timestamps are grouped in the cemetery's timezone (UTC+8).
DateTime? cemeteryDate(Object? value) {
  if (value == null) return null;
  final parsed = DateTime.tryParse(value.toString());
  if (parsed == null) return null;
  final local = parsed.isUtc ? parsed.add(const Duration(hours: 8)) : parsed;
  return DateTime(local.year, local.month, local.day);
}

bool inPeriod(Object? value, DateTime? start, DateTime? end) {
  final date = cemeteryDate(value);
  if (date == null) return start == null && end == null;
  return (start == null || !date.isBefore(start)) &&
      (end == null || !date.isAfter(end));
}

String blockOf(Map<String, dynamic> lot) {
  final block = lot['block_number']?.toString().trim() ?? '';
  return block.isEmpty ? 'Unassigned' : block;
}

double number(Object? value) => double.tryParse(value?.toString() ?? '') ?? 0;

class BurialPoint {
  const BurialPoint(this.id, this.lotId, this.block, this.lat, this.lng);
  final String id, lotId, block;
  final double lat, lng;
}

class SpatialResult {
  const SpatialResult(
    this.points,
    this.labels,
    this.clusterCount,
    this.excluded,
  );
  final List<BurialPoint> points;

  /// -1 denotes noise; cluster IDs start at 0.
  final List<int> labels;
  final int clusterCount, excluded;
  int get noiseCount => labels.where((label) => label == -1).length;
}

/// DBSCAN with a local metre projection and spatial buckets. MinPts includes self.
/// Suitable for a cemetery-sized extent; never interprets percentage coordinates
/// as geographic positions. Input order determines ambiguous border assignment.
SpatialResult dbscan(
  List<BurialPoint> points, {
  double epsilon = 15,
  int minPoints = 5,
  int excluded = 0,
}) {
  if (!epsilon.isFinite || epsilon <= 0 || minPoints < 2) {
    throw ArgumentError('Radius must be positive and MinPts at least 2.');
  }
  if (points.any(
    (p) =>
        !p.lat.isFinite ||
        !p.lng.isFinite ||
        p.lat.abs() > 90 ||
        p.lng.abs() > 180,
  )) {
    throw ArgumentError('Invalid geographic coordinates.');
  }
  if (points.isEmpty) return SpatialResult(points, [], 0, excluded);
  const metresPerDegree = 111195.0802335329;
  final origin = points.first;
  final scaleX = metresPerDegree * math.cos(origin.lat * math.pi / 180);
  final xy = points
      .map(
        (p) => (
          (p.lng - origin.lng) * scaleX,
          (p.lat - origin.lat) * metresPerDegree,
        ),
      )
      .toList();
  final buckets = <(int, int), List<int>>{};
  for (var i = 0; i < xy.length; i++) {
    final key = ((xy[i].$1 / epsilon).floor(), (xy[i].$2 / epsilon).floor());
    (buckets[key] ??= []).add(i);
  }
  List<int> neighbors(int index) {
    final point = xy[index];
    final bx = (point.$1 / epsilon).floor();
    final by = (point.$2 / epsilon).floor();
    final found = <int>[];
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        for (final j in buckets[(bx + dx, by + dy)] ?? <int>[]) {
          final x = point.$1 - xy[j].$1;
          final y = point.$2 - xy[j].$2;
          if (x * x + y * y <= epsilon * epsilon) found.add(j);
        }
      }
    }
    return found;
  }

  final labels = List<int>.filled(points.length, -2);
  var cluster = 0;
  for (var i = 0; i < points.length; i++) {
    if (labels[i] != -2) continue;
    final near = neighbors(i);
    if (near.length < minPoints) {
      labels[i] = -1;
      continue;
    }
    labels[i] = cluster;
    final queued = near.toSet();
    final queue = Queue<int>.from(near);
    while (queue.isNotEmpty) {
      final j = queue.removeFirst();
      if (labels[j] == -1) labels[j] = cluster;
      if (labels[j] != -2) continue;
      labels[j] = cluster;
      final more = neighbors(j);
      if (more.length >= minPoints) {
        for (final next in more) {
          if (queued.add(next)) queue.add(next);
        }
      }
    }
    cluster++;
  }
  return SpatialResult(points, labels, cluster, excluded);
}

class BlockDemand {
  BlockDemand(this.block);
  final String block;
  int lots = 0, occupied = 0, available = 0, sold = 0, usedOrSold = 0;
  double get score => lots == 0 ? 0 : 100 * usedOrSold / lots;
  String level({double medium = 30, double high = 70}) => score >= high
      ? 'High'
      : score >= medium
      ? 'Medium'
      : 'Low';
}

List<BlockDemand> classifyDemand(
  List<Map<String, dynamic>> lots,
  List<Map<String, dynamic>> ownerships,
) {
  final soldIds = ownerships
      .where(
        (o) => !{
          'cancelled',
          'canceled',
        }.contains(o['status']?.toString().toLowerCase()),
      )
      .map((o) => o['lot_id']?.toString())
      .whereType<String>()
      .toSet();
  final blocks = <String, BlockDemand>{};
  for (final lot in lots) {
    final block = blocks.putIfAbsent(
      blockOf(lot),
      () => BlockDemand(blockOf(lot)),
    );
    final status = lot['status']?.toString().toLowerCase();
    final sold = soldIds.contains(lot['lot_id'].toString());
    final occupied = status == 'occupied';
    block.lots++;
    if (occupied) block.occupied++;
    if (status == 'available') block.available++;
    if (sold) block.sold++;
    if (occupied || sold) block.usedOrSold++;
  }
  return blocks.values.toList()..sort((a, b) => a.block.compareTo(b.block));
}

enum TrendInterval { daily, weekly, monthly }

Map<DateTime, int> visitorTrend(
  List<Map<String, dynamic>> logs,
  TrendInterval interval, {
  DateTime? start,
  DateTime? end,
}) {
  DateTime bucket(DateTime day) => switch (interval) {
    TrendInterval.daily => day,
    TrendInterval.weekly => day.subtract(Duration(days: day.weekday - 1)),
    TrendInterval.monthly => DateTime(day.year, day.month),
  };
  final counts = SplayTreeMap<DateTime, int>();
  for (final log in logs) {
    final date = cemeteryDate(log['time_in']);
    if (date == null || !inPeriod(log['time_in'], start, end)) continue;
    final key = bucket(date);
    counts[key] = (counts[key] ?? 0) + 1;
  }
  if (counts.isEmpty && (start == null || end == null)) return counts;
  var cursor = bucket(start ?? counts.firstKey()!);
  final last = bucket(end ?? counts.lastKey()!);
  while (!cursor.isAfter(last)) {
    counts.putIfAbsent(cursor, () => 0);
    cursor = switch (interval) {
      TrendInterval.daily => DateTime(
        cursor.year,
        cursor.month,
        cursor.day + 1,
      ),
      TrendInterval.weekly => DateTime(
        cursor.year,
        cursor.month,
        cursor.day + 7,
      ),
      TrendInterval.monthly => DateTime(cursor.year, cursor.month + 1),
    };
  }
  return counts;
}

/// Quote CSV cells and neutralize spreadsheet formulas in text fields.
String encodeCsv(List<List<Object?>> rows) => rows
    .map(
      (row) => row
          .map((cell) {
            var value = cell?.toString() ?? '';
            if (cell is String && RegExp(r'^\s*[=+@\-\t\r]').hasMatch(value)) {
              value = "'$value";
            }
            return '"${value.replaceAll('"', '""')}"';
          })
          .join(','),
    )
    .join('\r\n');
