import '../core/surface_style.dart';
import 'package:flutter/material.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Ink(
        decoration: SurfaceStyle.panel(radius: 20),
        padding: padding,
        child: child,
      ),
    );
  }
}
