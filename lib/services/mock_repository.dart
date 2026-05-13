import '../models/grave_record.dart';
import '../models/visitor_log.dart';

class MockRepository {
  const MockRepository();

  List<GraveRecord> graves() => [
        GraveRecord(
          id: 'g1',
          deceasedName: 'Juan Dela Cruz',
          birthDate: DateTime(1952, 4, 3),
          deathDate: DateTime(2021, 11, 12),
          burialDate: DateTime(2021, 11, 18),
          sectionName: 'Section A',
          lotNumber: 'A-014',
        ),
        GraveRecord(
          id: 'g2',
          deceasedName: 'Maria Santos',
          birthDate: DateTime(1960, 1, 9),
          deathDate: DateTime(2020, 6, 1),
          burialDate: DateTime(2020, 6, 7),
          sectionName: 'Section B',
          lotNumber: 'B-108',
        ),
        GraveRecord(
          id: 'g3',
          deceasedName: 'Pedro Ramos',
          birthDate: DateTime(1944, 9, 20),
          deathDate: DateTime(2019, 2, 2),
          burialDate: DateTime(2019, 2, 6),
          sectionName: 'Section C',
          lotNumber: 'C-032',
        ),
      ];

  List<VisitorLog> visitorLogsFor(String visitorId) => [
        VisitorLog(
          id: 'v1',
          visitorId: visitorId,
          graveId: 'g2',
          createdAt: DateTime.now().subtract(const Duration(days: 3, hours: 2)),
        ),
        VisitorLog(
          id: 'v2',
          visitorId: visitorId,
          graveId: 'g1',
          createdAt: DateTime.now().subtract(const Duration(days: 9, hours: 1)),
        ),
      ];
}

