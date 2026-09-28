import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import 'session_service.dart';

class AuthService {

  /// ── Real Supabase Auth signup ──────────────────────────────────────
  /// Creates a real `auth.users` account, then links it to a new `admins`
  /// row via that account's uid. RLS policies that check `auth.uid()` will
  /// now work correctly for anyone who signs up through this method.
  static Future<String> signUpPharmacy({
    required String pharmacyName,
    required String address,
    required String type,
    required String fullName,
    required String username,
    required String email,
    required String password,
  }) async {
    try {
      // Check if username exists
      final existingUsername = await SupabaseService.client
          .from('admins')
          .select()
          .eq('username', username)
          .maybeSingle();
      if (existingUsername != null) {
        throw Exception(
            'This username is already taken. Please choose a different username.');
      }

      // Check if email exists
      final existingEmail = await SupabaseService.client
          .from('admins')
          .select()
          .eq('email', email)
          .maybeSingle();
      if (existingEmail != null) {
        throw Exception(
            'This email is already registered. Please use a different email address.');
      }

      // Check if pharmacy name exists
      final existingPharmacy = await SupabaseService.client
          .from('pharmacies')
          .select()
          .eq('name', pharmacyName)
          .maybeSingle();
      if (existingPharmacy != null) {
        throw Exception(
            'A pharmacy with this name already exists. Please use a different name.');
      }

      // ── Create the real Supabase Auth account first ──────────────────────
      // This is what makes auth.uid() / auth.email() work in RLS policies.
      final authResponse = await SupabaseService.client.auth.signUp(
        email: email,
        password: password,
      );

      final authUser = authResponse.user;
      if (authUser == null) {
        throw Exception('Could not create account. Please try again.');
      }

      // Create pharmacy
      final pharmacyRow = await SupabaseService.client
          .from('pharmacies')
          .insert({
            'name': pharmacyName,
            'address': address,
            'type': type,
            'email': email,
          })
          .select()
          .single();

      final pharmacyId = pharmacyRow['id'] as String;

      // Create admin profile row, keyed to the real auth user id.
      await SupabaseService.client.from('admins').insert({
        'id': authUser.id, // <-- links this row to auth.uid()
        'pharmacy_id': pharmacyId,
        'full_name': fullName,
        'username': username,
        'email': email,
        'role_label': 'Manager • $pharmacyName',
      });

      return pharmacyId;
    } on AuthException catch (e) {
      // Supabase Auth-specific errors (weak password, invalid email, etc.)
      throw Exception(e.message);
    } catch (e) {
      final errorMessage = e.toString();
      if (errorMessage.contains('duplicate key value violates unique constraint')) {
        if (errorMessage.contains('email')) {
          throw Exception('This email is already registered. Please use a different email address.');
        } else if (errorMessage.contains('username')) {
          throw Exception('This username is already taken. Please choose a different username.');
        } else if (errorMessage.contains('pharmacy_name') || errorMessage.contains('name')) {
          throw Exception('A pharmacy with this name already exists. Please use a different name.');
        } else {
          throw Exception('Some information is already registered. Please check your credentials.');
        }
      }
      print('Signup error: $e');
      rethrow;
    }
  }

  /// ── Verify OTP (signup / email verification) ────────────────────────
  static Future<void> verifyEmailOTP({
    required String email,
    required String token,
  }) async {
    try {
      final response = await SupabaseService.client.auth.verifyOTP(
        type: OtpType.signup,
        email: email,
        token: token,
      );

      if (response.user == null) {
        throw Exception('Verification failed. Please try again.');
      }

      print('Email verified successfully for: $email');
    } on AuthException catch (e) {
      if (e.message.contains('Invalid token')) {
        throw Exception('Invalid verification code. Please check and try again.');
      } else if (e.message.contains('Expired')) {
        throw Exception('This verification code has expired. Please request a new one.');
      } else {
        throw Exception('Verification failed: ${e.message}');
      }
    } catch (e) {
      throw Exception('Failed to verify code: ${e.toString()}');
    }
  }

