import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuditService {
  static Future<void> logMany(List<Map<String, dynamic>> entries) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null || entries.isEmpty) return;
    try {
      final profile = await supabase
          .from('users')
          .select('role')
          .eq('user_id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 20));
      for (var offset = 0; offset < entries.length; offset += 200) {
        await supabase
            .from('audit_log')
            .insert(
              entries
                  .skip(offset)
                  .take(200)
                  .map(
                    (entry) => {
                      ...entry,
                      'user_id': user.id,
                      'user_email': user.email,
                      'user_role': profile?['role'] ?? 'unknown',
                      'created_at': DateTime.now().toUtc().toIso8601String(),
                    },
                  )
                  .toList(),
            )
            .timeout(const Duration(seconds: 20));
      }
    } catch (e) {
      debugPrint('Batch audit logging failed: $e');
      rethrow;
    }
  }

  static Future<void> log({
    required String action,
    String? entityType,
    String? entityId,
    String? details,
  }) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final profile = await supabase
          .from('users')
          .select('role')
          .eq('user_id', user.id)
          .maybeSingle();
      await supabase.from('audit_log').insert({
        'user_id': user.id,
        'user_email': user.email,
        'user_role': profile?['role'] ?? 'unknown',
        'action': action,
        'entity_type': entityType,
        'entity_id': entityId,
        'details': details,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Audit logging failed: $e');
    }
  }
}
