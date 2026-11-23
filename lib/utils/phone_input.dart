import 'package:flutter/services.dart';

/// Allows phone digits and conventional formatting characters, but no letters.
final phoneInputFormatters = <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp(r'[0-9+()\-\s]')),
];
