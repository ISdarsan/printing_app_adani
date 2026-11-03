/// Rules for managing canteens and the staff assigned to them. Pure, so they
/// can be tested without Firebase.
///
/// Business rules (owner decision, 2026-11-03):
///  * Every canteen, including "Main Canteen", can be deleted.
///  * An admin can access every canteen and is therefore assigned to every
///    canteen automatically, including canteens created later. (Access is by
///    role; the canteen stored on an admin's record does not limit them.)
///  * A cashier belongs to exactly one canteen and must never be left without
///    one.
class CanteenInfo {
  final String id;
  final String name;
  const CanteenInfo(this.id, this.name);
}

class StaffMember {
  final String uid;
  final String email;
  final String role; // 'admin' | 'cashier'
  final String canteenId;
  final String canteenName;

  const StaffMember({
    required this.uid,
    required this.email,
    required this.role,
    required this.canteenId,
    this.canteenName = '',
  });

  bool get isAdmin => role == 'admin';

  /// A record without a canteen id has always been shown under 'main'.
  factory StaffMember.fromMap(String uid, Map<String, dynamic> d) {
    final canteen = (d['canteenId'] ?? '').toString().trim();
    return StaffMember(
      uid: uid,
      email: (d['email'] ?? 'No email').toString(),
      role: (d['role'] ?? 'cashier').toString(),
      canteenId: canteen.isEmpty ? 'main' : canteen,
      canteenName: (d['canteenName'] ?? '').toString(),
    );
  }
}

/// Staff shown under one canteen: its cashiers plus EVERY admin (admins reach
/// all canteens). Admins first, then by e-mail.
List<StaffMember> staffForCanteen(
    Iterable<StaffMember> staff, String canteenId) {
  final list =
      staff.where((s) => s.isAdmin || s.canteenId == canteenId).toList();
  list.sort((a, b) {
    if (a.isAdmin != b.isAdmin) return a.isAdmin ? -1 : 1;
    return a.email.toLowerCase().compareTo(b.email.toLowerCase());
  });
  return list;
}

/// What to show as a person's canteen: admins reach all of them.
String staffCanteenLabel(StaffMember s) {
  if (s.isAdmin) return 'All canteens';
  return s.canteenName.isEmpty ? s.canteenId : s.canteenName;
}

class CanteenDeletePlan {
  /// May this canteen be deleted right now?
  final bool allowed;

  /// Where its cashiers are moved (null when there are none to move, or blocked).
  final CanteenInfo? moveTo;
  final List<StaffMember> cashiers;

  /// Plain-language explanation for the confirmation (or the reason it is blocked).
  final String message;

  const CanteenDeletePlan({
    required this.allowed,
    required this.moveTo,
    required this.cashiers,
    required this.message,
  });
}

String _people(List<StaffMember> list) {
  final names = list.map((s) => s.email).take(4).toList();
  final more = list.length - names.length;
  return names.join(', ') + (more > 0 ? ' and $more more' : '');
}

/// Decide what deleting [canteenId] does.
///
///  * Cashiers assigned to it are moved to Main Canteen, but only when Main
///    exists and is not the canteen being deleted (the earlier behaviour).
///  * Otherwise, if any cashier would be left without a canteen, the delete is
///    blocked and the admin is told to move them first.
///  * Admins never block a delete: they keep access to every canteen.
///  * Existing bills, expenses and menu items are never deleted.
CanteenDeletePlan planCanteenDelete({
  required String canteenId,
  required Iterable<CanteenInfo> canteens,
  required Iterable<StaffMember> staff,
}) {
  final canteenList = canteens.toList();
  final target = canteenList.where((c) => c.id == canteenId).firstOrNull;
  final name = target?.name ?? canteenId;
  final cashiers =
      staff.where((s) => !s.isAdmin && s.canteenId == canteenId).toList();
  const keep = 'Admins keep access to every canteen. '
      'Existing bills, expenses and menu items are not deleted.';

  if (cashiers.isEmpty) {
    return CanteenDeletePlan(
      allowed: true,
      moveTo: null,
      cashiers: const [],
      message: 'No cashiers are assigned to "$name". $keep',
    );
  }

  final main = canteenId == 'main'
      ? null
      : canteenList.where((c) => c.id == 'main').firstOrNull;
  if (main != null) {
    final n = cashiers.length;
    return CanteenDeletePlan(
      allowed: true,
      moveTo: main,
      cashiers: cashiers,
      message: '$n cashier${n == 1 ? '' : 's'} (${_people(cashiers)}) will be '
          'moved to "${main.name}". $keep',
    );
  }

  final n = cashiers.length;
  return CanteenDeletePlan(
    allowed: false,
    moveTo: null,
    cashiers: cashiers,
    message: '$n cashier${n == 1 ? ' is' : 's are'} still assigned to "$name" '
        '(${_people(cashiers)}). Move ${n == 1 ? 'them' : 'them'} to another '
        'canteen first (Staff tab, then the menu on their row, then '
        '"Reassign Canteen"), then delete this one.',
  );
}

/// A dropdown must be given a value that is one of its items. Returns
/// [current] when it is still one of [canteens], otherwise the first canteen,
/// otherwise null (no canteens exist).
CanteenInfo? validCanteenSelection(
    String? current, Iterable<CanteenInfo> canteens) {
  final list = canteens.toList();
  if (list.isEmpty) return null;
  return list.where((c) => c.id == current).firstOrNull ?? list.first;
}
