import 'package:supabase_flutter/supabase_flutter.dart';

class AuditService {
  static final supabase = Supabase.instance.client;
  
  // Centralized audit logging method
  static Future<void> log({
    required String action,
    required String entityType,
    String? entityId,
    String? details,
  }) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        print('⚠️ AUDIT: No user logged in, skipping log');
        return;
      }
      
      print('📝 AUDIT: Logging $action for $entityType');
      
      await supabase.from('audit_log').insert({
        'user_email': user.email,
        'user_role': 'admin', // You can fetch from users table if needed
        'action': action,
        'entity_type': entityType,
        'entity_id': entityId,
        'details': details,
        'created_at': DateTime.now().toIso8601String(),
      });
      
      print('✅ AUDIT: Successfully logged');
    } catch (e) {
      print('❌ AUDIT ERROR: $e');
    }
  }
}