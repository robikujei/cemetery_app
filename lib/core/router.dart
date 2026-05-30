import 'package:go_router/go_router.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/visitor/visitor_shell_screen.dart';
import '../screens/admin/admin_shell_screen.dart';
import '../screens/guard/qr_scanner_screen.dart';
import '../screens/lot_owner/lot_owner_home_screen.dart';
import '../screens/lot_owner/lot_owner_payment_screen.dart';

final router = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
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
    GoRoute(
      path: '/lot-owner-payment',
      builder: (context, state) => const LotOwnerPaymentScreen(),
    ),
  ],
);