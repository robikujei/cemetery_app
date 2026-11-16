import 'package:cemetery_app/utils/restricted_app_roles.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('permits only visitor, lot-owner, and gate-officer roles', () {
    expect(isGeoGraveAllowedRole('visitor'), isTrue);
    expect(isGeoGraveAllowedRole('lot_owner'), isTrue);
    expect(isGeoGraveAllowedRole('gate_officer'), isTrue);
    expect(isGeoGraveAllowedRole('admin'), isFalse);
    expect(isGeoGraveAllowedRole(null), isFalse);
    expect(isGeoGraveAllowedRole('new_privileged_role'), isFalse);
  });
}
