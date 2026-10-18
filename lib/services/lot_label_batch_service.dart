import 'dart:async';
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/lot_label_batch.dart';
import 'audit_service.dart';
import 'supabase_pagination_service.dart';

class LotLabelBatchResult {
  const LotLabelBatchResult(this.savedIds, this.error);
  final List<String> savedIds;
  final String? error;
}

class LotLabelBatchService {
  static Future<LotLabelBatchResult> save(
    List<LotLabelChange> changes, {
    SupabaseClient? client,
    bool allowDuplicateNumbers = false,
    void Function(int saved, int total, String phase)? onProgress,
    bool Function()? shouldStop,
    Future<void> Function(List<LotLabelChange>)? auditWriter,
    Duration requestTimeout = const Duration(seconds: 30),
  }) async {
    final db = client ?? Supabase.instance.client;
    final saved = <LotLabelChange>[];
    String? error;
    try {
      onProgress?.call(0, changes.length, 'Checking lot numbers');
      final current = await SupabasePaginationService.selectAll(
        supabase: db,
        table: 'cemetery_lot',
        columns: 'lot_id, block_number, lot_number, lot_label',
        orderColumn: 'lot_id',
      ).timeout(requestTimeout);
      validateLotLabelBatch(
        changes,
        current,
        allowDuplicateNumbers: allowDuplicateNumbers,
      );
      // Block moves are independent; row numbering preserves its unsaved suffix.
      final concurrency = changes.every((change) => change.targetBlock != null)
          ? 8
          : 1;
      for (var offset = 0; offset < changes.length; offset += concurrency) {
        if (shouldStop?.call() ?? false) {
          error =
              'Stopped. Confirmed changes are kept; the remaining lots are still selected.';
          break;
        }
        final group = changes.sublist(
          offset,
          min(offset + concurrency, changes.length),
        );
        final outcomes = await Future.wait(
          group.map((change) async {
            try {
              var query = db
                  .from('cemetery_lot')
                  .update(change.updates)
                  .eq('lot_id', change.id);
              for (final field in ['block_number', 'lot_number', 'lot_label']) {
                final old = change.before[field];
                query = old == null
                    ? query.isFilter(field, null)
                    : query.eq(field, old);
              }
              final row = await query
                  .select('lot_id')
                  .maybeSingle()
                  .timeout(requestTimeout);
              return row == null
                  ? 'A lot changed or could not be updated. Review the remaining selection.'
                  : null;
            } on PostgrestException catch (failure) {
              return failure.code == '23505'
                  ? 'The database enforces unique lot numbers. The app override cannot bypass that database constraint.'
                  : 'A save could not be confirmed. Refresh the map before retrying the remaining lots.';
            } on TimeoutException {
              return 'A request timed out and may still finish. Refresh the map before retrying the remaining lots.';
            } catch (_) {
              return 'A save could not be confirmed. Refresh the map before retrying the remaining lots.';
            }
          }),
        );
        for (var index = 0; index < group.length; index++) {
          if (outcomes[index] == null) {
            saved.add(group[index]);
          } else {
            error ??= outcomes[index];
          }
        }
        onProgress?.call(saved.length, changes.length, 'Saving lots');
        if (error != null) break;
      }
    } on FormatException catch (failure) {
      error = failure.message;
    } catch (_) {
      error = 'Unable to finish checking the lots. Please try again.';
    }
    if (saved.isNotEmpty) {
      onProgress?.call(saved.length, changes.length, 'Recording changes');
      try {
        if (auditWriter != null) {
          await auditWriter(saved);
        } else {
          await AuditService.logMany(
            saved
                .map(
                  (change) => <String, dynamic>{
                    'action': 'UPDATE',
                    'entity_type': 'cemetery_lot',
                    'entity_id': change.id.toString(),
                    'details':
                        'Batch labeling: block ${change.before['block_number']} -> ${change.block}; lot ${change.before['lot_number']} -> ${change.number}; duplicate override: $allowDuplicateNumbers',
                  },
                )
                .toList(),
          );
        }
      } catch (_) {
        error ??= 'Lot changes were saved, but audit recording did not finish.';
      }
    }
    return LotLabelBatchResult(
      saved.map((change) => change.id.toString()).toList(),
      error,
    );
  }
}
