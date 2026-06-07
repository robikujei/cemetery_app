class GraveRecord {
  const GraveRecord({
    required this.id,
    required this.deceasedName,
    required this.birthDate,
    required this.deathDate,
    required this.burialDate,
    required this.blockName,
    required this.lotNumber,
  });

  final String id;
  final String deceasedName;
  final DateTime? birthDate;
  final DateTime? deathDate;
  final DateTime? burialDate;
  final String blockName;
  final String lotNumber;
}
