import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/lot_pricing.dart';

/// Reads the editable database catalogue, while retaining the built-in values
/// for installations where the catalogue migration has not been applied yet.
class LotPriceCatalogService {
  const LotPriceCatalogService._();

  static Future<List<LotPrice>> load() async {
    try {
      final rows = await Supabase.instance.client
          .from('lot_price_catalog')
          .select('lot_type, at_need_price, pre_need_price')
          .order('lot_type');
      final catalog = rows
          .map(
            (row) => LotPrice(
              type: row['lot_type'].toString(),
              atNeed: _number(row['at_need_price']),
              preNeed: _number(row['pre_need_price']),
            ),
          )
          .toList();
      return catalog.isEmpty ? List.of(lotPriceCatalog) : catalog;
    } on PostgrestException catch (error) {
      // Keep the existing lot editor usable until the accompanying SQL has
      // been run on older Supabase projects.
      if (error.code == '42P01' || error.code == 'PGRST205') {
        return List.of(lotPriceCatalog);
      }
      rethrow;
    }
  }

  static Future<void> save(LotPrice price) async {
    await Supabase.instance.client.from('lot_price_catalog').upsert({
      'lot_type': price.type,
      'at_need_price': price.atNeed,
      'pre_need_price': price.preNeed,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'lot_type');

    // Re-run the database trigger for every existing lot of this type, so the
    // configured amount is reflected immediately without changing its term.
    await Supabase.instance.client
        .from('cemetery_lot')
        .update({'price': 0})
        .ilike('lot_class_type', price.type);
  }

  static double _number(dynamic value) => (value as num?)?.toDouble() ?? 0;
}
