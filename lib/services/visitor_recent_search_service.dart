import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VisitorRecentSearchService {
  const VisitorRecentSearchService._();

  static const _table = 'visitor_recent_searches';

  static Future<List<Map<String, dynamic>>> load() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return [];
    final local = await _loadLocal(userId);
    try {
      if (local.isNotEmpty) await _upsertMany(userId, local);
      final rows = await Supabase.instance.client
          .from(_table)
          .select()
          .eq('user_id', userId)
          .order('searched_at', ascending: false)
          .limit(10);
      final searches = (rows as List)
          .map((row) => _fromDatabase(Map<String, dynamic>.from(row as Map)))
          .toList();
      await _writeLocal(userId, searches);
      return searches;
    } catch (_) {
      return local;
    }
  }

  static Future<void> save(Map<String, dynamic> search) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final burialId = _asInt(search['burialId'] ?? search['burial_id']);
    if (userId == null || burialId == null) return;
    final normalized = _normalize(search, burialId: burialId);
    final local = await _loadLocal(userId);
    local.removeWhere((item) => _asInt(item['burialId']) == burialId);
    local.insert(0, normalized);
    await _writeLocal(userId, local.take(10).toList());
    try {
      await Supabase.instance.client
          .from(_table)
          .upsert(
            _toDatabase(userId, normalized),
            onConflict: 'user_id,burial_id',
          );
    } catch (_) {
      // The local copy remains available and will sync on the next load.
    }
  }

  static Future<void> clear() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_localKey(userId));
    await Supabase.instance.client.from(_table).delete().eq('user_id', userId);
  }

  static Future<void> _upsertMany(
    String userId,
    List<Map<String, dynamic>> searches,
  ) async {
    final rows = searches
        .where((search) => _asInt(search['burialId']) != null)
        .map((search) => _toDatabase(userId, search))
        .toList();
    if (rows.isEmpty) return;
    await Supabase.instance.client
        .from(_table)
        .upsert(rows, onConflict: 'user_id,burial_id');
  }

  static Map<String, dynamic> _normalize(
    Map<String, dynamic> search, {
    required int burialId,
  }) => {
    'name': search['name'] ?? search['deceased_name'] ?? 'Unknown',
    'details': search['details'],
    'lotNumber': search['lotNumber'] ?? search['lot_number'],
    'lotId': _asInt(search['lotId'] ?? search['lot_id']),
    'timestamp': search['timestamp'] ?? DateTime.now().toIso8601String(),
    'type': search['type'] ?? 'deceased',
    'burialId': burialId,
  };

  static Map<String, dynamic> _toDatabase(
    String userId,
    Map<String, dynamic> search,
  ) => {
    'user_id': userId,
    'burial_id': _asInt(search['burialId']),
    'lot_id': _asInt(search['lotId']),
    'deceased_name': search['name'] ?? 'Unknown',
    'details': search['details'],
    'lot_number': search['lotNumber']?.toString(),
    'search_type': search['type'] ?? 'deceased',
    'searched_at': search['timestamp'] ?? DateTime.now().toIso8601String(),
  };

  static Map<String, dynamic> _fromDatabase(Map<String, dynamic> row) => {
    'name': row['deceased_name'] ?? 'Unknown',
    'details': row['details'],
    'lotNumber': row['lot_number'],
    'lotId': row['lot_id'],
    'timestamp': row['searched_at'],
    'type': row['search_type'] ?? 'deceased',
    'burialId': row['burial_id'],
  };

  static Future<List<Map<String, dynamic>>> _loadLocal(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localKey(userId));
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _writeLocal(
    String userId,
    List<Map<String, dynamic>> searches,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localKey(userId), jsonEncode(searches));
  }

  static String _localKey(String userId) => 'recent_searches_$userId';

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
