/// Returns the canonical role key used by navigation and authorization.
///
/// Older database rows used several names for Gate Officers. Keeping this
/// normalization in one place prevents the login screen and routers from
/// disagreeing about an otherwise valid account.
String normalizeAppRole(Object? value) {
  final role = value?.toString().trim().toLowerCase();
  return switch (role) {
    'guard' || 'gate officer' || 'gate-officer' => 'gate_officer',
    _ => role ?? '',
  };
}

/// Roles permitted in the GeoGrave field-access Android build.
///
/// Use an allow list so a newly added privileged role cannot access the app
/// until it has been explicitly approved.
bool isGeoGraveAllowedRole(Object? value) => switch (normalizeAppRole(value)) {
  'visitor' || 'lot_owner' || 'gate_officer' => true,
  _ => false,
};

String? appHomeForRole(Object? value) => switch (normalizeAppRole(value)) {
  'gate_officer' => '/gate-officer',
  'lot_owner' => '/lot-owner',
  'visitor' => '/visitor',
  _ => null,
};

String appRoleName(Object? value) => switch (normalizeAppRole(value)) {
  'admin' => 'administrators',
  'gate_officer' => 'gate officers',
  'lot_owner' => 'lot owners',
  _ => 'visitors',
};
