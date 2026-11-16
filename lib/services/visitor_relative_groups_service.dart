import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VisitorRelativeGroupsService {
  static String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  static String? _key(String suffix) {
    final userId = _userId;
    return userId == null ? null : 'visitor_relative_${suffix}_$userId';
  }

  static Future<List<String>> loadGroups() async {
    final key = _key('groups');
    if (key == null) return [];
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(key) ?? []).toList();
  }

  static Future<Map<String, Map<String, dynamic>>> loadAssignments() async {
    final key = _key('assignments');
    if (key == null) return {};
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map(
      (name, value) => MapEntry(name, Map<String, dynamic>.from(value as Map)),
    );
  }

  static Future<List<String>> createGroup(String name) async {
    final key = _key('groups');
    if (key == null) return [];
    final prefs = await SharedPreferences.getInstance();
    final groups = prefs.getStringList(key) ?? [];
    if (!groups.any((group) => group.toLowerCase() == name.toLowerCase())) {
      groups.add(name);
      await prefs.setStringList(key, groups);
    }
    return groups;
  }

  static Future<void> setAssignment(
    String name, {
    bool? favorite,
    String? group,
  }) async {
    final key = _key('assignments');
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    final assignments = await loadAssignments();
    final current = assignments[name] ?? <String, dynamic>{};
    if (favorite != null) current['favorite'] = favorite;
    if (group != null) current['group'] = group;
    assignments[name] = current;
    await prefs.setString(key, jsonEncode(assignments));
  }
}