  /// ── Resend OTP (signup / email verification) ────────────────────────
  static Future<void> resendVerificationCode({
    required String email,
  }) async {
    try {
      await SupabaseService.client.auth.signUp(
        email: email,
        password: 'dummy_password_123', // Not used since user already exists
      );

      print('Verification code resent to: $email');
    } on AuthException catch (e) {
      throw Exception('Failed to resend code: ${e.message}');
    } catch (e) {
      throw Exception('Failed to resend code: ${e.toString()}');
    }
  }

  /// ── Check if user's email is verified ────────────────────────────────
  static Future<bool> isUserVerified() async {
    try {
      final user = SupabaseService.client.auth.currentUser;
      return user?.emailConfirmedAt != null;
    } catch (e) {
      print('Error checking verification status: $e');
      return false;
    }
  }

  /// ── Get current user's email ──────────────────────────────────────────
  static String? getCurrentUserEmail() {
    try {
      return SupabaseService.client.auth.currentUser?.email;
    } catch (e) {
      return null;
    }
  }

  /// ── Check if user is authenticated ────────────────────────────────────
  static bool isAuthenticated() {
    try {
      return SupabaseService.client.auth.currentUser != null;
    } catch (e) {
      return false;
    }
  }

  /// ── Real Supabase Auth login (bcrypt fallback removed) ─────────
  /// Every account must now have a matching auth.users entry — created
  /// either via signUpPharmacy() or migrated manually. Accounts without
  /// one will simply fail to log in; there is no silent fallback.
  static Future<bool> login(String username, String password) async {
    try {
      print('🔍 Attempting to log in with username: $username');

      final adminRow = await SupabaseService.client
          .from('admins')
          .select()
          .eq('username', username)
          .maybeSingle();

      if (adminRow != null) {
        return await _loginProfileRow(
          row: adminRow,
          table: 'admins',
          username: username,
          password: password,
          isAdmin: true,
        );
      }

      final staffRow = await SupabaseService.client
          .from('staff')
          .select()
          .eq('username', username)
          .maybeSingle();

      if (staffRow != null && staffRow['pharmacy_id'] != null) {
        return await _loginProfileRow(
          row: staffRow,
          table: 'staff',
          username: username,
          password: password,
          isAdmin: false,
        );
      }

      print('No user found with username: $username');
      return false;
    } catch (e) {
      print('CRITICAL EXCEPTION IN LOGIN: $e');
      return false;
    }
  }

  /// Sends a password reset OTP to the user's email.
  static Future<void> sendPasswordResetOTP({required String email}) async {
    try {
      await SupabaseService.client.auth.resetPasswordForEmail(email);
      print('Password reset OTP sent to: $email');
    } catch (e) {
      throw Exception('Failed to send reset code: ${e.toString()}');
    }
  }

  /// Checks whether [email] belongs to a registered admin or staff account.
  /// Used before sending a password reset OTP, so the app can tell the
  /// user plainly when the email isn't registered instead of silently
  /// pretending a code was sent.
  static Future<bool> emailExists(String email) async {
    final adminRow = await SupabaseService.client
        .from('admins')
        .select('id')
        .eq('email', email)
        .maybeSingle();
    if (adminRow != null) return true;

    final staffRow = await SupabaseService.client
        .from('staff')
        .select('id')
        .eq('email', email)
        .maybeSingle();
    return staffRow != null;
  }

  /// Verifies the recovery OTP ONLY — does not touch the password.
  /// On success, Supabase has an authenticated session for this user,
  /// so SupabaseService.updatePassword() can be called afterwards
  /// (on a separate screen) without needing the OTP again.
  static Future<void> verifyPasswordResetOtp({
    required String email,
    required String token,
  }) async {
    try {
      final response = await SupabaseService.client.auth.verifyOTP(
        type: OtpType.recovery,
        email: email,
        token: token,
      );

      print('OTP verified — session user: ${response.user?.email}, session exists: ${response.session != null}');

      if (response.user == null) {
        throw Exception('Invalid or expired reset code.');
      }
    } on AuthException catch (e) {
      if (e.message.contains('Invalid token')) {
        throw Exception('Invalid verification code. Please check and try again.');
      } else if (e.message.contains('Expired')) {
        throw Exception('This verification code has expired. Please request a new one.');
      } else {
        throw Exception('Verification failed: ${e.message}');
      }
    } catch (e) {
      throw Exception('Failed to verify code: ${e.toString()}');
    }
  }


