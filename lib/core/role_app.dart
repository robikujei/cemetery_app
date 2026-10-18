import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import 'theme.dart';

class RoleApp extends StatelessWidget {
  const RoleApp({super.key, required this.role, required this.path, required this.home});
  final String role;
  final String path;
  final Widget home;

  String get portalName => switch (role) {
    'admin' => 'Administrator portal',
    'gate_officer' => 'Gate officer portal',
    'lot_owner' => 'Lot owner portal',
    _ => 'Visitor portal',
  };

  @override
  Widget build(BuildContext context) => ProviderScope(
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: 'Cemetery Grave Finder',
          theme: AppTheme.light(),
          routerConfig: GoRouter(
            initialLocation: path,
            redirect: (context, state) async {
              if (state.matchedLocation == '/login' || state.matchedLocation == '/register') return null;
              final user = Supabase.instance.client.auth.currentUser;
              if (user == null) return '/login';
              try {
                final client = Supabase.instance.client;
                var profile = await client
                    .from('users')
                    .select('role')
                    .eq('user_id', user.id)
                    .maybeSingle();
                if (profile == null && user.email != null) {
                  profile = await client
                      .from('users')
                      .select('role')
                      .eq('email', user.email!.trim().toLowerCase())
                      .maybeSingle();
                }
                final actualRole = profile?['role']?.toString().trim().toLowerCase();
                return actualRole == role.trim().toLowerCase() ? null : '/login';
              } catch (_) {
                return '/login';
              }
            },
            routes: [
              GoRoute(path: '/login', builder: (_, __) => LoginScreen(requiredRole: role, portalName: portalName)),
              GoRoute(
                path: '/register',
                builder: (_, __) => role == 'visitor'
                    ? const RegisterScreen()
                    : LoginScreen(requiredRole: role, portalName: portalName),
              ),
              GoRoute(path: path, builder: (_, __) => home),
            ],
          ),
        ),
      );
}
