import 'package:supabase_flutter/supabase_flutter.dart';

class AuditService {
  static final supabase = Supabase.instance.client;
  
  static Future<void> log({
    required String action,
    String? entityType,
    String? entityId,
    String? details,
  }) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      
      // Get user details
      final userData = await supabase
          .from('users')
          .select('name, email, role')
          .eq('email', user.email!)
          .maybeSingle();
      
      await supabase.from('audit_log').insert({
        'user_id': user.id,
        'user_email': user.email,
        'user_role': userData?['role'] ?? 'unknown',
        'action': action,
        'entity_type': entityType,
        'entity_id': entityId,
        'details': details,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Audit log error: $e');
    }
  }
}