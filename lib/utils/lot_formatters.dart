String lotText(dynamic lot, String key) {
  if (lot is! Map) return '';
  return lot[key]?.toString().trim() ?? '';
}

String lotReference(dynamic lot, {String fallback = 'N/A'}) {
  final label = lotText(lot, 'lot_label');
  if (label.isNotEmpty) return label;

  final block = lotText(lot, 'block_number');
  final number = lotText(lot, 'lot_number');
  if (block.isNotEmpty && number.isNotEmpty) return '$block-$number';
  if (number.isNotEmpty) return number;
  if (block.isNotEmpty) return block;
  return fallback;
}

String lotMeta(dynamic lot) {
  if (isFamilyEstateLot(lot)) {
    final phase = familyEstatePhase(lot);
    final estate = lotText(lot, 'lot_number');
    return [
      'Family Estate',
      if (phase.isNotEmpty) 'Phase $phase',
      if (estate.isNotEmpty) 'Estate $estate',
    ].join(' · ');
  }
  final parts = [
    if (lotText(lot, 'block_number').isNotEmpty)
      'Block ${lotText(lot, 'block_number')}',
    if (lotText(lot, 'lot_class_type').isNotEmpty)
      lotText(lot, 'lot_class_type'),
  ];
  return parts.join(' - ');
}

bool isFamilyEstateLot(dynamic lot) {
  if (lotText(lot, 'lot_class_type').toLowerCase() == 'family estate') {
    return true;
  }

  // Family Estate plots already drawn on the map were supplied as these
  // legacy plot IDs. Keep them in the Family Estate UI while their stored
  // lot type/phase labels are progressively cleaned up.
  final plotIdPattern = RegExp(r'(?:^|\s)0-(\d+)(?:$|\s)');
  final candidates = [lotText(lot, 'lot_number'), lotText(lot, 'lot_label')];
  return candidates.any((value) {
    final number = int.tryParse(
      plotIdPattern.firstMatch(value)?.group(1) ?? '',
    );
    return number != null &&
        ((number >= 1 && number <= 64) || (number >= 4566 && number <= 4585));
  });
}

/// Accepts `1`, `Phase 1`, or `Family Estate Phase 1` in the existing block
/// field while the map data transitions to the Family Estate vocabulary.
String familyEstatePhase(dynamic lot) {
  final source = '${lotText(lot, 'block_number')} ${lotText(lot, 'lot_label')}';
  final match = RegExp(
    r'(?:phase|p)\s*([12])',
    caseSensitive: false,
  ).firstMatch(source);
  return match?.group(1) ?? '';
}

String lotBlockLabel(dynamic lot, {String fallback = 'N/A'}) {
  final block = lotText(lot, 'block_number');
  return block.isEmpty ? fallback : 'Block $block';
}

String lotSearchText(dynamic lot) {
  return [
    lotReference(lot, fallback: ''),
    lotText(lot, 'lot_number'),
    lotText(lot, 'lot_label'),
    lotText(lot, 'block_number'),
    lotText(lot, 'lot_class_type'),
    lotText(lot, 'status'),
  ].where((value) => value.isNotEmpty).join(' ').toLowerCase();
}
