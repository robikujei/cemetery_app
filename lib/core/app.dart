import 'package:flutter/material.dart';

import 'router.dart'; // ← This now has 'router'
import 'theme.dart';

class CemeteryApp extends StatelessWidget {
  const CemeteryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Cemetery Grave Finder',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router, // ← Changed from 'appRouter' to 'router'
    );
  }
}
