import 'package:supabase_flutter/supabase_flutter.dart';

class MapFeatureService {
  static Future<List<Map<String, dynamic>>> loadVisible(
    SupabaseClient supabase,
  ) async {
    try {
      final rows = await supabase
          .from('cemetery_map_features')
          .select(
            'feature_id, feature_type, feature_name, geometry_wkt, stroke_color, fill_color, stroke_width, sort_order, is_visible, source_feature_id',
          )
          .eq('is_visible', true)
          .order('sort_order')
          .order('feature_id');

      return List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      return [];
    }
  }
}
