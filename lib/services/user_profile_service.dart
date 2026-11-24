import 'package:supabase_flutter/supabase_flutter.dart';

const _profileColumns = 'user_id, name, role, email';

/// Loads the application profile for an authenticated Supabase user.
///
/// The Auth UUID is authoritative. If a legacy profile is still associated
/// with a previous Auth UUID, the secured edge function reconnects the profile
/// only when its email matches the signed-in account.
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

  try {
    final response = await client.functions
        .invoke(
          'admin-user-management',
          body: const {'action': 'recover_profile'},
        )
        .timeout(timeout);
    final data = response.data;
    if (data is Map && data['profile'] is Map) {
      return Map<String, dynamic>.from(data['profile'] as Map);
    }
  } catch (_) {
    // Keep the sign-in failure generic below. The server performs the actual
    // authorization and returns no profile when the account cannot be linked.
  }
  return null;
}
