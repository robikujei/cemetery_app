import '../widgets/deferred_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/visitor/visitor_shell_screen.dart' deferred as visitor;
import '../screens/guard/qr_scanner_screen.dart' deferred as guard;
import '../screens/lot_owner/lot_owner_home_screen.dart' deferred as owner;
import '../services/user_profile_service.dart';
import '../utils/app_role.dart';

String? _cachedRoleUserId;
String? _cachedHome;

final router = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) async {
    final isPublicRoute =
        state.matchedLocation == '/login' ||
        state.matchedLocation == '/register';
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
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
      path: '/gate-officer',
      builder: (context, state) => DeferredScreen(
        load: guard.loadLibrary,
        builder: (_) => guard.QrScannerScreen(),
      ),
    ),
    GoRoute(
      path: '/lot-owner',
      builder: (context, state) => DeferredScreen(
        load: owner.loadLibrary,
        builder: (_) => owner.LotOwnerHomeScreen(),
      ),
    ),
  ],
);
