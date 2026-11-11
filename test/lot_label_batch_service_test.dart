import 'dart:convert';
import 'package:cemetery_app/services/lot_label_batch_service.dart';
import 'package:cemetery_app/utils/lot_label_batch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

http.Response jsonResponse(http.Request request, String body, int status) =>
    http.Response(
      body,
      status,
      request: request,
      headers: {'content-type': 'application/json'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final lots = List.generate(
    20,
    (index) => <String, dynamic>{
      'lot_id': index + 1,
      'block_number': '36',
      'lot_number': '${index + 1}',
      'lot_label': '36-${index + 1}',
    },
  );

  test(
    'duplicate override reaches updates and does not change the conflicting lot',
    () async {
      final updated = <int>[];
      final client = SupabaseClient(
        'https://example.test',
        'test-key',
        httpClient: MockClient((request) async {
          if (request.method == 'GET') {
            return jsonResponse(request, jsonEncode(lots), 200);
          }
          final id = int.parse(
            request.url.queryParameters['lot_id']!.substring(3),
          );
          updated.add(id);
          return jsonResponse(request, jsonEncode({'lot_id': id}), 200);
        }),
      );
      final plan = planLotLabels([lots.first], '2');
      final blocked = await LotLabelBatchService.save(
        plan,
        client: client,
        auditWriter: (_) async {},
      );
      expect(blocked.error, contains('already exists'));
      expect(updated, isEmpty);
      final allowed = await LotLabelBatchService.save(
        plan,
        client: client,
        allowDuplicateNumbers: true,
        auditWriter: (_) async {},
      );
      expect(allowed.error, isNull);
      expect(updated, [1]);
      await client.dispose();
    },
  );

  test(
    'block saves use bounded concurrency and a single audit callback',
    () async {
      var active = 0;
      var peak = 0;
      var auditCalls = 0;
      final written = <int>[];
      final progress = <int>[];
      final client = SupabaseClient(
        'https://example.test',
        'test-key',
        httpClient: MockClient((request) async {
          if (request.method == 'GET') {
            return jsonResponse(request, jsonEncode(lots), 200);
          }
          active++;
          if (active > peak) peak = active;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          final id = int.parse(
            request.url.queryParameters['lot_id']!.substring(3),
          );
          written.add(id);
          active--;
          expect(jsonDecode(request.body)['block_number'], '12');
          return jsonResponse(request, jsonEncode({'lot_id': id}), 200);
        }),
      );
      final result = await LotLabelBatchService.save(
        planLotBlocks(lots, '12'),
        client: client,
        auditWriter: (changes) async {
          auditCalls++;
          expect(changes.length, 20);
        },
        onProgress: (saved, total, phase) => progress.add(saved),
      );
      expect(result.error, isNull);
      expect(peak, 8);
      expect(written.toSet().length, 20);
      expect(auditCalls, 1);
      expect(result.savedIds, List.generate(20, (i) => '${i + 1}'));
      expect(progress, containsAllInOrder([0, 8, 16, 20]));
      expect(result.error, isNull);
      await client.dispose();
    },
  );

  test(
    'failure accounts for successes in current group and stops later groups',
    () async {
      final attempted = <int>[];
      final client = SupabaseClient(
        'https://example.test',
        'test-key',
        httpClient: MockClient((request) async {
          if (request.method == 'GET') {
            return jsonResponse(request, jsonEncode(lots), 200);
          }
          final id = int.parse(
            request.url.queryParameters['lot_id']!.substring(3),
          );
          attempted.add(id);
          if (id == 3) {
            return jsonResponse(
              request,
              jsonEncode({'message': 'denied', 'code': '42501'}),
              403,
            );
          }
          return jsonResponse(request, jsonEncode({'lot_id': id}), 200);
        }),
      );
      final result = await LotLabelBatchService.save(
        planLotBlocks(lots, '12'),
        client: client,
        auditWriter: (changes) async {
          expect(changes.length, 7);
        },
      );
      expect(attempted, hasLength(8));
      expect(result.savedIds, ['1', '2', '4', '5', '6', '7', '8']);
      expect(result.error, isNotNull);
      await client.dispose();
    },
  );

  test(
    'stop preserves completed group and does not schedule more writes',
    () async {
      var stop = false;
      var writes = 0;
      final client = SupabaseClient(
        'https://example.test',
        'test-key',
        httpClient: MockClient((request) async {
          if (request.method == 'GET') {
            return jsonResponse(request, jsonEncode(lots), 200);
          }
          writes++;
          return jsonResponse(
            request,
            jsonEncode({
              'lot_id': int.parse(
                request.url.queryParameters['lot_id']!.substring(3),
              ),
            }),
            200,
          );
        }),
      );
      final result = await LotLabelBatchService.save(
        planLotBlocks(lots, '12'),
        client: client,
        shouldStop: () => stop,
        onProgress: (saved, total, phase) {
          if (saved >= 8) stop = true;
        },
        auditWriter: (_) async {},
      );
      expect(writes, 8);
      expect(result.savedIds.length, 8);
      expect(result.error, contains('Stopped'));
      await client.dispose();
    },
  );

  test('row failure leaves an ordered unsaved suffix', () async {
    final attempts = <int>[];
    final client = SupabaseClient(
      'https://example.test',
      'test-key',
      httpClient: MockClient((request) async {
        if (request.method == 'GET') {
          return jsonResponse(request, jsonEncode(lots), 200);
        }
        final id = int.parse(
          request.url.queryParameters['lot_id']!.substring(3),
        );
        attempts.add(id);
        if (id == 2) {
          return jsonResponse(
            request,
            jsonEncode({'message': 'denied', 'code': '42501'}),
            403,
          );
        }
        return jsonResponse(request, jsonEncode({'lot_id': id}), 200);
      }),
    );
    final result = await LotLabelBatchService.save(
      planLotLabels(lots, '101'),
      client: client,
      auditWriter: (_) async {},
    );
    expect(attempts, [1, 2]);
    expect(result.savedIds, ['1']);
    await client.dispose();
  });

  test('timeout returns an unconfirmed result instead of hanging', () async {
    final client = SupabaseClient(
      'https://example.test',
      'test-key',
      httpClient: MockClient((request) async {
        if (request.method == 'GET') {
          return jsonResponse(request, jsonEncode(lots), 200);
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return jsonResponse(request, jsonEncode({'lot_id': 1}), 200);
      }),
    );
    final result = await LotLabelBatchService.save(
      planLotBlocks([lots.first], '12'),
      client: client,
      requestTimeout: const Duration(milliseconds: 10),
      auditWriter: (_) async {},
    );
    expect(result.savedIds, isEmpty);
    expect(result.error, contains('may still finish'));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await client.dispose();
  });
}
