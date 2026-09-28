import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import 'session_service.dart';

class PasswordService {
  /// Verifies the user's CURRENT password by attempting a real Supabase
  /// Auth sign-in with it. This replaces the old bcrypt hash comparison —
  /// there is no local hash to check anymore, Supabase is the source of
  /// truth for every account's password.
  static Future<bool> verifyCurrentPassword(String password) async {
    try {
      final email = await SessionService.email;

      if (email == null || email.isEmpty) {
        print('❌ No email in session');
        return false;
      }

      final res = await SupabaseService.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      return res.user != null;
    } on AuthException catch (e) {
      print('❌ verifyCurrentPassword - Auth error: ${e.message}');
      return false;
    } catch (e) {
      print('❌ verifyCurrentPassword - Exception: $e');
      return false;
    }
  }

  /// Sets a new password via Supabase Auth. Requires an active session
  /// (the user must already be signed in — e.g. via a prior
  /// verifyCurrentPassword() call or an existing logged-in session).
  static Future<void> setPassword(String newPassword) async {
    try {
      final username = await SessionService.username;

      if (username == null || username.isEmpty) {
        throw Exception('No active session found.');
      }

      await SupabaseService.client.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      print('✅ Password updated successfully for $username');
    } on AuthException catch (e) {
      print('❌ setPassword - Auth error: ${e.message}');
      throw Exception(e.message);
    } catch (e) {
      print('❌ setPassword - Exception: $e');
      rethrow;
    }
  }
}