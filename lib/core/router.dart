import 'package:go_router/go_router.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/update_password_screen.dart';
import '../screens/visitor/visitor_shell_screen.dart';
import '../screens/admin/admin_shell_screen.dart';
import '../screens/guard/qr_scanner_screen.dart';
import '../screens/lot_owner/lot_owner_home_screen.dart';
import '../utils/app_audience.dart';

final router = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(
      path: '/',
      redirect: (context, state) =>
          state.uri.queryParameters['screen'] == 'update-password'
          ? '/update-password'
          : '/login',
    ),
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
    if (isAdminApp)
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminShellScreen(),
      )
    else ...[
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/visitor',
        builder: (context, state) => const VisitorShellScreen(),
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
  ],
);
