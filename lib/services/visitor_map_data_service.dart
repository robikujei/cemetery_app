import 'package:supabase_flutter/supabase_flutter.dart';

class VisitorMapBaseData {
  const VisitorMapBaseData(this.config, this.features, this.nodes, this.edges);
  final Map<String, dynamic>? config;
  final List<Map<String, dynamic>> features, nodes, edges;
}

/// Loads the lightweight map before downloading lot geometry. Every request has
/// a deadline, and page boundaries allow the screen to paint and report progress.
class VisitorMapDataService {
  VisitorMapDataService(
    this.client, {
    this.requestTimeout = const Duration(seconds: 20),
    this.pageSize = 500,
  });
  final SupabaseClient client;
  final Duration requestTimeout;
  final int pageSize;

  /// Public map overlay for today's active interments and their lot IDs.
  ///
  /// Interments can be scheduled directly in the planner or recorded through
  /// the Interment Application/Record form.  The latter creates a
  /// `burial_record`, not an `interment_schedule` row, so both sources must be
  /// included for the visitor map to remain in sync.
  Future<List<Map<String, dynamic>>> loadTodaySchedules() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    final dateText = '${start.year.toString().padLeft(4, '0')}-'
        '${start.month.toString().padLeft(2, '0')}-'
        '${start.day.toString().padLeft(2, '0')}';
    final scheduleResult = await client
        .from('interment_schedule')
        .select('schedule_id,lot_id,deceased_name,scheduled_at,notes')
        .eq('status', 'scheduled')
        .gte('scheduled_at', start.toUtc().toIso8601String())
        .lt('scheduled_at', end.toUtc().toIso8601String())
        .order('scheduled_at')
        .timeout(requestTimeout);
    final scheduled = List<Map<String, dynamic>>.from(scheduleResult);
    final scheduledKeys = scheduled
        .map(
          (item) => '${item['lot_id']}|${item['deceased_name']}|'
              '${item['scheduled_at'].toString().substring(0, 10)}',
        )
        .toSet();
    // Some older projects may grant visitor access only to the schedule table.
    // Preserve manual planner schedules if that supplemental query is denied.
    List<Map<String, dynamic>> burials;
    try {
      final result = await client
          .from('burial_record')
          .select(
            'burial_id,lot_id,name_of_deceased,interment_date,interment_time',
          )
          .eq('interment_date', dateText)
          .not('lot_id', 'is', null)
          .timeout(requestTimeout);
      burials = List<Map<String, dynamic>>.from(result);
    } catch (_) {
      return scheduled;
    }
    for (final burial in burials) {
      final date = burial['interment_date']?.toString();
      final name = burial['name_of_deceased']?.toString();
      final lotId = burial['lot_id'];
      if (date == null || name == null || lotId == null) continue;
      final time = burial['interment_time']?.toString().trim();
      final at = DateTime.tryParse(
        time == null || time.isEmpty ? '${date}T00:00:00' : '${date}T$time',
      );
      if (at == null) continue;
      final key = '$lotId|$name|${date.substring(0, 10)}';
      if (scheduledKeys.contains(key)) continue;
      scheduled.add({
        'schedule_id': 'burial-${burial['burial_id']}',
        'lot_id': lotId,
        'deceased_name': name,
        'scheduled_at': at.toUtc().toIso8601String(),
        'notes': null,
        'from_burial_record': true,
      });
    }
    scheduled.sort(
      (a, b) => a['scheduled_at'].toString().compareTo(
        b['scheduled_at'].toString(),
      ),
    );
    return scheduled;
  }

  Future<VisitorMapBaseData> loadBase() async {
    final results = await Future.wait<dynamic>([
      client
          .from('cemetery_map')
          .select(
            'entrance_x_percent,entrance_y_percent,center_lat,center_lng,lat_span,lng_span',
          )
          .order('uploaded_at', ascending: false)
          .limit(1)
          .maybeSingle()
          .timeout(requestTimeout),
      _all(
        'cemetery_map_features',
        'feature_id,feature_type,feature_name,geometry_wkt,stroke_color,fill_color,stroke_width,is_visible,sort_order',
        'feature_id',
      ),
      _all('path_nodes', '*', 'node_id'),
      _all('path_edges', '*', 'edge_id'),
    ], eagerError: true);
    final features =
        (results[1] as List<Map<String, dynamic>>)
            .where((f) => f['is_visible'] == true)
            .toList()
          ..sort(
            (a, b) => ((a['sort_order'] as num?) ?? 0).compareTo(
              (b['sort_order'] as num?) ?? 0,
            ),
          );
    return VisitorMapBaseData(
      results[0] as Map<String, dynamic>?,
      features,
      results[2] as List<Map<String, dynamic>>,
      results[3] as List<Map<String, dynamic>>,
    );
  }

  Stream<List<Map<String, dynamic>>> markerPages({
    required bool Function() isCurrent,
  }) => _pages(
    'lot_markers',
    '''
      marker_id,lot_id,x_percent,y_percent,
      cemetery_lot(lot_id,lot_number,lot_label,block_number,lot_class_type,
        polygon_geo,price,status,
        burial_record(burial_id,name_of_deceased,birth_date,death_date,burial_date,lot_location_no))
    ''',
    'marker_id',
    isCurrent: isCurrent,
  );

  Future<Map<String, List<Map<String, dynamic>>>> loadGraves({
    required bool Function() isCurrent,
  }) async {
    final grouped = <String, List<Map<String, dynamic>>>{};
    // Do not put thousands of lot IDs into a GET URL. The same visible grave
    // records can be paged by their primary key and grouped locally.
    await for (final page in _pages(
      'graves',
      '''
      grave_id,lot_id,grave_label,status,burial_id,notes,
      burial:burial_id(burial_id,name_of_deceased,birth_date,death_date,burial_date,
        interment_date,interment_time,religion,burial_category)
    ''',
      'grave_id',
      isCurrent: isCurrent,
    )) {
      for (final grave in page) {
        final id = grave['lot_id']?.toString();
        if (id != null) (grouped[id] ??= []).add(grave);
      }
    }
    return grouped;
  }

  Future<List<Map<String, dynamic>>> _all(
    String table,
    String columns,
    String order,
  ) async {
    final rows = <Map<String, dynamic>>[];
    await for (final page in _pages(
      table,
      columns,
      order,
      isCurrent: () => true,
    )) {
      rows.addAll(page);
    }
    return rows;
  }

  Stream<List<Map<String, dynamic>>> _pages(
    String table,
    String columns,
    String order, {
    required bool Function() isCurrent,
  }) async* {
    for (var from = 0; isCurrent(); from += pageSize) {
      final result = await client
          .from(table)
          .select(columns)
          .order(order)
          .range(from, from + pageSize - 1)
          .timeout(requestTimeout);
      if (!isCurrent()) return;
      final page = List<Map<String, dynamic>>.from(result);
      yield page;
      if (page.length < pageSize) return;
    }
  }
}
