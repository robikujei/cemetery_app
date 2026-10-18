import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart'; // ← This now has 'router'
import '../providers/theme_provider.dart';
import 'theme.dart';

class CemeteryApp extends StatelessWidget {
  const CemeteryApp({super.key});

  @override
  Widget build(BuildContext context) =>
      ProviderScope(child: const _CemeteryMaterialApp());
}

class _CemeteryMaterialApp extends ConsumerWidget {
  const _CemeteryMaterialApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Cemetery Grave Finder',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: router, // ← Changed from 'appRouter' to 'router'
    );
  }
}
