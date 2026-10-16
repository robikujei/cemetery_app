import 'dart:async';

/// Audit failures must not prevent logout. A remote sign-out failure is safe
/// to tolerate only after the auth client has cleared its local session.
Future<void> endSession({
  required Future<void> Function() recordAudit,
  required Future<void> Function() signOut,
  required bool Function() hasSession,
  Duration auditTimeout = const Duration(seconds: 2),
  Duration signOutTimeout = const Duration(seconds: 5),
}) async {
  try {
    await recordAudit().timeout(auditTimeout);
  } catch (_) {
    // Best effort: authentication cleanup takes priority over audit availability.
  }
  try {
    await signOut().timeout(signOutTimeout);
  } catch (_) {
    if (hasSession()) rethrow;
  }
  if (hasSession()) {
    throw StateError('The local session could not be cleared.');
  }
}
