import 'package:supabase_flutter/supabase_flutter.dart';

const _profileColumns = 'user_id, name, role, email';

/// Loads the application profile for an authenticated Supabase user.
///
/// The Auth UUID is authoritative. The email lookup is retained for databases
/// that have not yet run the Gate Officer profile repair, provided their RLS
/// policy permits that legacy row to be read.
Future<Map<String, dynamic>?> loadAppUserProfile(
  SupabaseClient client,
  User authUser, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final byId = await client
      .from('users')
      .select(_profileColumns)
      .eq('user_id', authUser.id)
      .maybeSingle()
      .timeout(timeout);
  if (byId != null) return Map<String, dynamic>.from(byId);

  final email = authUser.email?.trim().toLowerCase();
  if (email == null || email.isEmpty) return null;

  final byEmail = await client
      .from('users')
      .select(_profileColumns)
      .eq('email', email)
      .maybeSingle()
      .timeout(timeout);
  return byEmail == null ? null : Map<String, dynamic>.from(byEmail);
}
