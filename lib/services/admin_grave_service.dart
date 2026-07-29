import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/lot_pricing.dart';

class AdminGraveService {
  const AdminGraveService._();

  static const statuses = ['Available', 'Reserved', 'Occupied'];
  static final lotTypes = lotPriceCatalog.map((price) => price.type).toList();

  static Future<Map<String, List<Map<String, dynamic>>>> loadGravesByLotIds(
    Iterable<dynamic> lotIds,
  ) async {
    final normalizedIds = lotIds
        .where((id) => id != null)
        .map((id) => int.tryParse(id.toString()))
        .whereType<int>()
        .toSet()
        .toList();

    if (normalizedIds.isEmpty) return {};

    try {
      final rows = await Supabase.instance.client
          .from('graves')
          .select('''
            grave_id,
            lot_id,
            grave_label,
            status,
            burial_id,
            notes,
            burial:burial_id (
              burial_id,
              name_of_deceased,
              birth_date,
              death_date,
              burial_date,
              interment_date,
              interment_time,
              religion,
              burial_category
            )
          ''')
          .inFilter('lot_id', normalizedIds)
          .order('grave_label');

      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final row in rows as List) {
        final grave = Map<String, dynamic>.from(row);
        final lotId = grave['lot_id']?.toString();
        if (lotId == null) continue;
        grouped.putIfAbsent(lotId, () => []).add(grave);
      }
      return grouped;
    } catch (_) {
      return {};
    }
  }

  static Future<Map<String, dynamic>> addGrave({
    required int lotId,
    required String graveLabel,
    required String status,
    int? burialId,
    String? notes,
  }) async {
    final inserted = await Supabase.instance.client
        .from('graves')
        .insert({
          'lot_id': lotId,
          'grave_label': graveLabel,
          'status': status,
          'burial_id': burialId,
          'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
        })
        .select('grave_id, lot_id, grave_label, status, burial_id, notes')
        .single();

    if (burialId != null) {
      await _linkBurialToLot(burialId: burialId, lotId: lotId);
    }
    await _refreshLotStatus(lotId);

    return Map<String, dynamic>.from(inserted);
  }

  static Future<Map<String, dynamic>> createBurialAndGrave({
    required int lotId,
    required String graveLabel,
    required String deceasedName,
    required String deathDate,
    String? birthDate,
    String? intermentDate,
    String? intermentTime,
    String? religion,
    String? lotType,
    String? notes,
  }) async {
    final supabase = Supabase.instance.client;
    final burial = await supabase
        .from('burial_record')
        .insert({
          'lot_id': lotId,
          'name_of_deceased': deceasedName.trim(),
          'birth_date': _blankToNull(birthDate),
          'death_date': deathDate.trim(),
          'burial_date': _blankToNull(intermentDate),
          'interment_date': _blankToNull(intermentDate),
          'interment_time': _blankToNull(intermentTime),
          'religion': _blankToNull(religion),
          'burial_category': _blankToNull(lotType),
          'lot_location_no': graveLabel.trim(),
        })
        .select('burial_id')
        .single();

    final burialId = int.parse(burial['burial_id'].toString());
    return addGrave(
      lotId: lotId,
      graveLabel: graveLabel,
      status: 'Occupied',
      burialId: burialId,
      notes: notes,
    );
  }

  static Future<void> linkExistingBurialToGrave({
    required int lotId,
    required int graveId,
    required int burialId,
  }) async {
    await Supabase.instance.client
        .from('graves')
        .update({'burial_id': burialId, 'status': 'Occupied'})
        .eq('grave_id', graveId);
    await _linkBurialToLot(burialId: burialId, lotId: lotId);
    await _refreshLotStatus(lotId);
  }

  static String nextGraveLabel(List<Map<String, dynamic>> graves) {
    final numbers = graves
        .map((grave) => grave['grave_label']?.toString() ?? '')
        .map((label) => RegExp(r'\d+').firstMatch(label)?.group(0))
        .whereType<String>()
        .map(int.tryParse)
        .whereType<int>()
        .toList();

    final next = numbers.isEmpty
        ? graves.length + 1
        : numbers.reduce((a, b) => a > b ? a : b) + 1;
    return 'Grave $next';
  }

  static Future<void> _linkBurialToLot({
    required int burialId,
    required int lotId,
  }) async {
    await Supabase.instance.client
        .from('burial_record')
        .update({'lot_id': lotId})
        .eq('burial_id', burialId);
  }

  static Future<void> _refreshLotStatus(int lotId) async {
    final supabase = Supabase.instance.client;
    final occupiedGraves = await supabase
        .from('graves')
        .select('grave_id')
        .eq('lot_id', lotId)
        .eq('status', 'Occupied')
        .limit(1);
    if ((occupiedGraves as List).isNotEmpty) {
      await supabase
          .from('cemetery_lot')
          .update({'status': 'Occupied'})
          .eq('lot_id', lotId);
      return;
    }

    final ownerships = await supabase
        .from('lot_ownership')
        .select('ownership_id')
        .eq('lot_id', lotId)
        .limit(1);
    await supabase
        .from('cemetery_lot')
        .update({
          'status': (ownerships as List).isEmpty ? 'Available' : 'Reserved',
        })
        .eq('lot_id', lotId);
  }

  static String? _blankToNull(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
