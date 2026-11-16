/// Roles permitted in the GeoGrave field-access build.
///
/// Keep this client-side check aligned with the database RLS policies. It is
/// deliberately allow-list based so newly added privileged roles are denied
/// until they have been explicitly approved for this build.
const geoGraveAllowedRoles = <String>{'visitor', 'lot_owner', 'gate_officer'};

bool isGeoGraveAllowedRole(String? role) =>
    geoGraveAllowedRoles.contains(role?.trim().toLowerCase());
