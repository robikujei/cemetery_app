import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'core/app.dart';
import 'core/supabase_bootstrap.dart';

Future<void> main() async {
  await bootstrapSupabase();
  runApp(const ProviderScope(child: CemeteryApp()));
}
