class LotLabelChange {
  LotLabelChange(this.before, this.number, {this.targetBlock});

  final Map<String, dynamic> before;
  final String number;
  final String? targetBlock;
  dynamic get id => before['lot_id'];
  String get block => targetBlock ?? before['block_number'].toString().trim();
  String get label => number.isEmpty ? block : '$block-$number';
  Map<String, dynamic> get updates => {
    if (targetBlock != null) 'block_number': block else 'lot_number': number,
    'lot_label': label,
  };
}

List<LotLabelChange> planLotBlocks(
  List<Map<String, dynamic>> lots,
  String block,
) {
  block = block.trim();
  if (block.isEmpty || block.length > 50) {
    throw const FormatException('Enter a block number (up to 50 characters).');
  }
  if (lots.isEmpty) throw const FormatException('Select at least one lot.');
  final ids = <String>{};
  return lots.map((lot) {
    if (lot['lot_id'] == null || !ids.add(lot['lot_id'].toString())) {
      throw const FormatException('Each lot must be selected only once.');
    }
    return LotLabelChange(
      Map<String, dynamic>.from(lot),
      lot['lot_number']?.toString().trim() ?? '',
      targetBlock: block,
    );
  }).toList();
}

List<LotLabelChange> planLotLabels(
  List<Map<String, dynamic>> orderedLots,
  String start,
) {
  final first = int.tryParse(start);
  if (!RegExp(r'^\d+$').hasMatch(start) ||
      first == null ||
      first < 1 ||
      first > 999999999) {
    throw const FormatException('Enter a starting number from 1 to 999999999.');
  }
  if (orderedLots.isEmpty) {
    throw const FormatException('Select at least one lot.');
  }
  final block = orderedLots.first['block_number']?.toString().trim() ?? '';
  if (block.isEmpty) {
    throw const FormatException(
      'Assign a block to these lots before labeling a row.',
    );
  }
  final ids = <String>{};
  for (final lot in orderedLots) {
    if (lot['lot_id'] == null || !ids.add(lot['lot_id'].toString())) {
      throw const FormatException('Each lot must be selected only once.');
    }
    if (lot['block_number']?.toString().trim() != block) {
      throw const FormatException('Select lots from one block per batch.');
    }
  }
  return [
    for (var i = 0; i < orderedLots.length; i++)
      LotLabelChange(
        Map<String, dynamic>.from(orderedLots[i]),
        (first + i).toString().padLeft(
          start.length < 3 ? 3 : start.length,
          '0',
        ),
      ),
  ];
}

/// Validate against every lot, including lots without map markers.
void validateLotLabelBatch(
  List<LotLabelChange> changes,
  List<Map<String, dynamic>> currentLots, {
  bool allowDuplicateNumbers = false,
}) {
  String normalized(Object? value) {
    final text = value?.toString().trim() ?? '';
    return int.tryParse(text)?.toString() ?? text.toLowerCase();
  }

  final destinations = <String>{};
  for (final change in changes) {
    if (!allowDuplicateNumbers &&
        change.number.isNotEmpty &&
        !destinations.add(
          '${normalized(change.block)}:${normalized(change.number)}',
        )) {
      throw FormatException(
        'Selected lots would share number ${change.number} in block ${change.block}. Correct their lot numbers first.',
      );
    }
    final matches = currentLots.where(
      (lot) => lot['lot_id'].toString() == change.id.toString(),
    );
    if (matches.length != 1) {
      throw const FormatException(
        'A selected lot no longer exists. Select the row again.',
      );
    }
    for (final field in ['block_number', 'lot_number', 'lot_label']) {
      if (matches.single[field] != change.before[field]) {
        throw const FormatException(
          'A selected lot changed. Select the row again.',
        );
      }
    }
    final conflict =
        !allowDuplicateNumbers &&
        change.number.isNotEmpty &&
        currentLots.any(
          (lot) =>
              lot['lot_id'].toString() != change.id.toString() &&
              normalized(lot['block_number']) == normalized(change.block) &&
              normalized(lot['lot_number']) == normalized(change.number),
        );
    if (conflict) {
      throw FormatException(
        'Lot ${change.number} already exists in block ${change.block}. Choose a different range.',
      );
    }
  }
}
