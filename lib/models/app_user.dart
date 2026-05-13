enum UserRole { visitor, lotOwner, admin, gateOfficer }

class AppUser {
  const AppUser({
    required this.id,
    required this.displayName,
    required this.role,
  });

  final String id;
  final String displayName;
  final UserRole role;
}

