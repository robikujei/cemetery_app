import 'package:supabase_flutter/supabase_flutter.dart';

class AdminDeleteService {
  const AdminDeleteService._();

  static Future<void> deleteBurialRecord(int burialId) async {
    final supabase = Supabase.instance.client;
    final record = await supabase
        .from('burial_record')
        .select('burial_id, lot_id')
        .eq('burial_id', burialId)
        .maybeSingle();

    if (record == null) {
      throw Exception('Burial record was not found.');
    }

    await _detachVisitorLogsFromBurials([burialId]);
    await _detachGravesFromBurials([burialId]);

    final deleted = await supabase
        .from('burial_record')
        .delete()
        .eq('burial_id', burialId)
        .select('burial_id');

    if ((deleted as List).isEmpty) {
      throw Exception(
        'Burial record was not deleted. Check delete permissions in Supabase.',
      );
    }

    final lotId = record['lot_id'];
    if (lotId != null) {
      await refreshLotStatus(lotId);
    }
  }

  static Future<void> deleteLot(int lotId) async {
    final supabase = Supabase.instance.client;

    final burials = await supabase
        .from('burial_record')
        .select('burial_id')
        .eq('lot_id', lotId);
    final burialIds = (burials as List)
        .map((burial) => burial['burial_id'])
        .where((id) => id != null)
        .toList();

    await _detachVisitorLogsFromBurials(burialIds);
    await _detachGravesFromBurials(burialIds);
    await supabase.from('burial_record').delete().eq('lot_id', lotId);

    final ownerships = await supabase
        .from('lot_ownership')
        .select('ownership_id')
        .eq('lot_id', lotId);
    final ownershipIds = (ownerships as List)
        .map((ownership) => ownership['ownership_id'])
        .where((id) => id != null)
        .toList();

    await _deleteOwnershipDependents(ownershipIds);
    await supabase.from('lot_ownership').delete().eq('lot_id', lotId);
    await supabase.from('lot_markers').delete().eq('lot_id', lotId);
    await _deleteGravesForLot(lotId);

    final deleted = await supabase
        .from('cemetery_lot')
        .delete()
        .eq('lot_id', lotId)
        .select('lot_id');

    if ((deleted as List).isEmpty) {
      throw Exception(
        'Lot was not deleted. Check delete permissions in Supabase.',
      );
    }
  }

  static Future<void> refreshLotStatus(dynamic lotId) async {
    final supabase = Supabase.instance.client;
    final remainingBurials = await supabase
        .from('burial_record')
        .select('burial_id')
        .eq('lot_id', lotId)
        .limit(1);

    if ((remainingBurials as List).isNotEmpty) {
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

  static Future<void> _detachVisitorLogsFromBurials(
    List<dynamic> burialIds,
  ) async {
    if (burialIds.isEmpty) return;

    try {
      await Supabase.instance.client
          .from('visitor_log')
          .update({'burial_id': null})
          .inFilter('burial_id', burialIds);
    } catch (_) {
      await Supabase.instance.client
          .from('visitor_log')
          .delete()
          .inFilter('burial_id', burialIds);
    }
  }

  static Future<void> _detachGravesFromBurials(List<dynamic> burialIds) async {
    if (burialIds.isEmpty) return;

    try {
      await Supabase.instance.client
          .from('graves')
          .update({'burial_id': null})
          .inFilter('burial_id', burialIds);
    } catch (_) {
      return;
    }
  }

  static Future<void> _deleteGravesForLot(int lotId) async {
    try {
      await Supabase.instance.client
          .from('graves')
          .delete()
          .eq('lot_id', lotId);
    } catch (_) {
      return;
    }
  }

  static Future<void> _deleteOwnershipDependents(
    List<dynamic> ownershipIds,
  ) async {
    if (ownershipIds.isEmpty) return;

    final supabase = Supabase.instance.client;
    await supabase
        .from('payment_requests')
        .delete()
        .inFilter('ownership_id', ownershipIds);
    await supabase
        .from('transaction_history')
        .delete()
        .inFilter('ownership_id', ownershipIds);
  }
}
