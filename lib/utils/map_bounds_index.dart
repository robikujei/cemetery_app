import 'package:flutter_map/flutter_map.dart';

/// A local geographic grid for cemetery overlays. Results retain source order
/// so overlapping shapes keep the same paint and hit-test order.
class MapBoundsIndex<T> {
  MapBoundsIndex(List<T> items, LatLngBounds Function(T) boundsOf) {
    for (final item in items) {
      final bounds = boundsOf(item);
      final index = _entries.length;
      _entries.add((item, bounds));
      final cells = _cellsFor(bounds);
      if (cells.count > 256) {
        _overflow.add(index);
        continue;
      }
      for (var x = cells.west; x <= cells.east; x++) {
        for (var y = cells.south; y <= cells.north; y++) {
          (_buckets[(x, y)] ??= []).add(index);
        }
      }
    }
  }

  // About 28 metres at the cemetery; independent of camera zoom.
  static const _cellSize = 0.00025;
  final _entries = <(T, LatLngBounds)>[];
  final _buckets = <(int, int), List<int>>{};
  final _overflow = <int>[];

  List<T> query(LatLngBounds bounds) {
    final cells = _cellsFor(bounds);
    // A zoomed-out GPS view must not enumerate millions of empty grid cells.
    if (cells.count > 4096) {
      return [
        for (final entry in _entries)
          if (_intersects(entry.$2, bounds)) entry.$1,
      ];
    }
    final candidates = <int>{..._overflow};
    for (var x = cells.west; x <= cells.east; x++) {
      for (var y = cells.south; y <= cells.north; y++) {
        final bucket = _buckets[(x, y)];
        if (bucket != null) candidates.addAll(bucket);
      }
    }
    final ordered = candidates.toList()..sort();
    return [
      for (final index in ordered)
        if (_intersects(_entries[index].$2, bounds)) _entries[index].$1,
    ];
  }

  static bool _intersects(LatLngBounds a, LatLngBounds b) =>
      a.south <= b.north &&
      a.north >= b.south &&
      a.west <= b.east &&
      a.east >= b.west;

  static _GridCells _cellsFor(LatLngBounds bounds) => _GridCells(
    (bounds.west / _cellSize).floor(),
    (bounds.east / _cellSize).floor(),
    (bounds.south / _cellSize).floor(),
    (bounds.north / _cellSize).floor(),
  );
}

class _GridCells {
  const _GridCells(this.west, this.east, this.south, this.north);
  final int west, east, south, north;
  int get count => (east - west + 1) * (north - south + 1);
}

LatLngBounds paddedMapBounds(LatLngBounds bounds, double factor) {
  final lat = (bounds.north - bounds.south) * factor;
  final lng = (bounds.east - bounds.west) * factor;
  return LatLngBounds.unsafe(
    north: (bounds.north + lat).clamp(-90, 90),
    south: (bounds.south - lat).clamp(-90, 90),
    east: (bounds.east + lng).clamp(-180, 180),
    west: (bounds.west - lng).clamp(-180, 180),
  );
}
