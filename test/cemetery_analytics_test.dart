import 'package:flutter_test/flutter_test.dart';
import 'package:cemetery_app/services/cemetery_analytics.dart';
import 'package:cemetery_app/services/analytics_data.dart';

void main() {
  BurialPoint p(String id, double metres) =>
      BurialPoint(id, id, '1', 7, 125 + metres / 110366);
  test('DBSCAN separates clusters and isolated records', () {
    final result = dbscan(
      [
        p('1', 0),
        p('2', 1),
        p('3', 2),
        p('4', 50),
        p('5', 51),
        p('6', 52),
        p('7', 100),
      ],
      epsilon: 5,
      minPoints: 3,
    );
    expect(result.clusterCount, 2);
    expect(result.labels, [0, 0, 0, 1, 1, 1, -1]);
  });
  test('DBSCAN reassigns early noise as a border point, counts self', () {
    final result = dbscan(
      [p('1', 0), p('2', 4), p('3', 5), p('4', 6)],
      epsilon: 4.5,
      minPoints: 4,
    );
    expect(result.labels, [0, 0, 0, 0]);
    expect(dbscan([p('1', 0)], minPoints: 2).labels, [-1]);
  });
  test('Empty input and coincident burials are handled', () {
    expect(dbscan([]).clusterCount, 0);
    expect(dbscan([p('1', 0), p('2', 0)], minPoints: 2).labels, [0, 0]);
    expect(() => dbscan([], epsilon: 0), throwsArgumentError);
  });
  test(
    'Demand deduplicates sold and occupied lots and ignores canceled sales',
    () {
      final blocks = classifyDemand(
        [
          {'lot_id': 1, 'block_number': '1', 'status': 'Occupied'},
          {'lot_id': 2, 'block_number': '1', 'status': 'Available'},
          {'lot_id': 3, 'block_number': '1', 'status': 'Available'},
        ],
        [
          {'lot_id': 1},
          {'lot_id': 1},
          {'lot_id': 2},
          {'lot_id': 3, 'status': 'Cancelled'},
        ],
      );
      expect(blocks.single.usedOrSold, 2);
      expect(blocks.single.sold, 2);
      expect(blocks.single.level(), 'Medium');
    },
  );
  test(
    'Daily trends use Philippine time and include end day and zero days',
    () {
      final result = visitorTrend(
        [
          {'time_in': '2026-09-12T16:30:00Z'},
          {'time_in': '2026-09-15T15:59:59Z'},
          {'time_in': '2026-09-15T16:00:00Z'},
        ],
        TrendInterval.daily,
        start: DateTime(2026, 9, 13),
        end: DateTime(2026, 9, 15),
      );
      expect(result.values.toList(), [1, 0, 1]);
    },
  );
  test('Weeks start Monday and months cross year boundaries', () {
    final logs = [
      {'time_in': '2025-12-31'},
      {'time_in': '2026-01-04'},
      {'time_in': '2026-01-05'},
    ];
    expect(visitorTrend(logs, TrendInterval.weekly).values.toList(), [2, 1]);
    expect(visitorTrend(logs, TrendInterval.monthly).values.toList(), [1, 2]);
  });
  test('Missing dates are excluded only when date filtering', () {
    expect(inPeriod(null, null, null), isTrue);
    expect(inPeriod(null, DateTime(2026), null), isFalse);
  });
  test(
    'CSV escapes embedded quotes, line breaks, and spreadsheet formulas',
    () {
      expect(
        encodeCsv([
          ['A "name"', 'line\nbreak', '=SUM(A1)', -4],
        ]),
        '"A ""name""","line\nbreak","\'=SUM(A1)","-4"',
      );
    },
  );
  test('Spatial analysis excludes percentage markers and unlinked burials', () {
    final data = AnalyticsData();
    data.rows['cemetery_lot'] = [
      {'lot_id': 1, 'x_coord': 50, 'y_coord': 50},
      {'lot_id': 2, 'x_coord': 125, 'y_coord': 7, 'qgis_feature_id': '2'},
    ];
    data.rows['burial_record'] = [
      {'burial_id': 1, 'lot_id': 1},
      {'burial_id': 2, 'lot_id': 2},
      {'burial_id': 3},
    ];
    expect(data.spatial().excluded, 2);
    expect(data.spatial().points.single.id, '2');
  });
  test('Mock analytics data fills every report source and lot polygons', () {
    final data = AnalyticsData.mock();

    expect(data.errors, isEmpty);
    expect(data.lots, hasLength(48));
    expect(data.burials, isNotEmpty);
    expect(data.sales, isNotEmpty);
    expect(data.payments, isNotEmpty);
    expect(data.visitors, hasLength(120));
    expect(data.features, isEmpty);
    expect(data.mappedLotAreas(), hasLength(3));
    expect(data.spatial(minPoints: 2).points, isNotEmpty);
    expect(data.position(data.lots.first), isNotNull);
  });
}
