import 'package:cemetery_app/utils/lot_label_batch.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> lot(int id, {String block = 'A', String? number}) => {
  'lot_id': id,
  'block_number': block,
  'lot_number': number,
  'lot_label': number == null ? null : '$block-$number',
};

void main() {
  test('row numbers use at least three digits across decimal boundaries', () {
    for (final entry in {
      '1': ['001', '002'],
      '9': ['009', '010'],
      '99': ['099', '100'],
      '999': ['999', '1000'],
    }.entries) {
      final plan = planLotLabels([lot(1), lot(2)], entry.key);
      expect(plan.map((change) => change.number), entry.value);
      expect(plan.first.label, 'A-${entry.value.first}');
    }
  });
  test(
    'duplicate override allows collisions but retains stale and missing record checks',
    () {
      final selected = lot(1, number: '5');
      final other = lot(2, number: '10');
      final plan = planLotLabels([selected], '10');
      expect(
        () => validateLotLabelBatch(plan, [
          selected,
          other,
        ], allowDuplicateNumbers: true),
        returnsNormally,
      );
      expect(
        () => validateLotLabelBatch(plan, [
          lot(1, number: '6'),
          other,
        ], allowDuplicateNumbers: true),
        throwsFormatException,
      );
      expect(
        () => validateLotLabelBatch(plan, [other], allowDuplicateNumbers: true),
        throwsFormatException,
      );
      final blockPlan = planLotBlocks([
        lot(1, block: '36', number: '1'),
        lot(2, block: '35', number: '1'),
      ], '12');
      expect(
        () => validateLotLabelBatch(
          blockPlan,
          blockPlan.map((change) => change.before).toList(),
          allowDuplicateNumbers: true,
        ),
        returnsNormally,
      );
    },
  );
  test('block reassignment retains lot numbers and rebuilds labels', () {
    final source = lot(1, block: '36', number: '001');
    final plan = planLotBlocks([source], '12');
    expect(plan.single.block, '12');
    expect(plan.single.number, '001');
    expect(plan.single.updates, {'block_number': '12', 'lot_label': '12-001'});
    expect(source['block_number'], '36');
    validateLotLabelBatch(plan, [source]);
  });

  test(
    'block assignment supports unnumbered lots without assigning numbers',
    () {
      final source = lot(1, block: '36');
      final plan = planLotBlocks([source], '12');
      expect(plan.single.updates, {'block_number': '12', 'lot_label': '12'});
      validateLotLabelBatch(plan, [source, lot(2, block: '12')]);
      expect(() => planLotBlocks([source], ' '), throwsFormatException);
    },
  );

  test(
    'block assignment rejects duplicate destinations inside and outside the batch',
    () {
      final first = lot(1, block: '36', number: '1');
      final second = lot(2, block: '35', number: '01');
      expect(
        () => validateLotLabelBatch(planLotBlocks([first, second], '12'), [
          first,
          second,
        ]),
        throwsFormatException,
      );
      expect(
        () => validateLotLabelBatch(planLotBlocks([first], '12'), [
          first,
          lot(3, block: '12', number: '1'),
        ]),
        throwsFormatException,
      );
    },
  );

  test('numbering follows click order and preserves leading zeros', () {
    final plan = planLotLabels([lot(8), lot(2), lot(5)], '009');
    expect(plan.map((item) => item.id), [8, 2, 5]);
    expect(plan.map((item) => item.number), ['009', '010', '011']);
    expect(plan.last.label, 'A-011');
  });

  test('removal, reversal and batch boundary affect only selected lots', () {
    final selected = [lot(1), lot(2), lot(3)];
    selected.removeAt(1);
    final plan = planLotLabels(selected.reversed.toList(), '101');
    expect(plan.map((item) => item.id), [3, 1]);
    expect(plan.map((item) => item.number), ['101', '102']);
  });

  test(
    'rejects empty selection, invalid starts, mixed blocks and repeated lots',
    () {
      expect(() => planLotLabels([], '1'), throwsFormatException);
      for (final start in ['0', '-1', '1.5', '', 'A1', '1000000000']) {
        expect(() => planLotLabels([lot(1)], start), throwsFormatException);
      }
      expect(
        () => planLotLabels([lot(1), lot(2, block: 'B')], '1'),
        throwsFormatException,
      );
      expect(
        () => planLotLabels([lot(1, block: '')], '1'),
        throwsFormatException,
      );
      expect(() => planLotLabels([lot(1), lot(1)], '1'), throwsFormatException);
    },
  );

  test(
    'rejects duplicate number in the same block, including padded numbers',
    () {
      final selected = lot(1);
      final plan = planLotLabels([selected], '001');
      expect(
        () => validateLotLabelBatch(plan, [selected, lot(2, number: '1')]),
        throwsFormatException,
      );
      expect(
        () => validateLotLabelBatch(plan, [
          selected,
          lot(2, block: 'B', number: '1'),
        ]),
        returnsNormally,
      );
    },
  );

  test('allows retaining own number but rejects overlapping renumbering', () {
    final first = lot(1, number: '1');
    final second = lot(2, number: '2');
    expect(
      () => validateLotLabelBatch(planLotLabels([first], '1'), [first, second]),
      returnsNormally,
    );
    expect(
      () => validateLotLabelBatch(planLotLabels([first, second], '2'), [
        first,
        second,
      ]),
      throwsFormatException,
    );
  });

  test('detects changed or deleted lots before saving', () {
    final selected = lot(1, number: '5');
    final plan = planLotLabels([selected], '10');
    expect(() => validateLotLabelBatch(plan, []), throwsFormatException);
    expect(
      () => validateLotLabelBatch(plan, [lot(1, number: '6')]),
      throwsFormatException,
    );
    expect(
      () => validateLotLabelBatch(plan, [
        {...selected, 'lot_label': 'custom'},
      ]),
      throwsFormatException,
    );
    expect(() => validateLotLabelBatch(plan, [selected]), returnsNormally);
  });
}
