import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Visitor bottom navigation selected index (Home / Map / Scan / Profile).
final visitorNavIndexProvider = StateProvider<int>((ref) => 0);

