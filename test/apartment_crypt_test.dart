import 'package:cemetery_app/utils/apartment_crypt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes apartment crypt lots by type or known building name', () {
    expect(
      isApartmentCryptLot({'lot_class_type': 'Apartment-Type Crypt'}),
      isTrue,
    );
    expect(isApartmentCryptLot({'lot_label': 'Mt. Abarim'}), isTrue);
    expect(
      isApartmentCryptLot({'lot_label': 'Building 01 - Mt. Abarim'}),
      isTrue,
    );
    expect(isApartmentCryptLot({'lot_class_type': 'Regular Lot'}), isFalse);
    for (var lotNumber = 65; lotNumber <= 88; lotNumber++) {
      expect(
        isApartmentCryptLot({
          'block_number': '0',
          'lot_number': lotNumber.toString().padLeft(4, '0'),
          'lot_class_type': 'Regular Lot',
        }),
        isTrue,
        reason: 'Block 0 lot $lotNumber must be an apartment crypt',
      );
    }
    expect(
      isApartmentCryptLot({'block_number': '0', 'lot_number': '0064'}),
      isFalse,
    );
    expect(
      isApartmentCryptLot({'block_number': '0', 'lot_number': '0089'}),
      isFalse,
    );
  });

  test('builds and parses stable crypt slot labels', () {
    expect(
      apartmentCryptLabel(wing: 'a', slot: 7, customLabel: 'Santos'),
      'A-007 - Santos',
    );
    final parsed = parseApartmentCryptLabel('A-007 - Santos');
    expect(parsed?.wing, 'A');
    expect(parsed?.slot, 7);
    expect(parsed?.customLabel, 'Santos');
  });
}
