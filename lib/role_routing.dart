/// Authorization decision taken after sign-in, extracted from RoleSplashPage
/// so it can be unit-tested. This is the ONLY place that maps a staff document
/// to a destination; nothing navigates to a dashboard without going through it.
enum RoleOutcome { admin, cashier, deactivated, notFound, unknownRole, error }

class RoleDecision {
  final RoleOutcome outcome;

  /// Named route to open when [allowed]; null for every denial.
  final String? route;
  final String title;
  final String subtitle;

  /// Extra line shown under a denial (never contains credentials).
  final String detail;
  const RoleDecision(this.outcome, this.route, this.title, this.subtitle,
      [this.detail = '']);

  bool get allowed => route != null;

  /// How long a denial stays on screen before the user is signed out, so the
  /// message can be read. Allowed users are never delayed.
  Duration get denialHold => const Duration(milliseconds: 2500);
}

/// [docExists] / [data] describe `canteenStaff/{uid}` read from the SERVER.
/// A read [error] (offline, permission) is a denial, never a fallback to
/// another role or to the 'main' canteen.
///
/// `active` follows firestore.rules: a missing field counts as active, only an
/// explicit `false` deactivates.
RoleDecision decideRole({
  required bool docExists,
  Map<String, dynamic>? data,
  Object? error,
}) {
  if (error != null) {
    return RoleDecision(RoleOutcome.error, null, 'Connection Error',
        'Check your internet connection.', error.toString());
  }
  if (!docExists) {
    return const RoleDecision(RoleOutcome.notFound, null, 'Access Denied',
        'User role not found.', 'Contact your administrator.');
  }
  if (data?['active'] == false) {
    return const RoleDecision(RoleOutcome.deactivated, null, 'Access Denied',
        'This account has been deactivated.', 'Contact your administrator.');
  }
  switch ((data?['role'] ?? '').toString()) {
    case 'admin':
      return const RoleDecision(RoleOutcome.admin, '/admin_dashboard',
          'Welcome, Admin', 'Loading your dashboard...');
    case 'cashier':
      return const RoleDecision(RoleOutcome.cashier, '/billing_dashboard',
          'Welcome, Cashier', 'Loading your dashboard...');
    default:
      // Unknown or missing role: the old code also signed these users out.
      return const RoleDecision(RoleOutcome.unknownRole, null, 'Access Denied',
          'User role not found.', 'Contact your administrator.');
  }
}
