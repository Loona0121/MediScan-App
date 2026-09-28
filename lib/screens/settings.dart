import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/web_shell.dart';
import '../widgets/top_banner.dart';
import '../services/staff_service.dart';
import '../services/account_service.dart';
import '../services/supabase_service.dart';
import '../services/session_service.dart';
import '../services/pharmacy_service.dart';
import '../services/password_service.dart';
import 'login.dart';
import 'change_password.dart';
import 'pharmacy_details.dart';
import 'staff_management.dart';
import 'support.dart';
import 'edit_profile.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/app_palette.dart';
import '../services/theme_service.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/push_notification_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  // Set by WebShell's sidebar before navigating here, so the Profile /
  // Pharmacy / Security sub-item that was tapped opens directly instead
  // of always landing on the Profile tab. Consumed (reset to null) in
  // initState so it doesn't stick on a later, unrelated navigation.
  static int? initialTab;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsOn = true;
  int _staffCount = 0;
  bool _isLoadingAccount = true;

  String _displayName = '';
  String _roleLabel = '';
  String _fullName = '';
  String _email = '';
  String _username = '';
  String? _photoPath;
  Uint8List? _photoBytes;
  bool _isUploadingPhoto = false;
  bool _isAdmin = false;

  int _webSelectedTab = 0;

  final _webNameCtrl = TextEditingController();
  final _webUsernameCtrl = TextEditingController();
  final _webEmailCtrl = TextEditingController();
  final _webPharmacyNameCtrl = TextEditingController();
  final _webAddressCtrl = TextEditingController();
  final _webPhoneCtrl = TextEditingController();
  bool _webIsSavingProfile = false;
  bool _webIsSavingPharmacy = false;

  final _currentPasswordCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSavingPassword = false;

  @override
  void initState() {
    super.initState();
    final pendingTab = SettingsScreen.initialTab;
    if (pendingTab != null) {
      _webSelectedTab = pendingTab;
      SettingsScreen.initialTab = null;
    }
    _loadAccount();
    _loadNotificationsPref();
  }

  Future<void> _loadNotificationsPref() async {
    final enabled = await PushNotificationService.isEnabled();
    if (!mounted) return;
    setState(() => _notificationsOn = enabled);
  }

  Future<void> _toggleNotifications() async {
    final newValue = !_notificationsOn;
    setState(() => _notificationsOn = newValue);
    await PushNotificationService.setEnabled(newValue);
  }

  Future<void> _loadAccount() async {
    final sessionEmail = await SessionService.email ?? '';
    final sessionFullName = await SessionService.fullName ?? '';
    final rawRoleLabel = await SessionService.roleLabel ?? '';

    final sessionRoleLabel = rawRoleLabel.contains('•')
        ? rawRoleLabel.split('•').first.trim()
        : rawRoleLabel.trim();

    bool isAdmin = false;

    if (sessionEmail.isNotEmpty) {
      try {
        isAdmin = await AccountService.isAdmin(sessionEmail);
      } catch (e) {
        debugPrint('Settings role check failed: $e');
        isAdmin = false;
      }
    }

    String? photoUrl;
    String? fullNameFromDb;
    String? usernameFromDb;

    try {
      photoUrl = await AccountService.getPhotoUrl(sessionEmail);
      fullNameFromDb = await AccountService.getFullName(sessionEmail);
      usernameFromDb = await AccountService.getUsername(sessionEmail);
    } catch (e) {
      debugPrint('Settings - Error loading photo: $e');
    }

    final localOverrides = await AccountService.getAccount(email: sessionEmail);

    if (!mounted) return;
    setState(() {
      _isAdmin = isAdmin;
      _email = sessionEmail;
      _fullName = fullNameFromDb ?? sessionFullName;
      _username = usernameFromDb ?? '';
      _displayName = localOverrides['displayName']?.isNotEmpty == true
          ? localOverrides['displayName']!
          : _fullName;
      _roleLabel = sessionRoleLabel;
      if (!_isUploadingPhoto && _photoBytes == null) {
        _photoPath = photoUrl ?? localOverrides['photoPath'];
      }
      _isLoadingAccount = false;
      _webNameCtrl.text = _fullName;
      _webUsernameCtrl.text = _username;
      _webEmailCtrl.text = _email;
      if (!_isAdmin && _webSelectedTab == 1) {
        _webSelectedTab = 0;
      }
    });

    if (isAdmin) {
      _loadStaffCount();
      _loadPharmacyDetails();
    }
  }

  Future<void> _loadPharmacyDetails() async {
    final details = await PharmacyService.getDetails();
    if (!mounted) return;
    setState(() {
      _webPharmacyNameCtrl.text = details['name'] ?? '';
      _webAddressCtrl.text = details['address'] ?? '';
      _webPhoneCtrl.text = details['phone'] ?? '';
    });
  }

  Future<void> _saveWebProfile() async {
    setState(() => _webIsSavingProfile = true);
    try {
      await AccountService.saveAccount(
        email: _email,
        displayName: _webNameCtrl.text.trim(),
        username: _webUsernameCtrl.text.trim(),
        photoPath: _photoPath,
      );
      if (!mounted) return;
      TopBanner.show(
  context,
  message: 'Profile updated!',
  width: 320,
  alignment: Alignment.topCenter,
);
      await _loadAccount();
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _webIsSavingProfile = false);
    }
  }

  Future<void> _saveWebPharmacy() async {
    setState(() => _webIsSavingPharmacy = true);
    await PharmacyService.saveDetails(
      name: _webPharmacyNameCtrl.text.trim(),
      address: _webAddressCtrl.text.trim(),
      phone: _webPhoneCtrl.text.trim(),
      email: _email,
      type: 'Retail Pharmacy',
    );
    if (!mounted) return;
    setState(() => _webIsSavingPharmacy = false);
    TopBanner.show(
  context,
  message: 'Pharmacy details saved!',
  width: 320,
  alignment: Alignment.topCenter,
);
  }

  bool _isStrongPassword(String password) {
    if (password.length < 8) return false;
    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(password);
    final hasNumber = RegExp(r'[0-9]').hasMatch(password);
    return hasLetter && hasNumber;
  }

  Future<void> _updatePassword() async {
    final current = _currentPasswordCtrl.text.trim();
    final newPass = _newPasswordCtrl.text.trim();
    final confirm = _confirmPasswordCtrl.text.trim();

    if (current.isEmpty || newPass.isEmpty || confirm.isEmpty) {
      _showPasswordError('Please fill in all fields.');
      return;
    }

    setState(() => _isSavingPassword = true);

    try {
      final isValid = await PasswordService.verifyCurrentPassword(current);

      if (!isValid) {
        _showPasswordError('Current password is incorrect.');
        setState(() => _isSavingPassword = false);
        return;
      }

      if (!_isStrongPassword(newPass)) {
        _showPasswordError(
          'New password must be at least 8 characters and include letters and numbers.',
        );
        setState(() => _isSavingPassword = false);
        return;
      }

      if (newPass != confirm) {
        _showPasswordError('New password and confirmation do not match.');
        setState(() => _isSavingPassword = false);
        return;
      }

      if (newPass == current) {
        _showPasswordError(
          'New password must be different from the current one.',
        );
        setState(() => _isSavingPassword = false);
        return;
      }

      await PasswordService.setPassword(newPass);

      if (!mounted) return;

      TopBanner.show(
  context,
  message: 'Password updated successfully!',
  width: 320,
  alignment: Alignment.topCenter,
);

      _currentPasswordCtrl.clear();
      _newPasswordCtrl.clear();
      _confirmPasswordCtrl.clear();
      setState(() => _isSavingPassword = false);
    } catch (e) {
      setState(() => _isSavingPassword = false);
      _showPasswordError('Failed to update password: ${e.toString()}');
    }
  }

  void _showPasswordError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _loadStaffCount() async {
    try {
      final staff = await StaffService.fetchStaff();
      if (mounted) setState(() => _staffCount = staff.length);
    } catch (e) {
      debugPrint('Staff count fetch error: $e');
    }
  }

  String get _initials {
    final parts = _displayName.trim().split(' ');
    if (_displayName.isEmpty) return '?';
    if (parts.length < 2) return _displayName.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Future<void> _editProfile() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(
          email: _email,
          initialDisplayName: _displayName,
          roleLabel: _roleLabel,
          fullName: _fullName,
          initialPhotoPath: _photoPath,
          initialUsername: _username,
        ),
      ),
    );
    if (result == true) {
      await _loadAccount();
    }
  }

  void _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await SessionService.clear();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const Login()),
        (route) => false,
      );
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      setState(() {
        _photoBytes = bytes;
        _isUploadingPhoto = true;
      });

      String url;
      if (kIsWeb) {
        final ext = picked.name.contains('.')
            ? picked.name.split('.').last
            : 'jpg';
        url = await SupabaseService.uploadProfilePhoto(
          email: _email,
          bytes: bytes,
          fileExt: ext,
        );
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final ext = picked.path.split('.').last;
        final fileName =
            'profile_${_email.replaceAll('@', '_')}_${DateTime.now().millisecondsSinceEpoch}.$ext';
        final savedPath = '${dir.path}/$fileName';
        final savedFile = await File(picked.path).copy(savedPath);

        if (_photoPath != null && !_photoPath!.startsWith('http')) {
          final oldFile = File(_photoPath!);
          if (await oldFile.exists()) {
            try {
              await oldFile.delete();
            } catch (_) {}
          }
        }

        final fileBytes = await savedFile.readAsBytes();
        url = await SupabaseService.uploadProfilePhoto(
          email: _email,
          bytes: fileBytes,
          fileExt: ext,
        );
        await savedFile.delete();
      }

      if (!mounted) return;

      final cacheBustedUrl =
          '$url${url.contains('?') ? '&' : '?'}t=${DateTime.now().millisecondsSinceEpoch}';

      try {
        await NetworkImage(url).evict();
        await NetworkImage(cacheBustedUrl).evict();
      } catch (_) {}

      setState(() {
        _photoPath = cacheBustedUrl;
        _photoBytes = null;
        _isUploadingPhoto = false;
      });
    } catch (e) {
      debugPrint('Pick photo error: $e');
      if (!mounted) return;
      setState(() => _isUploadingPhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Photo upload failed: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _notImplemented(String feature) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$feature coming soon')));
  }

  @override
  void dispose() {
    _webNameCtrl.dispose();
    _webUsernameCtrl.dispose();
    _webEmailCtrl.dispose();
    _webPharmacyNameCtrl.dispose();
    _webAddressCtrl.dispose();
    _webPhoneCtrl.dispose();
    _currentPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = kIsWeb;

    if (isWeb) {
      return _buildWebLayout(context);
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette(isDark);

    return Scaffold(
      backgroundColor: p.scaffoldBg,
      appBar: AppBar(
        backgroundColor: p.appBarBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kPrimaryBlue),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          'Settings',
          style: TextStyle(
            color: p.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: p.cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: p.cardBorder),
            ),
            child: Column(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: kPrimaryBlue,
                      backgroundImage: _getProfileImage(),
                      child: _photoPath == null || _photoPath!.isEmpty
                          ? Text(
                              _initials,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onTap: _editProfile,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: kPrimaryBlue,
                            shape: BoxShape.circle,
                            border: Border.all(color: p.cardBg, width: 2),
                          ),
                          child: const Icon(
                            Icons.edit,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  _displayName,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: p.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _roleLabel,
                  style: TextStyle(color: p.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: kPrimaryBlue.withValues(alpha: isDark ? 0.20 : 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _isAdmin ? 'Admin Account' : 'Staff Account',
                    style: const TextStyle(
                      color: kPrimaryBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          _sectionLabel('ACCOUNT', p),
          _isLoadingAccount
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _sectionCard(p, [
                  _infoField(
                    'Full Name',
                    _fullName,
                    Icons.badge_outlined,
                    p,
                    onTap: _editProfile,
                  ),
                  const SizedBox(height: 12),
                  _infoField(
                    'Username',
                    _username.isEmpty ? 'Not set' : _username,
                    Icons.alternate_email,
                    p,
                    onTap: _editProfile,
                  ),
                  const SizedBox(height: 12),
                  _infoField(
                    'Email Address',
                    _email,
                    Icons.mail_outline,
                    p,
                    onTap: _editProfile,
                  ),
                ]),
          const SizedBox(height: 22),

          _sectionLabel('SECURITY', p),
          _sectionCard(p, [
            _tile(
              icon: Icons.shield_outlined,
              label: 'Password',
              p: p,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ChangePasswordScreen(),
                  ),
                );
              },
            ),
          ]),
          const SizedBox(height: 22),

          _sectionLabel('PREFERENCES', p),
          _sectionCard(p, [
            _buildNotificationsTile(p),
            Divider(height: 1, color: p.rowDivider),
            _buildThemeTile(p),
          ]),

          if (_isAdmin) ...[
            const SizedBox(height: 22),
            _sectionLabel('PHARMACY ADMIN', p),
            _sectionCard(p, [
              _tile(
                icon: Icons.storefront_outlined,
                label: 'Pharmacy Details',
                p: p,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PharmacyDetailsScreen(),
                    ),
                  );
                },
              ),
              Divider(height: 1, color: p.rowDivider),
              _tile(
                icon: Icons.groups_outlined,
                label: 'Staff Management',
                p: p,
                trailingBadge: '$_staffCount Active',
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const StaffManagementScreen(),
                    ),
                  );
                  _loadStaffCount();
                },
              ),
            ]),
          ],

          const SizedBox(height: 22),
          _sectionLabel('SYSTEM', p),
          _sectionCard(p, [
            _tile(
              icon: Icons.support_agent_outlined,
              label: 'FAQ',
              p: p,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SupportScreen()),
                );
              },
            ),
          ]),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              onPressed: _logout,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Logout',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 3),
    );
  }

  ImageProvider? _getProfileImage() {
    if (_photoBytes != null) return MemoryImage(_photoBytes!);

    if (_photoPath == null || _photoPath!.isEmpty) return null;

    if (_photoPath!.startsWith('http')) {
      return NetworkImage(_photoPath!);
    }

    if (!kIsWeb) {
      return FileImage(File(_photoPath!));
    }

    return null;
  }

  // ─────────────────────────────────────────────────────────────────
  // Notifications tile — mirrors the Appearance/Theme switch
  // ─────────────────────────────────────────────────────────────────
  Widget _buildNotificationsTile(AppPalette p) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: kPrimaryBlue.withValues(alpha: p.isDark ? 0.20 : 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.notifications_none, size: 18, color: kPrimaryBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Notifications',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: p.textPrimary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              _notificationsOn ? 'On' : 'Off',
              style: TextStyle(color: p.textSecondary, fontSize: 13),
            ),
          ),
          Switch(
            value: _notificationsOn,
            activeColor: kPrimaryBlue,
            onChanged: (_) => _toggleNotifications(),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // Theme toggle tile (moved here from the mobile Dashboard AppBar)
  // ─────────────────────────────────────────────────────────────────
  Widget _buildThemeTile(AppPalette p) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, _, __) {
        final dark = ThemeService.isDark(context);
        return InkWell(
          onTap: () => ThemeService.toggle(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: kPrimaryBlue.withValues(
                      alpha: p.isDark ? 0.20 : 0.10,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: SvgPicture.string(
                      dark ? _svgSun : _svgMoon,
                      width: 18,
                      height: 18,
                      color: kPrimaryBlue,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Appearance',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: p.textPrimary,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    dark ? 'Dark' : 'Light',
                    style: TextStyle(color: p.textSecondary, fontSize: 13),
                  ),
                ),
                Switch(
                  value: dark,
                  activeColor: kPrimaryBlue,
                  onChanged: (_) => ThemeService.toggle(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sectionLabel(String text, AppPalette p) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: p.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _sectionCard(AppPalette p, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.cardBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(children: children),
    );
  }

  Widget _infoField(
    String label,
    String value,
    IconData icon,
    AppPalette p, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: p.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: p.searchBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(fontSize: 14, color: p.textPrimary),
                  ),
                ),
                Icon(icon, size: 18, color: p.textMuted),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String label,
    required AppPalette p,
    String? trailingText,
    String? trailingBadge,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: kPrimaryBlue.withValues(alpha: p.isDark ? 0.20 : 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: kPrimaryBlue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: p.textPrimary,
                ),
              ),
            ),
            if (trailingBadge != null)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: p.isDark
                      ? kWarningOrange.withValues(alpha: 0.20)
                      : const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  trailingBadge,
                  style: TextStyle(
                    color: p.isDark ? kWarningOrange : const Color(0xFFB45309),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (trailingText != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  trailingText,
                  style: TextStyle(color: p.textSecondary, fontSize: 13),
                ),
              ),
            Icon(Icons.chevron_right, color: p.textMuted, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _webField(
    String label,
    TextEditingController controller,
    AppPalette p, {
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: p.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: TextStyle(color: p.textPrimary),
          decoration: InputDecoration(
            filled: true,
            fillColor: p.searchBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: p.cardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: p.cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: kPrimaryBlue, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _webPasswordField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggle,
    required AppPalette p,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: p.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          enabled: !_isSavingPassword,
          style: TextStyle(color: p.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: p.textMuted, fontSize: 14),
            filled: true,
            fillColor: p.searchBg,
            suffixIcon: IconButton(
              icon: Icon(
                obscure ? Icons.visibility_off : Icons.visibility,
                color: p.textMuted,
                size: 20,
              ),
              onPressed: onToggle,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: p.cardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: p.cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: kPrimaryBlue, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _saveButton({
    required bool isSaving,
    required String label,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton(
      onPressed: isSaving ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: kPrimaryBlue,
        foregroundColor: Colors.white,
        minimumSize: const Size(180, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: isSaving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(
              label,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // WEB SUB-PAGES — titles left-aligned; fields left-aligned with
  // title; profile fields stacked one per row.
  // ─────────────────────────────────────────────────────────────────

   // ─────────────────────────────────────────────────────────────────
  // WEB SUB-PAGES — the whole block (title + content) is centered
  // horizontally within the page, but everything inside is left-aligned.
  // ─────────────────────────────────────────────────────────────────

  Widget _webProfileCard(AppPalette p) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Text(
              'Edit profile',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: p.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Manage your administrative profile and account details.',
              style: TextStyle(color: p.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 28),

            // ── Photo ──
            Text(
              'Photo',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: p.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: kPrimaryBlue,
                      backgroundImage: _getProfileImage(),
                      child: _getProfileImage() == null
                          ? Text(
                              _initials,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    if (_isUploadingPhoto)
                      Positioned.fill(
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 16),
                OutlinedButton(
                  onPressed: _isUploadingPhoto ? null : _pickAndUploadPhoto,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: p.textPrimary,
                    side: BorderSide(color: p.cardBorder),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                  ),
                  child: const Text('Change'),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // ── Fields (one per line, all left-aligned) ──
            _webField('Full Name', _webNameCtrl, p),
            const SizedBox(height: 16),

            // Role (read-only)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Role',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: p.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: p.searchBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: p.cardBorder),
                  ),
                  child: Text(
                    _roleLabel,
                    style: TextStyle(color: p.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            _webField('Username', _webUsernameCtrl, p),
            const SizedBox(height: 16),

            _webField(
              'Email Address',
              _webEmailCtrl,
              p,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 24),

            _saveButton(
              isSaving: _webIsSavingProfile,
              label: 'Save Changes',
              onPressed: _saveWebProfile,
            ),
          ],
        ),
      ),
    );
  }

  Widget _webSecurityCard(AppPalette p) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Text(
              'Change Password',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: p.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Manage your account security by updating your password regularly.',
              style: TextStyle(color: p.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 28),

            // ── Fields ──
            _webPasswordField(
              label: 'Current Password',
              hint: 'Enter current password',
              controller: _currentPasswordCtrl,
              obscure: _obscureCurrent,
              p: p,
              onToggle: () =>
                  setState(() => _obscureCurrent = !_obscureCurrent),
            ),
            const SizedBox(height: 16),
            _webPasswordField(
              label: 'New Password',
              hint: 'Create new password',
              controller: _newPasswordCtrl,
              obscure: _obscureNew,
              p: p,
              onToggle: () => setState(() => _obscureNew = !_obscureNew),
            ),
            const SizedBox(height: 16),
            _webPasswordField(
              label: 'Confirm New Password',
              hint: 'Confirm new password',
              controller: _confirmPasswordCtrl,
              obscure: _obscureConfirm,
              p: p,
              onToggle: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: kPrimaryBlue.withValues(alpha: p.isDark ? 0.15 : 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: kPrimaryBlue,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Strong passwords contain at least 8 characters, including letters and numbers. Avoid using information like birthdays or common words.',
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _saveButton(
              isSaving: _isSavingPassword,
              label: 'Update Password',
              onPressed: _updatePassword,
            ),
          ],
        ),
      ),
    );
  }

  Widget _webPharmacyCard(AppPalette p) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Text(
              'Pharmacy Details',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: p.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Global settings for your medical establishment.',
              style: TextStyle(color: p.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 28),

            // ── Fields ──
            _webField('Pharmacy Name', _webPharmacyNameCtrl, p),
            const SizedBox(height: 16),
            _webField('Business Address', _webAddressCtrl, p),
            const SizedBox(height: 16),
            _webField(
              'Contact Number',
              _webPhoneCtrl,
              p,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 20),
            _saveButton(
              isSaving: _webIsSavingPharmacy,
              label: 'Save Changes',
              onPressed: _saveWebPharmacy,
            ),
          ],
        ),
      ),
    );
  }

  Widget _webSelectedCard(AppPalette p) {
    switch (_webSelectedTab) {
      case 1:
        return _isAdmin ? _webPharmacyCard(p) : _webProfileCard(p);
      case 2:
        return _webSecurityCard(p);
      case 0:
      default:
        return _webProfileCard(p);
    }
  }

  Widget _buildWebLayout(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette(isDark);

    final activeSubRoute = switch (_webSelectedTab) {
      1 => 'pharmacy',
      2 => 'security',
      _ => 'profile',
    };

    return WebShell(
      activeRoute: 'settings',
      activeSubRoute: activeSubRoute,
      photoUrl: _photoPath,
      displayName: _displayName,
      headerBar: WebTopBar(
        pageTitle: 'Settings',
        showSearch: false,
        initials: _initials,
        photoUrl: _photoPath,
        displayName: _displayName.isEmpty ? 'Account' : _displayName,
        roleLabel: _roleLabel,
      ),
      // The Profile / Pharmacy / Security sub-navigation now lives in the
      // sidebar (under Settings), so this page is just the selected
      // section's content, full width.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrowShell = MediaQuery.of(context).size.width < 1024;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isNarrowShell) const SizedBox(height: 16),
              _webSelectedCard(p),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// SVG icons used by the Appearance/Theme toggle
// ─────────────────────────────────────────────────────────────────
const String _svgMoon =
    '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><rect width="256" height="256" fill="none"/><path d="M235.54,150.21a104.84,104.84,0,0,1-37,52.91A104,104,0,0,1,32,120,103.09,103.09,0,0,1,52.88,57.48a104.84,104.84,0,0,1,52.91-37,8,8,0,0,1,10,10,88.08,88.08,0,0,0,109.8,109.8,8,8,0,0,1,10,10Z"/></svg>''';

const String _svgSun =
    '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><rect width="256" height="256" fill="none"/><path d="M120,40V16a8,8,0,0,1,16,0V40a8,8,0,0,1-16,0Zm8,24a64,64,0,1,0,64,64A64.07,64.07,0,0,0,128,64ZM58.34,69.66A8,8,0,0,0,69.66,58.34l-16-16A8,8,0,0,0,42.34,53.66Zm0,116.68-16,16a8,8,0,0,0,11.32,11.32l16-16a8,8,0,0,0-11.32-11.32ZM192,72a8,8,0,0,0,5.66-2.34l16-16a8,8,0,0,0-11.32-11.32l-16,16A8,8,0,0,0,192,72Zm5.66,114.34a8,8,0,0,0-11.32,11.32l16,16a8,8,0,0,0,11.32-11.32ZM48,128a8,8,0,0,0-8-8H16a8,8,0,0,0,0,16H40A8,8,0,0,0,48,128Zm80,80a8,8,0,0,0-8,8v24a8,8,0,0,0,16,0V216A8,8,0,0,0,128,208Zm112-88H216a8,8,0,0,0,0,16h24a8,8,0,0,0,0-16Z"/></svg>''';