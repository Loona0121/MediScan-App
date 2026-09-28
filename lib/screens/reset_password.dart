import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

enum _BannerType { success, error }

/// Reached ONLY from ForgotPasswordScreen, and ONLY after the OTP has been
/// verified there. By the time this screen is shown, Supabase already has
/// an authenticated recovery session for [email] — so this screen just
/// needs to collect and submit the new password.
class ResetPasswordScreen extends StatefulWidget {
  final String email;

  const ResetPasswordScreen({super.key, required this.email});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isSuccess = false;

  String? _bannerMessage;
  _BannerType _bannerType = _BannerType.error;

  // Live checklist state
  bool get _hasMinLength => _newPasswordController.text.length >= 8;
  bool get _passwordsMatch =>
      _confirmPasswordController.text.isNotEmpty &&
      _newPasswordController.text == _confirmPasswordController.text;

  @override
  void initState() {
    super.initState();
    _newPasswordController.addListener(() => setState(() {}));
    _confirmPasswordController.addListener(() => setState(() {}));
  }

  Future<void> _resetPassword() async {
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (newPassword.isEmpty || confirmPassword.isEmpty) {
      _showBanner('Please fill in all fields', _BannerType.error);
      return;
    }
    if (newPassword.length < 8) {
      _showBanner('Password must be at least 8 characters', _BannerType.error);
      return;
    }
    if (newPassword != confirmPassword) {
      _showBanner('Passwords do not match', _BannerType.error);
      return;
    }

    setState(() {
      _isLoading = true;
      _bannerMessage = null;
    });

    try {
      await SupabaseService.updatePassword(newPassword);

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isSuccess = true;
      });

      _showBanner('Password updated successfully!', _BannerType.success);

      // Send them all the way back to login, past the OTP screen.
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      });
    } catch (e) {
      setState(() => _isLoading = false);

      String errorMessage = e.toString();
      if (errorMessage.contains('session') || errorMessage.contains('token')) {
        errorMessage = 'Your session has expired. Please request a new code.';
      } else if (errorMessage.contains('same_password')) {
        errorMessage = 'New password must be different from your old password.';
      } else if (errorMessage.startsWith('Exception: ')) {
        errorMessage = errorMessage.substring(11);
      }
      _showBanner(errorMessage, _BannerType.error);
    }
  }

  void _showBanner(String message, _BannerType type) {
    setState(() {
      _bannerMessage = message;
      _bannerType = type;
    });
  }

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: kIsWeb ? null : const Text('Reset Password'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        automaticallyImplyLeading: !_isSuccess,
      ),
      body: SafeArea(
        child: Builder(
          builder: (context) {
            final screenWidth = MediaQuery.of(context).size.width;
            final isMobile = screenWidth < 768;

            final content = ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBanner(),

                    Text(
                      _isSuccess ? 'Password Updated' : 'New Credentials',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E3A8A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isSuccess
                          ? 'Your password has been successfully updated.'
                          : 'Choose a new password for your account.',
                      style: const TextStyle(
                        fontSize: 15,
                        color: Color(0xFF64748B),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 28),

                    if (_isSuccess)
                      const Center(child: CircularProgressIndicator())
                    else
                      _buildPasswordForm(),
                  ],
                ),
              ),
            );

            // Mobile: pin content to the top instead of vertically centering it.
            // Web/desktop: keep the original centered layout.
            return isMobile ? Align(alignment: Alignment.topCenter, child: content)
                             : Center(child: content);
          },
        ),
      ),
    );
  }

  Widget _buildBanner() {
    if (_bannerMessage == null) return const SizedBox.shrink();

    final bool isSuccess = _bannerType == _BannerType.success;
    final Color bg = isSuccess ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2);
    final Color border = isSuccess ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA);
    final Color text = isSuccess ? const Color(0xFF15803D) : const Color(0xFFB91C1C);
    final IconData icon = isSuccess ? Icons.check_circle_outline : Icons.error_outline_rounded;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: text, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _bannerMessage!,
              style: TextStyle(color: text, fontSize: 13, fontWeight: FontWeight.w500, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequirement(String label, bool met) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle : Icons.cancel,
            size: 15,
            color: met ? const Color(0xFF16A34A) : const Color(0xFFCBD5E1),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: met ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordForm() {
    final showChecklist = _newPasswordController.text.isNotEmpty ||
        _confirmPasswordController.text.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showChecklist) ...[
          _buildRequirement('At least 8 characters', _hasMinLength),
          _buildRequirement('Passwords match', _passwordsMatch),
          const SizedBox(height: 16),
        ] else ...[
          Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              Text('Minimum 8 characters', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _newPasswordController,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
          decoration: InputDecoration(
            labelText: 'New Password',
            hintText: 'Enter your new password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2),
            ),
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _confirmPasswordController,
          obscureText: _obscureConfirmPassword,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _resetPassword(),
          decoration: InputDecoration(
            labelText: 'Confirm Password',
            hintText: 'Confirm your new password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
              onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
            ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2),
            ),
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _resetPassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Submit', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            onPressed: _isLoading ? null : () => Navigator.of(context).popUntil((r) => r.isFirst),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF2563EB),
              side: const BorderSide(color: Color(0xFF2563EB)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Cancel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}