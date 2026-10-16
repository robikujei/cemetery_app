import 'dart:async';
import 'package:cemetery_app/services/logout_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('audit failure cannot prevent clearing the session', () async {
    var active = true;
    await endSession(
      recordAudit: () async => throw StateError('audit unavailable'),
      signOut: () async {
        active = false;
      },
      hasSession: () => active,
    );
    expect(active, isFalse);
  });
  test(
    'stalled audit and remote revocation cannot trap a signed out user',
    () async {
      var active = true;
      await endSession(
        recordAudit: () => Completer<void>().future,
        signOut: () {
          active = false;
          return Completer<void>().future;
        },
        hasSession: () => active,
        auditTimeout: const Duration(milliseconds: 10),
        signOutTimeout: const Duration(milliseconds: 10),
      );
      expect(active, isFalse);
    },
  );
  test('remote failure is tolerated after local session removal', () async {
    await endSession(
      recordAudit: () async {},
      signOut: () async => throw StateError('offline'),
      hasSession: () => false,
    );
  });
  test(
    'a retained session reports failure instead of pretending to log out',
    () async {
      await expectLater(
        endSession(
          recordAudit: () async {},
          signOut: () async => throw StateError('storage failed'),
          hasSession: () => true,
        ),
        throwsStateError,
      );
    },
  );
}
