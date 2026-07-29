import 'package:supabase_flutter/supabase_flutter.dart';

class SupabasePaginationService {
  static const int _pageSize = 1000;

  static Future<List<Map<String, dynamic>>> selectAll({
    required SupabaseClient supabase,
    required String table,
    required String columns,
    required String orderColumn,
  }) async {
    final allRows = <Map<String, dynamic>>[];

    for (var from = 0; ; from += _pageSize) {
      final rows = await supabase
          .from(table)
          .select(columns)
          .order(orderColumn)
          .range(from, from + _pageSize - 1);
      final page = List<Map<String, dynamic>>.from(rows);
      allRows.addAll(page);
      if (page.length < _pageSize) break;
    }

    return allRows;
  }
}
