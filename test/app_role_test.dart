import 'package:cemetery_app/utils/app_role.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy Gate Officer roles normalize to the current role', () {
    for (final role in ['guard', 'Gate Officer', 'gate-officer']) {
      expect(normalizeAppRole(role), 'gate_officer');
      expect(appHomeForRole(role), '/gate-officer');
    }
  });

  test('all supported roles resolve to their portal home', () {
    expect(appHomeForRole('admin'), '/admin');
    // Ownership is an unlocked capability inside the Visitor shell.
    expect(appHomeForRole('lot_owner'), '/lot-owner');
    expect(appHomeForRole('visitor'), '/visitor');
    expect(appHomeForRole('gate_officer'), '/gate-officer');
  });

  test('GeoGrave accepts supported roles and rejects unknown roles', () {
    expect(isGeoGraveAllowedRole('visitor'), isTrue);
    expect(isGeoGraveAllowedRole('lot_owner'), isTrue);
    expect(isGeoGraveAllowedRole('gate_officer'), isTrue);
    expect(isGeoGraveAllowedRole('admin'), isTrue);
    expect(isGeoGraveAllowedRole('unknown'), isFalse);
  });

  test('missing and unknown roles do not receive portal access', () {
    expect(appHomeForRole(null), isNull);
    expect(appHomeForRole('unknown'), isNull);
  });
}
