import 'package:flutter/material.dart';

import 'router.dart';
import 'theme.dart';

class CemeteryApp extends StatelessWidget {
  const CemeteryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Cemetery Grave Finder',
      theme: AppTheme.light(),
      routerConfig: appRouter,
    );
  }
}

