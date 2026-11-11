import 'dart:math' as math;
import 'package:cemetery_app/utils/lot_row_selection.dart';
import 'package:flutter_test/flutter_test.dart';

RowSelectionLot lot(String id, double x, double y, {String block = '12'}) =>
    RowSelectionLot(
      id: id,
      block: block,
      center: Offset(x, y),
      outline: [
        Offset(x - 4, y - 4),
        Offset(x + 4, y - 4),
        Offset(x + 4, y + 4),
        Offset(x - 4, y + 4),
      ],
    );

void main() {
  final grid = [
    for (var row = 0; row < 3; row++)
      for (var column = 0; column < 6; column++)
        lot('$row-$column', column * 10, row * 10),
  ];
  test(
    'arrow navigation finds the adjacent lot in all four screen directions',
    () {
      expect(nextLotInDirection(grid, '1-2', const Offset(1, 0)), '1-3');
      expect(nextLotInDirection(grid, '1-2', const Offset(-1, 0)), '1-1');
      expect(nextLotInDirection(grid, '1-2', const Offset(0, -1)), '0-2');
      expect(nextLotInDirection(grid, '1-2', const Offset(0, 1)), '2-2');
      expect(nextLotInDirection(grid, '1-5', const Offset(1, 0)), isNull);
    },
  );
  test(
    'arrows stay in the block, prefer aligned neighbors, and stop at large gaps',
    () {
      final lots = [
        lot('previous', -10, 0),
        lot('current', 0, 0),
        lot('nearby', 10, 1),
        lot('other-block', 5, 0, block: '36'),
        lot('far', 100, 0),
      ];
      expect(nextLotInDirection(lots, 'current', const Offset(1, 0)), 'nearby');
      expect(nextLotInDirection(lots, 'nearby', const Offset(1, 0)), isNull);
      expect(
        nextLotInDirection(lots, 'nearby', const Offset(-1, 0)),
        'current',
      );
    },
  );
  test('selects only the requested row between inclusive endpoints', () {
    expect(selectLotRow(grid, '1-1', '1-4'), ['1-1', '1-2', '1-3', '1-4']);
  });
  test('reverse direction reverses numbering order', () {
    expect(selectLotRow(grid, '1-4', '1-1'), ['1-4', '1-3', '1-2', '1-1']);
  });
  test('vertical rows and individual lots work', () {
    expect(selectLotRow(grid, '0-2', '2-2'), ['0-2', '1-2', '2-2']);
    expect(selectLotRow(grid, '1-2', '1-2'), ['1-2']);
  });
  test('selection is unchanged by zoom, translation and rotation', () {
    Offset transform(Offset point) => Offset(
      (point.dx * math.cos(0.7) - point.dy * math.sin(0.7)) * 5 + 300,
      (point.dx * math.sin(0.7) + point.dy * math.cos(0.7)) * 5 + 100,
    );
    final moved = grid
        .map(
          (item) => RowSelectionLot(
            id: item.id,
            block: item.block,
            center: transform(item.center),
            outline: item.outline.map(transform).toList(),
          ),
        )
        .toList();
    expect(selectLotRow(moved, '1-1', '1-4'), ['1-1', '1-2', '1-3', '1-4']);
  });
  test('excludes neighboring blocks and rejects cross-block endpoints', () {
    final lots = [
      lot('a', 0, 0),
      lot('b', 10, 0, block: '36'),
      lot('c', 20, 0),
    ];
    expect(selectLotRow(lots, 'a', 'c'), ['a', 'c']);
    expect(() => selectLotRow(lots, 'a', 'b'), throwsFormatException);
  });
  test('allows slight row misalignment without selecting the next row', () {
    final lots = [
      lot('a', 0, 0),
      lot('b', 10, 1),
      lot('c', 20, 0),
      lot('neighbor', 10, 10),
    ];
    expect(selectLotRow(lots, 'a', 'c'), ['a', 'b', 'c']);
  });
  test('point markers use spacing as a fallback', () {
    final points = grid
        .map(
          (item) => RowSelectionLot(
            id: item.id,
            block: item.block,
            center: item.center,
          ),
        )
        .toList();
    expect(selectLotRow(points, '1-1', '1-4'), ['1-1', '1-2', '1-3', '1-4']);
  });
  test('missing, unassigned and overlapping endpoints are rejected', () {
    expect(() => selectLotRow(grid, 'missing', '1-4'), throwsFormatException);
    expect(
      () => selectLotRow([lot('a', 0, 0, block: '')], 'a', 'a'),
      throwsFormatException,
    );
    expect(
      () => selectLotRow([lot('a', 0, 0), lot('b', 0, 0)], 'a', 'b'),
      throwsFormatException,
    );
  });
}
