import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/admin/admin_shell_screen.dart' deferred as admin;
import '../screens/guard/qr_scanner_screen.dart' deferred as guard;
import '../screens/visitor/visitor_shell_screen.dart' deferred as visitor;
import '../providers/theme_provider.dart';
import '../services/user_profile_service.dart';
import '../utils/app_role.dart';
import '../widgets/deferred_screen.dart';
import 'theme.dart';

class RoleApp extends StatelessWidget {
  const RoleApp({
    super.key,
    required this.role,
    required this.path,
    required this.home,
    this.bypassAuth = false,
  });
  final String role;
  final String path;
  final Widget home;
  final bool bypassAuth;

  String get portalName => switch (role) {
    'admin' => 'Administrator portal',
    'gate_officer' => 'Gate officer portal',
    'lot_owner' => 'Lot owner portal',
    _ => 'Visitor portal',
  };

  @override
  Widget build(BuildContext context) => ProviderScope(
    child: _RoleMaterialApp(
      role: role,
      path: path,
      home: home,
      bypassAuth: bypassAuth,
      portalName: portalName,
    ),
  );
}

class _RoleMaterialApp extends ConsumerWidget {
  const _RoleMaterialApp({
    required this.role,
    required this.path,
    required this.home,
    required this.bypassAuth,
    required this.portalName,
  });

  final String role;
  final String path;
  final Widget home;
  final bool bypassAuth;
  final String portalName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Cemetery Grave Finder',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: GoRouter(
        initialLocation: path,
        redirect: (context, state) async {
          if (state.matchedLocation == '/login' ||
              state.matchedLocation == '/register') {
            return null;
          }
          if (bypassAuth) return null;
          final auth = Supabase.instance.client.auth;
          final session = auth.currentSession;
          final user = auth.currentUser;
          if (session == null || session.isExpired || user == null) {
            return '/login';
          }
          try {
            final client = Supabase.instance.client;
            final profile = await loadAppUserProfile(client, user);
            final home = appHomeForRole(profile?['role']);
            if (home == null) return '/login';
            return state.matchedLocation == home ? null : home;
          } catch (_) {
            return '/login';
          }
        },
        routes: [
          GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
          GoRoute(
            path: '/register',
            builder: (_, _) => role == 'visitor'
                ? const RegisterScreen()
                : LoginScreen(requiredRole: role, portalName: portalName),
          ),
          GoRoute(
            path: '/visitor',
            builder: (_, _) => DeferredScreen(
              load: visitor.loadLibrary,
              builder: (_) => visitor.VisitorShellScreen(),
            ),
          ),
          GoRoute(
            path: '/admin',
            builder: (_, _) => DeferredScreen(
              load: admin.loadLibrary,
              builder: (_) => admin.AdminShellScreen(),
            ),
          ),
          GoRoute(
            path: '/gate-officer',
            builder: (_, _) => DeferredScreen(
              load: guard.loadLibrary,
              builder: (_) => guard.QrScannerScreen(),
            ),
          ),
          GoRoute(
            path: '/lot-owner',
            builder: (_, _) => DeferredScreen(
              load: visitor.loadLibrary,
              builder: (_) => visitor.VisitorShellScreen(),
            ),
          ),
        ],
      ),
    );
  }
}
