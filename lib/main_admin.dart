import 'package:flutter/widgets.dart';
import 'core/role_app.dart';
import 'core/supabase_bootstrap.dart';
import 'screens/admin/admin_shell_screen.dart';

Future<void> main() async {
  await bootstrapSupabase();
  runApp(const RoleApp(role: 'admin', path: '/admin', home: AdminShellScreen()));
}
