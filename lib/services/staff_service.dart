import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import 'session_service.dart';
import 'account_service.dart';

class StaffMember {
  final int id;
  final String fullName;
  final String email;
  final String role;
  final String? photoUrl;

  const StaffMember({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    this.photoUrl,
  });

factory StaffMember.fromMap(Map<String, dynamic> map, {String? photoUrl}) {
  return StaffMember(
    id: map['id'],
    fullName: map['full_name'] ?? '',
    email: map['email'] ?? '',
    role: map['role'] ?? '',
    photoUrl: photoUrl,
  );
}
}

/// Centralizes what each role is allowed to do, so screens check one
/// permissions object instead of hardcoding `role == 'admin'` string
/// comparisons in multiple places (inventory screen, staff management
/// screen, export button, etc.). If you ever add a third role, this is
/// the only place that needs to change.
///
/// Current split:
///  - Admin: full control — invite/manage staff, add/edit/delete inventory,
///    export data.
///  - Staff: can add inventory (scan or manual) and adjust quantity
///    (restock/dispense), but cannot edit core item details (name/expiry/
///    category) or delete items, and cannot invite/manage staff. Export
///    is allowed for both roles since it's read-only.
class StaffPermissions {
  final bool canInviteStaff;
  final bool canManageStaff; // edit/remove existing staff accounts
  final bool canAddInventory; // scan or manual add
  final bool canAdjustQuantity; // restock/dispense on an existing item
  final bool canEditInventory; // full edit: name, expiry, category
  final bool canDeleteInventory;
  final bool canExportData;

  const StaffPermissions({
    required this.canInviteStaff,
    required this.canManageStaff,
    required this.canAddInventory,
    required this.canAdjustQuantity,
    required this.canEditInventory,
    required this.canDeleteInventory,
    required this.canExportData,
  });

  factory StaffPermissions.forRole(String role) {
    final isAdmin = role.trim().toLowerCase() == 'admin';
    return StaffPermissions(
      canInviteStaff: isAdmin,
      canManageStaff: isAdmin,
      canAddInventory: true,
      canAdjustQuantity: true,
      canEditInventory: isAdmin,
      canDeleteInventory: isAdmin,
      canExportData: true,
    );
  }
}

class StaffService {
  /// Returns the permission set for the currently logged-in user.
  ///
  /// ASSUMPTION: this reads `SessionService.role`. I don't have your
  /// session_service.dart, so if the current user's role is stored under
  /// a different name there (or only available on the StaffMember row
  /// fetched at login), swap the line below to match — everything else
  /// here (StaffPermissions.forRole) stays the same either way.
  /// Returns the permission set for the currently logged-in user.
  /// Derives the role from the `staff` table (by current user email),
  /// so it doesn't rely on a SessionService.role getter existing.
  static Future<StaffPermissions> currentPermissions() async {
    try {
      final email = SupabaseService.client.auth.currentUser?.email ??
          await SessionService.email;
      if (email == null || email.isEmpty) {
        return StaffPermissions.forRole('staff');
      }

      final row = await SupabaseService.client
          .from('staff')
          .select('role')
          .eq('email', email)
          .maybeSingle();

      final role = row?['role']?.toString() ?? 'staff';
      return StaffPermissions.forRole(role);
    } catch (e) {
      // Fail closed: treat as staff if we can't determine the role.
      return StaffPermissions.forRole('staff');
    }
  }

static Future<List<StaffMember>> fetchStaff() async {
  final pharmacyId = await SessionService.pharmacyId;
  if (pharmacyId == null) return [];
  final response = await SupabaseService.client
      .from('staff')
      .select()
      .eq('pharmacy_id', pharmacyId)
      .order('created_at', ascending: false);

  final rows = List<Map<String, dynamic>>.from(response);

  // Fetch each staff member's photo in parallel, not one-by-one.
  final staffList = await Future.wait(rows.map((row) async {
    final email = row['email'] ?? '';
    String? photoUrl;
    try {
      photoUrl = await AccountService.getPhotoUrl(email);
    } catch (e) {
      photoUrl = null; // fall back to initials if lookup fails
    }
    return StaffMember.fromMap(row, photoUrl: photoUrl);
  }));

  return staffList;
}

  /// Invites a new staff member by email via a Supabase Edge Function.
  /// The admin only supplies email + role — no name, username, or
  /// password is collected here. The staff member fills in their own
  /// name/username and sets their own password when they open the
  /// invite link, which is caught by the app's deep-link handler in
  /// main.dart and routed to CompleteInviteScreen. Runs entirely
  /// server-side, so it doesn't touch or disturb the admin's own
  /// active session.
  static Future<void> addStaff({
    required String email,
    required String role,
  }) async {
    final pharmacyId = await SessionService.pharmacyId;
    if (pharmacyId == null) {
      throw Exception('No active pharmacy session found.');
    }

    final response = await SupabaseService.client.functions.invoke(
      'invite-staff',
      body: {
        'email': email,
        'role': role,
        'pharmacyId': pharmacyId,
      },
    );

    if (response.status != 200) {
      final data = response.data;
      final message = (data is Map && data['error'] != null)
          ? data['error'].toString()
          : 'Failed to invite staff member. Please try again.';
      throw Exception(message);
    }
  }

  static Future<void> updateStaff({
    required int id,
    required String fullName,
    required String email,
    required String role,
  }) async {
    await SupabaseService.client.from('staff').update({
      'full_name': fullName,
      'email': email,
      'role': role,
    }).eq('id', id);
  }

  /// Deletes both the staff table row AND their underlying Supabase Auth
  /// account (via a server-side Edge Function), so their email becomes
  /// available to invite again in the future. Deleting only the table
  /// row (the old behavior) left the email permanently stuck as
  /// "already registered" for any future invite attempt.
  static Future<void> deleteStaff(int id, {required String email}) async {
    final response = await SupabaseService.client.functions.invoke(
      'delete-staff',
      body: {
        'staffId': id,
        'email': email,
      },
    );

    if (response.status != 200) {
      final data = response.data;
      final message = (data is Map && data['error'] != null)
          ? data['error'].toString()
          : 'Failed to remove staff member. Please try again.';
      throw Exception(message);
    }
  }
}