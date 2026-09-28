import 'package:shared_preferences/shared_preferences.dart';

/// Tracks which pharmacy/account is currently logged in. This is what makes
/// every screen show only that pharmacy's data instead of everyone's.
class SessionService {
  static const _pharmacyIdKey = 'session_pharmacy_id';
  static const _isAdminKey = 'session_is_admin';
  static const _emailKey = 'session_email';
  static const _usernameKey = 'session_username'; 
  static const _fullNameKey = 'session_full_name';
  static const _roleLabelKey = 'session_role_label';
  static const _photoUrlKey = 'session_photo_url';

  static String? _pharmacyId;
  static bool _isAdmin = false;
  static String? _email;
  static String? _username; 
  static String? _fullName;
  static String? _roleLabel;
  static bool _loaded = false;

  static Future<String?> get photoUrl async {
    await _ensureLoaded();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_photoUrlKey);
  }

  static Future<void> setPhotoUrl(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url != null) {
      await prefs.setString(_photoUrlKey, url);
    } else {
      await prefs.remove(_photoUrlKey);
    }
  }

  static Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _pharmacyId = prefs.getString(_pharmacyIdKey);
    _isAdmin = prefs.getBool(_isAdminKey) ?? false;
    _email = prefs.getString(_emailKey);
    _username = prefs.getString(_usernameKey); 
    _fullName = prefs.getString(_fullNameKey);
    _roleLabel = prefs.getString(_roleLabelKey);
    _loaded = true;
  }

  static Future<String?> get pharmacyId async {
    await _ensureLoaded();
    return _pharmacyId;
  }

  static Future<bool> get isAdmin async {
    await _ensureLoaded();
    return _isAdmin;
  }

  static Future<String?> get email async {
    await _ensureLoaded();
    return _email;
  }

  static Future<String?> get username async { 
    await _ensureLoaded();
    return _username;
  }

  static Future<String?> get fullName async {
    await _ensureLoaded();
    return _fullName;
  }

  static Future<String?> get roleLabel async {
    await _ensureLoaded();
    return _roleLabel;
  }

  static Future<bool> get isLoggedIn async {
    await _ensureLoaded();
    return _pharmacyId != null;
  }

  static Future<void> setSession({
    required String pharmacyId,
    required bool isAdmin,
    required String email,
    required String fullName,
    required String roleLabel,
    String? username, 
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pharmacyIdKey, pharmacyId);
    await prefs.setBool(_isAdminKey, isAdmin);
    await prefs.setString(_emailKey, email);
    await prefs.setString(_usernameKey, username ?? email);
    await prefs.setString(_fullNameKey, fullName);
    await prefs.setString(_roleLabelKey, roleLabel);
    _pharmacyId = pharmacyId;
    _isAdmin = isAdmin;
    _email = email;
    _username = username ?? email; 
    _fullName = fullName;
    _roleLabel = roleLabel;
    _loaded = true;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pharmacyIdKey);
    await prefs.remove(_isAdminKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_usernameKey); 
    await prefs.remove(_fullNameKey);
    await prefs.remove(_roleLabelKey);
    _pharmacyId = null;
    _isAdmin = false;
    _email = null;
    _username = null; 
    _fullName = null;
    _roleLabel = null;
    _loaded = false;
  }
}