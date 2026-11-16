import 'package:cemetery_app/utils/app_audience.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('admin audience permits only administrators', () {
    expect(isRoleAllowedForAudience('admin', AppAudience.admin), isTrue);
    expect(isRoleAllowedForAudience('visitor', AppAudience.admin), isFalse);
    expect(
      isRoleAllowedForAudience('gate_officer', AppAudience.admin),
      isFalse,
    );
  });

  test('users audience permits all non-admin application roles', () {
    expect(isRoleAllowedForAudience('visitor', AppAudience.users), isTrue);
    expect(isRoleAllowedForAudience('lot_owner', AppAudience.users), isTrue);
    expect(isRoleAllowedForAudience('gate_officer', AppAudience.users), isTrue);
    expect(isRoleAllowedForAudience('admin', AppAudience.users), isFalse);
    expect(isRoleAllowedForAudience(null, AppAudience.users), isFalse);
  });
}
