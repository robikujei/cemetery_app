import 'package:flutter/widgets.dart';
import 'core/role_app.dart';
import 'core/supabase_bootstrap.dart';
import 'screens/admin/admin_shell_screen.dart';
import 'screens/admin/admin_analytics_screen.dart';

const _mockAnalytics = bool.fromEnvironment(
  'MOCK_ANALYTICS',
  defaultValue: false,
);

Future<void> main() async {
  await bootstrapSupabase();
  runApp(
    RoleApp(
      role: 'admin',
      path: _mockAnalytics ? '/demo-reports' : '/admin',
      home: _mockAnalytics
          ? const AdminAnalyticsScreen()
          : const AdminShellScreen(),
      bypassAuth: _mockAnalytics,
    ),
  );
}
