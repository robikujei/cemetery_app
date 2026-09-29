import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuditService {
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
