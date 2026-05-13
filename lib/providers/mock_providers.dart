import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/grave_record.dart';
import '../models/visitor_log.dart';
import '../services/mock_repository.dart';

final mockRepositoryProvider = Provider<MockRepository>((ref) => const MockRepository());

final gravesProvider = Provider<List<GraveRecord>>((ref) {
  return ref.watch(mockRepositoryProvider).graves();
});

final visitorLogsProvider = Provider.family<List<VisitorLog>, String>((ref, visitorId) {
  return ref.watch(mockRepositoryProvider).visitorLogsFor(visitorId);
});

