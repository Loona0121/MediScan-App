import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_service.dart';
import 'session_service.dart';

class AccountService {
  static String _keyFor(String field, String email) =>
      'account_${email}_$field';

  static Future<Map<String, String?>> getAccount({required String email}) async {
    final prefs = await SharedPreferences.getInstance();
    
    String? displayName = prefs.getString(_keyFor('display_name', email));
    String? photoPath = prefs.getString(_keyFor('photo_path', email));
    
    print('getAccount - Local displayName: $displayName');
    print('getAccount - Local photoPath: $photoPath');
    
    // If no local data, try to get from Supabase
    if (displayName == null || photoPath == null) {
      try {
        final profile = await _getProfileFromSupabase(email);
        print('getAccount - Supabase profile: $profile');
        if (profile != null) {
          displayName = profile['full_name'] ?? displayName;
          photoPath = profile['photo_url'] ?? photoPath;
          
          if (displayName != null && displayName.isNotEmpty) {
            await prefs.setString(_keyFor('display_name', email), displayName);
          }
          if (photoPath != null && photoPath.isNotEmpty) {
            await prefs.setString(_keyFor('photo_path', email), photoPath);
          }
        }
      } catch (e) {
        print('getAccount - Supabase error: $e');
      }
    }
    
    return {
      'displayName': displayName,
      'photoPath': photoPath,
    };
  }

  static Future<Map<String, dynamic>?> _getProfileFromSupabase(String email) async {
    try {
      final pharmacyId = await SessionService.pharmacyId;
      print('_getProfileFromSupabase - pharmacyId: $pharmacyId');
      if (pharmacyId == null) return null;

      // Try admins table first
      final adminResponse = await SupabaseService.client
          .from('admins')
          .select('id, email, full_name, photo_url, username')
          .eq('pharmacy_id', pharmacyId)
          .eq('email', email)
          .maybeSingle();

      if (adminResponse != null) {
        print('_getProfileFromSupabase - found in admins: $adminResponse');
        return {...adminResponse, 'role': 'admin'};
      }

      // Fall back to staff table
      final staffResponse = await SupabaseService.client
          .from('staff')
          .select('id, email, full_name, photo_url, username')
          .eq('pharmacy_id', pharmacyId)
          .eq('email', email)
          .maybeSingle();

      if (staffResponse != null) {
        print('_getProfileFromSupabase - found in staff: $staffResponse');
        return {...staffResponse, 'role': 'staff'};
      }

      return null;
    } catch (e) {
      print('_getProfileFromSupabase - error: $e');
      return null;
    }
  }

  /// Returns true if [username] already belongs to a DIFFERENT account
  /// (any account other than [excludeEmail]) in either admins or staff.
  /// Mirrors the uniqueness check AuthService.signUpPharmacy() does.
  static Future<bool> isUsernameTaken(
    String username, {
    required String excludeEmail,
  }) async {
    final admin = await SupabaseService.client
        .from('admins')
        .select('email')
        .eq('username', username)
        .maybeSingle();
    if (admin != null && admin['email'] != excludeEmail) return true;

    final staff = await SupabaseService.client
        .from('staff')
        .select('email')
        .eq('username', username)
        .maybeSingle();
    if (staff != null && staff['email'] != excludeEmail) return true;

    return false;
  }

