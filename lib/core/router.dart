import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/visitor/visitor_shell_screen.dart';
import '../screens/admin/admin_shell_screen.dart';
import '../screens/guard/qr_scanner_screen.dart';
import '../screens/lot_owner/lot_owner_home_screen.dart';

final router = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) async {
    if (state.matchedLocation == '/login' || state.matchedLocation == '/register') {
      return null;
    }
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return '/login';
    try {
      final profile = await client.from('users').select('role')
          .eq('user_id', user.id).maybeSingle();
      final home = switch (profile?['role']) {
        'admin' => '/admin',
        'gate_officer' => '/gate-officer',
        'lot_owner' => '/lot-owner',
        'visitor' => '/visitor',
        _ => '/login',
      };
      return state.matchedLocation == home ? null : home;
    } catch (_) {
      return '/login';
    }
  },
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/visitor',
      builder: (context, state) => const VisitorShellScreen(),
    ),
    GoRoute(
      path: '/admin',
      builder: (context, state) => const AdminShellScreen(),
    ),
    GoRoute(
      path: '/gate-officer',
      builder: (context, state) => const QrScannerScreen(),
    ),
    GoRoute(
      path: '/lot-owner',
      builder: (context, state) => const LotOwnerHomeScreen(),
    ),
  ],
);
