import '../widgets/deferred_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/auth/update_password_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/visitor/visitor_shell_screen.dart' deferred as visitor;
import '../screens/admin/admin_shell_screen.dart' deferred as admin;
import '../screens/guard/qr_scanner_screen.dart' deferred as guard;
import '../services/user_profile_service.dart';
import '../utils/app_role.dart';

String? _cachedRoleUserId;
String? _cachedHome;

final router = GoRouter(
  redirect: (context, state) async {
    // Recovery OTP verification creates a Supabase session; keep the user on
    // this public reset route until they have chosen a new password.
    if (state.matchedLocation == '/update-password') return null;
    final isPublicRoute =
        state.matchedLocation == '/login' ||
        state.matchedLocation == '/register' ||
        state.matchedLocation == '/forgot-password' ||
        state.matchedLocation == '/update-password';
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    final user = client.auth.currentUser;
    if (session == null || session.isExpired || user == null) {
      _cachedRoleUserId = null;
      _cachedHome = null;
      return isPublicRoute ? null : '/login';
    }
    if (_cachedRoleUserId == user.id && _cachedHome != null) {
      return state.matchedLocation == _cachedHome ? null : _cachedHome;
    }
    try {
      final profile = await loadAppUserProfile(client, user);
      final home = appHomeForRole(profile?['role']);
      if (home == null) {
        _cachedRoleUserId = null;
        _cachedHome = null;
        return '/login';
      }
      _cachedRoleUserId = user.id;
      _cachedHome = home;
      return state.matchedLocation == home ? null : home;
    } catch (_) {
      _cachedRoleUserId = null;
      _cachedHome = null;
      // Keep the public page visible if restoring the profile failed, rather
      // than trapping a user in a redirect loop while offline.
      return isPublicRoute ? null : '/login';
    }
  },
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(
      path: '/forgot-password',
      builder: (context, state) =>
          ForgotPasswordScreen(initialEmail: state.extra as String? ?? ''),
    ),
    GoRoute(
      path: '/update-password',
      builder: (context, state) => const UpdatePasswordScreen(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/visitor',
      builder: (context, state) => DeferredScreen(
        load: visitor.loadLibrary,
        builder: (_) => visitor.VisitorShellScreen(),
      ),
    ),
    GoRoute(
      path: '/admin',
      builder: (context, state) => DeferredScreen(
        load: admin.loadLibrary,
        builder: (_) => admin.AdminShellScreen(),
      ),
    ),
    GoRoute(
      path: '/gate-officer',
      builder: (context, state) => DeferredScreen(
        load: guard.loadLibrary,
        builder: (_) => guard.QrScannerScreen(),
      ),
    ),
    GoRoute(
      path: '/lot-owner',
      builder: (context, state) => DeferredScreen(
        load: visitor.loadLibrary,
        builder: (_) => visitor.VisitorShellScreen(),
      ),
    ),
  ],
);
