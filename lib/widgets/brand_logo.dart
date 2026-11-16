import 'package:flutter/material.dart';

/// The Eternal Garden brand mark used on entry and authentication screens.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.height = 104});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Eternal Garden logo',
      child: Image.asset(
        'assets/images/eternal_garden_logo.png',
        height: height,
        fit: BoxFit.contain,
      ),
    );
  }
}
