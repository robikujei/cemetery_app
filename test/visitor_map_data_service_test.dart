import 'dart:async';
import 'dart:convert';

import 'package:cemetery_app/services/visitor_map_data_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseClient client;
  VisitorMapDataService service(
    Future<http.Response> Function(http.Request) handler, {
    int pageSize = 500,
  }) {
    client = SupabaseClient(
      'https://example.supabase.co',
      'test-key',
      httpClient: MockClient((request) async {
        final response = await handler(request);
        return http.Response(
          response.body,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
    );
    return VisitorMapDataService(
      client,
      pageSize: pageSize,
      requestTimeout: const Duration(milliseconds: 100),
    );
  }

  tearDown(() => client.dispose());

  test('base map completes without requesting lots or graves', () async {
    final tables = <String>[];
    final loader = service((request) async {
      final table = request.url.pathSegments.last;
      tables.add(table);
      return http.Response(
        jsonEncode(
          table == 'cemetery_map_features'
              ? [
                  {'feature_id': 1, 'is_visible': true, 'sort_order': 2},
                  {'feature_id': 2, 'is_visible': false, 'sort_order': 0},
                  {'feature_id': 3, 'is_visible': true, 'sort_order': 1},
                ]
              : [],
        ),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final base = await loader.loadBase();
    expect(
      tables,
      unorderedEquals([
        'cemetery_map',
        'cemetery_map_features',
        'path_nodes',
        'path_edges',
      ]),
    );
    expect(base.features.map((f) => f['feature_id']), [3, 1]);
  });

  test('lots arrive progressively without the 1000 row limit', () async {
    final offsets = <int>[];
    final loader = service((request) async {
      final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
      offsets.add(offset);
      final count = offset < 1000 ? 500 : 17;
      return http.Response(
        jsonEncode(
          List.generate(
            count,
            (i) => {'marker_id': offset + i, 'lot_id': offset + i},
          ),
        ),
        200,
      );
    });
    final pages = await loader.markerPages(isCurrent: () => true).toList();
    expect(pages.map((p) => p.length), [500, 500, 17]);
    expect(offsets, [0, 500, 1000]);
  });

  test('graves paginate and group without a lot ID URL filter', () async {
    final loader = service((request) async {
      expect(request.url.queryParameters.containsKey('lot_id'), isFalse);
      final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
      return http.Response(
        jsonEncode(
          offset == 0
              ? [
                  {'grave_id': 1, 'lot_id': 9},
                  {'grave_id': 2, 'lot_id': 9},
                ]
              : [
                  {'grave_id': 3, 'lot_id': 10},
                ],
        ),
        200,
      );
    }, pageSize: 2);
    final graves = await loader.loadGraves(isCurrent: () => true);
    expect(graves['9']!.length, 2);
    expect(graves['10']!.single['grave_id'], 3);
  });

  test('a stalled request times out instead of loading forever', () async {
    final loader = service((_) => Completer<http.Response>().future);
    await expectLater(
      loader.markerPages(isCurrent: () => true).toList(),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('leaving the map prevents subsequent page requests', () async {
    var current = true;
    var requests = 0;
    final loader = service((_) async {
      requests++;
      return http.Response('[{"marker_id":1}]', 200);
    }, pageSize: 1);
    await for (final _ in loader.markerPages(isCurrent: () => current)) {
      current = false;
    }
    expect(requests, 1);
  });
}