   static Future<String?> getAccountLabelForEmail(String email) async {
    final adminRow = await SupabaseService.client
        .from('admins')
        .select('username, full_name')
        .eq('email', email)
        .maybeSingle();
    if (adminRow != null) {
      return adminRow['username'] ?? adminRow['full_name'] ?? email;
    }

    final staffRow = await SupabaseService.client
        .from('staff')
        .select('username, full_name')
        .eq('email', email)
        .maybeSingle();
    if (staffRow != null) {
      return staffRow['username'] ?? staffRow['full_name'] ?? email;
    }

    return null;
  }

    /// Syncs [SessionService] to whichever account is CURRENTLY authenticated
  /// in Supabase (by auth.currentUser's email) — without requiring a
  /// username/password. Needed after any flow where Supabase already has
  /// an authenticated session before SessionService knows about it: staff
  /// invite links and forgot-password resets both land here, since both
  /// authenticate via a deep-link/OTP token rather than AuthService.login().
  ///
  /// Without this, SessionService keeps showing whichever account was last
  /// manually logged in on this device (e.g. an admin), even after a
  /// completely different account (e.g. a newly invited staff member)
  /// authenticates via deep link and sets their password.
  static Future<bool> syncSessionForCurrentUser() async {
    final email = SupabaseService.client.auth.currentUser?.email;
    if (email == null) {
      print('syncSessionForCurrentUser: no authenticated Supabase user.');
      return false;
    }

    final adminRow = await SupabaseService.client
        .from('admins')
        .select()
        .eq('email', email)
        .maybeSingle();

    if (adminRow != null) {
      await SessionService.setSession(
        pharmacyId: adminRow['pharmacy_id'],
        isAdmin: true,
        email: email,
        fullName: adminRow['full_name'] ?? '',
        roleLabel: adminRow['role_label'] ?? '',
        username: adminRow['username'],
      );
      print('Session synced to admin: $email');
      return true;
    }

    final staffRow = await SupabaseService.client
        .from('staff')
        .select()
        .eq('email', email)
        .maybeSingle();

    if (staffRow != null && staffRow['pharmacy_id'] != null) {
      await SessionService.setSession(
        pharmacyId: staffRow['pharmacy_id'],
        isAdmin: false,
        email: email,
        fullName: staffRow['full_name'] ?? '',
        roleLabel: staffRow['role_label'] ?? staffRow['role'] ?? 'Staff',
        username: staffRow['username'],
      );
      print('Session synced to staff: $email');
      return true;
    }

    print('syncSessionForCurrentUser: no admins/staff row found for $email');
    return false;
  } 

  static Future<bool> _loginProfileRow({
    required Map<String, dynamic> row,
    required String table,
    required String username,
    required String password,
    required bool isAdmin,
  }) async {
    final email = row['email'] as String?;
    if (email == null || email.isEmpty) {
      print('No email on file for $table/$username — cannot authenticate.');
      return false;
    }

    try {
      final res = await SupabaseService.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (res.user == null) {
        print('Invalid password for $table/$username');
        return false;
      }

      await SessionService.setSession(
        pharmacyId: row['pharmacy_id'],
        isAdmin: isAdmin,
        email: email,
        fullName: row['full_name'] ?? '',
        roleLabel: row['role_label'] ?? row['role'] ?? (isAdmin ? '' : 'Staff'),
        username: username,
      );
      print('Login successful via Supabase Auth ($table)');
      return true;
    } on AuthException catch (e) {
      print('Auth error: ${e.message}');
      return false;
    }
  }
}