  static Future<void> saveAccount({
    required String email,
    String? displayName,
    String? roleLabel,
    String? fullName,
    String? photoPath,
    String? username,
  }) async {
    print('saveAccount - Saving for email: $email');
    print('saveAccount - displayName: $displayName');
    print('saveAccount - photoPath: $photoPath');
    print('saveAccount - username: $username');

    // Validate username uniqueness BEFORE writing anything, local or
    // remote, so a rejected username never gets cached.
    String? trimmedUsername;
    if (username != null && username.trim().isNotEmpty) {
      trimmedUsername = username.trim();
      final taken = await isUsernameTaken(trimmedUsername, excludeEmail: email);
      if (taken) {
        throw Exception(
            'This username is already taken. Please choose a different username.');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    
    if (displayName != null) {
      await prefs.setString(_keyFor('display_name', email), displayName);
      print('saveAccount - Saved displayName locally');
    }
    if (photoPath != null) {
      await prefs.setString(_keyFor('photo_path', email), photoPath);
      print('saveAccount - Saved photoPath locally');
    }
    if (trimmedUsername != null) {
      await prefs.setString(_keyFor('username', email), trimmedUsername);
      print('saveAccount - Saved username locally');
    }
    
    try {
      final pharmacyId = await SessionService.pharmacyId;
      print('saveAccount - pharmacyId: $pharmacyId');
      if (pharmacyId == null) throw Exception('Not logged in');

      final Map<String, dynamic> updateData = {};
      if (displayName != null) {
        updateData['full_name'] = displayName;
      }
      if (photoPath != null) {
        updateData['photo_url'] = photoPath;
      }
      if (trimmedUsername != null) {
        updateData['username'] = trimmedUsername;
      }

      print('saveAccount - updateData: $updateData');

      if (updateData.isNotEmpty) {
        // Try to update admins first
        final adminResult = await SupabaseService.client
            .from('admins')
            .update(updateData)
            .eq('pharmacy_id', pharmacyId)
            .eq('email', email);
        print('saveAccount - Admin update result: $adminResult');
        
        // If no admin found, update staff
        final staffResult = await SupabaseService.client
            .from('staff')
            .update(updateData)
            .eq('pharmacy_id', pharmacyId)
            .eq('email', email);
        print('saveAccount - Staff update result: $staffResult');
      }
    } catch (e) {
      print('saveAccount - Supabase error: $e');
      rethrow;
    }
  }

  static Future<String?> getPhotoUrl(String email) async {
    try {
      print('getPhotoUrl - Getting photo for: $email');
      
      // Try to get from local cache first
      final prefs = await SharedPreferences.getInstance();
      final cachedPhoto = prefs.getString(_keyFor('photo_path', email));
      if (cachedPhoto != null && cachedPhoto.isNotEmpty) {
        print('getPhotoUrl - Using cached photo: $cachedPhoto');
        return cachedPhoto;
      }
      
      // If not in cache, get from Supabase
      final profile = await _getProfileFromSupabase(email);
      print('getPhotoUrl - Profile from DB: $profile');
      
      final photoUrl = profile?['photo_url'] as String?;
      print('getPhotoUrl - photoUrl from DB: $photoUrl');
      
      // Cache the photo URL if found
      if (photoUrl != null && photoUrl.isNotEmpty) {
        await prefs.setString(_keyFor('photo_path', email), photoUrl);
        print('getPhotoUrl - Cached photo URL: $photoUrl');
      }
      
      return photoUrl;
    } catch (e) {
      print('getPhotoUrl - error: $e');
      return null;
    }
  }

  static Future<String?> getFullName(String email) async {
    try {
      print('getFullName - Getting name for: $email');
      
      // Try to get from local cache first
      final prefs = await SharedPreferences.getInstance();
      final cachedName = prefs.getString(_keyFor('display_name', email));
      if (cachedName != null && cachedName.isNotEmpty) {
        print('getFullName - Using cached name: $cachedName');
        return cachedName;
      }
      
      final profile = await _getProfileFromSupabase(email);
      print('getFullName - Profile from DB: $profile');
      
      final fullName = profile?['full_name'] as String?;
      print('getFullName - fullName from DB: $fullName');
      
      // Cache the full name if found
      if (fullName != null && fullName.isNotEmpty) {
        await prefs.setString(_keyFor('display_name', email), fullName);
        print('getFullName - Cached full name: $fullName');
      }
      
      return fullName;
    } catch (e) {
      print('getFullName - error: $e');
      return null;
    }
  }

  static Future<String?> getUsername(String email) async {
    try {
      print('getUsername - Getting username for: $email');

      final prefs = await SharedPreferences.getInstance();
      final cachedUsername = prefs.getString(_keyFor('username', email));
      if (cachedUsername != null && cachedUsername.isNotEmpty) {
        print('getUsername - Using cached username: $cachedUsername');
        return cachedUsername;
      }

      final profile = await _getProfileFromSupabase(email);
      print('getUsername - Profile from DB: $profile');

      final username = profile?['username'] as String?;
      print('getUsername - username from DB: $username');

      if (username != null && username.isNotEmpty) {
        await prefs.setString(_keyFor('username', email), username);
        print('getUsername - Cached username: $username');
      }

      return username;
    } catch (e) {
      print('getUsername - error: $e');
      return null;
    }
  }

  // ===== ADDED: role lookup for RBAC. Deliberately NOT cached to
  // SharedPreferences like the display/photo/username helpers above —
  // role is security-relevant, and a stale local cache could keep
  // showing admin-only UI to someone who was just demoted. Always hits
  // Supabase fresh.
  static Future<String?> getRole(String email) async {
    try {
      final profile = await _getProfileFromSupabase(email);
      return profile?['role'] as String?;
    } catch (e) {
      print('getRole - error: $e');
      return null;
    }
  }

  static Future<bool> isAdmin(String email) async {
    final role = await getRole(email);
    return role == 'admin';
  }

  static Future<void> clearLocalCache(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyFor('display_name', email));
    await prefs.remove(_keyFor('photo_path', email));
    await prefs.remove(_keyFor('username', email));
  }

  static Future<void> refreshFromSupabase(String email) async {
    try {
      print('refreshFromSupabase - Refreshing for: $email');
      final profile = await _getProfileFromSupabase(email);
      print('refreshFromSupabase - Profile: $profile');
      
      if (profile != null) {
        final prefs = await SharedPreferences.getInstance();
        
        final name = profile['full_name'] as String?;
        final photo = profile['photo_url'] as String?;
        final username = profile['username'] as String?;
        
        if (name != null && name.isNotEmpty) {
          await prefs.setString(_keyFor('display_name', email), name);
          print('refreshFromSupabase - Updated cached name: $name');
        }
        if (photo != null && photo.isNotEmpty) {
          await prefs.setString(_keyFor('photo_path', email), photo);
          print('refreshFromSupabase - Updated cached photo: $photo');
        }
        if (username != null && username.isNotEmpty) {
          await prefs.setString(_keyFor('username', email), username);
          print('refreshFromSupabase - Updated cached username: $username');
        }
      }
    } catch (e) {
      print('refreshFromSupabase - error: $e');
    }
  }
} 