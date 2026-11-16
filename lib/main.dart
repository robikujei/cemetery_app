import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter/widgets.dart';
import 'core/app.dart';
import 'core/supabase_bootstrap.dart';

Future<void> main() async {
  usePathUrlStrategy();
  await bootstrapSupabase();
  runApp(const ProviderScope(child: CemeteryApp()));
}
