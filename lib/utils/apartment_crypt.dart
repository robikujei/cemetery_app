const apartmentCryptBuildingNames = <String>{
  'mt. abarim',
  'mt. ararat',
  'mt. bashan',
  'mt. carmel',
  'mt. ebal',
  'mt. gerizim',
  'mt. gilboa',
  'mt. gilead',
  'mt. hermon',
  'mt. hor',
  'mt. horeb',
  'mt. lebanon',
  'mt. moriah',
  'mt. meron',
  'mt. nebo',
  'mt. olivet',
  'mt. zuriel',
  'mt. zion',
  'mt. zemaraim',
  'mt. tabor',
  'mt. sinai',
  'mt. seir',
};

bool isApartmentCryptLot(Map<String, dynamic> lot) {
  final blockNumber = lot['block_number']?.toString().trim() ?? '';
  final lotNumberText = lot['lot_number']?.toString().trim() ?? '';
  final normalizedBlock = int.tryParse(blockNumber);
  final normalizedLotNumber = int.tryParse(lotNumberText);

  // The apartment-crypt buildings occupy every Block 0 lot from 0065
  // through 0088, inclusive. Detect the range directly so the behavior does
  // not depend on whether an individual lot label was already migrated.
  if (normalizedBlock == 0 &&
      normalizedLotNumber != null &&
      normalizedLotNumber >= 65 &&
      normalizedLotNumber <= 88) {
    return true;
  }

  final values = [
    lot['lot_class_type'],
    lot['lot_label'],
    lot['lot_number'],
    lot['block_number'],
  ].map((value) => value?.toString().trim().toLowerCase() ?? '');

  for (final value in values) {
    if (value.contains('apartment') &&
        (value.contains('crypt') || value.contains('niche'))) {
      return true;
    }
    if (apartmentCryptBuildingNames.any(value.contains)) return true;
  }
  return false;
}

String apartmentCryptSlotCode(String wing, int slot) =>
    '${wing.toUpperCase()}-${slot.toString().padLeft(3, '0')}';

final RegExp _apartmentCryptLabelPattern = RegExp(
  r'^([AB])-([0-9]{3})(?:\s+-\s+(.+))?$',
  caseSensitive: false,
);

({String wing, int slot, String customLabel})? parseApartmentCryptLabel(
  String? label,
) {
  final match = _apartmentCryptLabelPattern.firstMatch(label?.trim() ?? '');
  if (match == null) return null;
  final slot = int.tryParse(match.group(2)!);
  if (slot == null || slot < 1 || slot > 100) return null;
  return (
    wing: match.group(1)!.toUpperCase(),
    slot: slot,
    customLabel: match.group(3)?.trim() ?? '',
  );
}

String apartmentCryptLabel({
  required String wing,
  required int slot,
  String customLabel = '',
}) {
  final code = apartmentCryptSlotCode(wing, slot);
  final suffix = customLabel.trim();
  return suffix.isEmpty ? code : '$code - $suffix';
}
