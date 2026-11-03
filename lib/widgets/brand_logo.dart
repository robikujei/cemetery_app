import 'package:flutter/material.dart';

/// The Eternal Garden brand mark for welcome and sign-in experiences.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.height = 112});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Eternal Garden logo',
      child: Image.asset(
        'eternal garden logo.png',
        height: height,
        fit: BoxFit.contain,
      ),
    );
  }
}
