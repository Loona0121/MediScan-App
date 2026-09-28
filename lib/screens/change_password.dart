import 'package:flutter/material.dart';
import '../services/password_service.dart';
import '../services/session_service.dart';
import '../widgets/web_shell.dart';
import '../utils/app_palette.dart';   // ← ADDED

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSaving = false;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool _isStrongPassword(String password) {
    if (password.length < 8) return false;
    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(password);
    final hasNumber = RegExp(r'[0-9]').hasMatch(password);
    return hasLetter && hasNumber;
  }

  Future<void> _updatePassword() async {
    final current = _currentController.text.trim();
    final newPass = _newController.text.trim();
    final confirm = _confirmController.text.trim();

    if (current.isEmpty || newPass.isEmpty || confirm.isEmpty) {
      _showError('Please fill in all fields.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final username = await SessionService.username;
      final isAdmin = await SessionService.isAdmin;
      print('🔍 ChangePassword - Username: $username');
      print('🔍 ChangePassword - IsAdmin: $isAdmin');
      print('🔍 ChangePassword - Current password length: ${current.length}');

      print('🔍 Verifying current password...');
      final isValid = await PasswordService.verifyCurrentPassword(current);
      print('🔍 Password verification result: $isValid');

      if (!isValid) {
        _showError('Current password is incorrect.');
        setState(() => _isSaving = false);
        return;
      }

      if (!_isStrongPassword(newPass)) {
        _showError(
          'New password must be at least 8 characters and include letters and numbers.',
        );
        setState(() => _isSaving = false);
        return;
      }

      if (newPass != confirm) {
        _showError('New password and confirmation do not match.');
        setState(() => _isSaving = false);
        return;
      }

      if (newPass == current) {
        _showError('New password must be different from the current one.');
        setState(() => _isSaving = false);
        return;
      }

      print('🔍 Updating password...');
      await PasswordService.setPassword(newPass);
      print('✅ Password updated successfully!');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      _currentController.clear();
      _newController.clear();
      _confirmController.clear();

      Navigator.pop(context, true);
    } catch (e) {
      print('❌ Error in _updatePassword: $e');
      setState(() => _isSaving = false);
      _showError('Failed to update password: ${e.toString()}');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ← CHANGED: takes `p` and uses theme-aware colors.
  Widget _passwordField({
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
            color: p.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          enabled: !_isSaving,
          style: TextStyle(color: p.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: p.textSecondary, fontSize: 14),
            filled: true,
            fillColor: p.searchBg,
            suffixIcon: IconButton(
              icon: Icon(
                obscure ? Icons.visibility_off : Icons.visibility,
                color: p.textSecondary,
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
              borderSide: const BorderSide(color: Color(0xFF3C83F6), width: 2),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF3C83F6);
    final isWeb = MediaQuery.of(context).size.width >= 900;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette(isDark);

    if (isWeb) {
      return WebShell(
        activeRoute: 'settings',
        activeSubRoute: 'security',
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Security',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Manage your account password and login security.',
                style: TextStyle(color: p.textSecondary),
              ),
              const SizedBox(height: 24),
              _buildContent(context, primaryBlue, p),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      // ← CHANGED
      backgroundColor: p.scaffoldBg,
      appBar: AppBar(
        // ← CHANGED
        backgroundColor: p.appBarBg,
        elevation: 0,
        surfaceTintColor: p.appBarBg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: primaryBlue),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          'Security',
          style: TextStyle(
            color: p.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: _buildContent(context, primaryBlue, p),
            ),
          ),
        ],
      ),
    );
  }

  // ← CHANGED: takes `p` so every card/box is theme-aware.
  Widget _buildContent(BuildContext context, Color primaryBlue, AppPalette p) {
    final isDark = p.isDark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            // ← CHANGED
            color: p.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Change Password',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Manage your account security by updating your password regularly.',
                style: TextStyle(color: p.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),
              _passwordField(
                label: 'Current Password',
                hint: 'Enter current password',
                controller: _currentController,
                obscure: _obscureCurrent,
                onToggle: () =>
                    setState(() => _obscureCurrent = !_obscureCurrent),
                p: p,
              ),
              const SizedBox(height: 16),
              _passwordField(
                label: 'New Password',
                hint: 'Create new password',
                controller: _newController,
                obscure: _obscureNew,
                onToggle: () => setState(() => _obscureNew = !_obscureNew),
                p: p,
              ),
              const SizedBox(height: 16),
              _passwordField(
                label: 'Confirm New Password',
                hint: 'Confirm new password',
                controller: _confirmController,
                obscure: _obscureConfirm,
                onToggle: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
                p: p,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _updatePassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Update Password',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            // ← CHANGED: tinted primary instead of hard-coded light blue
            color: primaryBlue.withValues(alpha: isDark ? 0.15 : 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: primaryBlue, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Strong passwords contain at least 8 characters, including letters, numbers, and symbols. Avoid using information like birthdays or common words.',
                  style: TextStyle(
                      color: p.textSecondary, fontSize: 12.5, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}