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
  final parts = [
    if (lotText(lot, 'block_number').isNotEmpty)
      'Block ${lotText(lot, 'block_number')}',
    if (lotText(lot, 'lot_class_type').isNotEmpty)
      lotText(lot, 'lot_class_type'),
  ];
  return parts.join(' - ');
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
