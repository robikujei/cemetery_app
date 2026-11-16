enum AppAudience { admin, users }

const _appAudienceValue = String.fromEnvironment(
  'APP_AUDIENCE',
  defaultValue: 'users',
);

const appAudience = _appAudienceValue == 'admin'
    ? AppAudience.admin
    : AppAudience.users;

bool get isAdminApp => appAudience == AppAudience.admin;

bool isRoleAllowedForAudience(String? role, AppAudience audience) {
  final normalizedRole = role?.trim().toLowerCase();
  return switch (audience) {
    AppAudience.admin => normalizedRole == 'admin',
    AppAudience.users => const {
      'visitor',
      'lot_owner',
      'gate_officer',
    }.contains(normalizedRole),
  };
}

bool isRoleAllowedInThisApp(String? role) =>
    isRoleAllowedForAudience(role, appAudience);

String get audienceAccessMessage => isAdminApp
    ? 'This link is reserved for administrator accounts.'
    : 'This link is for visitors, lot owners, and gate officers. Administrators must use the admin link.';
