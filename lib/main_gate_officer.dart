import 'package:flutter/widgets.dart';
import 'core/role_app.dart';
import 'core/supabase_bootstrap.dart';
import 'screens/guard/qr_scanner_screen.dart';

Future<void> main() async {
  await bootstrapSupabase();
  runApp(const RoleApp(role: 'gate_officer', path: '/gate-officer', home: QrScannerScreen()));
}
