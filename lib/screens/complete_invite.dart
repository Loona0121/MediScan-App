import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../services/auth_service_complete.dart';
import 'dashboard.dart';

enum _BannerType { success, error }

class CompleteInviteScreen extends StatefulWidget {
  final String email;

  const CompleteInviteScreen({super.key, required this.email});

  @override
  State<CompleteInviteScreen> createState() => _CompleteInviteScreenState();
}

class _CompleteInviteScreenState extends State<CompleteInviteScreen> {
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isSuccess = false;

  String? _bannerMessage;
  _BannerType _bannerType = _BannerType.error;
  String? _passwordError;

  String? _validatePassword(String password) {
    if (password.isEmpty) return null;
    if (password.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Password must have at least one uppercase letter';
    }
    if (!RegExp(r'[a-z]').hasMatch(password)) {
      return 'Password must have at least one lowercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(password)) {
      return 'Password must have at least one digit';
    }
    if (!RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      return 'Passwords must have at least one non letter or digit character.';
    }
    return null;
  }

  Future<void> _completeInvite() async {
    final fullName = _fullNameController.text.trim();
    final username = _usernameController.text.trim();
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (fullName.isEmpty || username.isEmpty) {
      _showBanner('Please fill in your name and username', _BannerType.error);
      return;
    }

    final pwError = _validatePassword(newPassword);
    if (pwError != null) {
      setState(() => _passwordError = pwError);
      return;
    }
    if (newPassword != confirmPassword) {
      setState(() => _passwordError = 'Passwords do not match');
      return;
    }

    setState(() {
      _isLoading = true;
      _bannerMessage = null;
      _passwordError = null;
    });

    try {
      final existingUsername = await SupabaseService.client
          .from('staff')
          .select('id')
          .eq('username', username)
          .maybeSingle();
      if (existingUsername != null) {
        setState(() => _isLoading = false);
        _showBanner('This username is already taken.', _BannerType.error);
        return;
      }

      await SupabaseService.updatePassword(newPassword);

      await SupabaseService.client
          .from('staff')
          .update({
            'full_name': fullName,
            'username': username,
            'profile_completed': true,
          })
          .eq('email', widget.email);

      final synced = await AuthService.syncSessionForCurrentUser();

      if (!mounted) return;

      if (!synced) {
        setState(() => _isLoading = false);
        _showBanner(
          'Profile saved, but something went wrong loading your account. '
          'Please try logging in.',
          _BannerType.error,
        );
        return;
      }

      setState(() {
        _isLoading = false;
        _isSuccess = true;
      });

      _showBanner('Welcome to MediScan!', _BannerType.success);

      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const Dashboard()),
          (route) => false,
        );
      });
    } catch (e) {
      setState(() => _isLoading = false);

      String errorMessage = e.toString();
      if (errorMessage.contains('session') || errorMessage.contains('token')) {
        errorMessage =
            'Your invite link has expired. Please ask your admin to resend it.';
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
    _fullNameController.dispose();
    _usernameController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: isMobile ? _buildMobileLayout() : _buildWebLayout(),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // WEB LAYOUT — mirrors login.dart's two-column card
  // ─────────────────────────────────────────────────────────────────
  Widget _buildWebLayout() {
    return Container(
      width: MediaQuery.of(context).size.width * 0.7,
      constraints: const BoxConstraints(
        maxWidth: 820,
        maxHeight: 620,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // ── Left panel (same as login) ─────────────────────────────
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFDBEAFE), Color(0xFFEFF6FF)],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/pharmacy.jpg',
                    width: 220,
                    height: 190,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Never Miss an\nExpiry Date',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E3A8A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Monitor your pharmacy inventory smarter\nwith AI-powered expiry tracking.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF3B82F6),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Right panel (form) ─────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: _buildForm(),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // MOBILE LAYOUT — mirrors login.dart's stacked layout
  // ─────────────────────────────────────────────────────────────────
  Widget _buildMobileLayout() {
    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Column(
                  children: [
                    Image.asset(
                      'assets/images/pharmacy.jpg',
                      width: double.infinity,
                      height: 160,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Never Miss an Expiry Date',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E3A8A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'AI-powered pharmacy inventory tracking',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF3B82F6),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: _buildForm(),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // ERROR BANNER — same visual style as login.dart
  // ─────────────────────────────────────────────────────────────────
  Widget _buildBanner() {
    if (_bannerMessage == null) return const SizedBox.shrink();

    final bool isSuccess = _bannerType == _BannerType.success;
    final Color bg = isSuccess ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2);
    final Color border = isSuccess ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA);
    final Color text = isSuccess ? const Color(0xFF15803D) : const Color(0xFFB91C1C);
    final IconData icon =
        isSuccess ? Icons.check_circle_outline : Icons.error_outline_rounded;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        axisAlignment: -1,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: Container(
        key: ValueKey(_bannerMessage),
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                style: TextStyle(
                  color: text,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // SHARED FORM — matches login.dart's input styling and spacing
  // ─────────────────────────────────────────────────────────────────
  Widget _buildForm() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment:
          _isSuccess ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        // Heading (replaces login's "Username" as the top element)
        Text(
          _isSuccess ? "You're All Set!" : 'Complete Your Account',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E3A8A),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _isSuccess
              ? 'Taking you to your dashboard...'
              : 'Set up your staff account to continue.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 16),

        // Error / success banner
        _buildBanner(),

        if (_isSuccess)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[

          // Full Name
          const Text(
            'Full Name',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _fullNameController,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => FocusScope.of(context).nextFocus(),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              hintText: 'Enter your full name',
              hintStyle: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 14,
              ),
              prefixIcon: const Icon(
                Icons.badge_outlined,
                color: Color(0xFF94A3B8),
              ),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: _bannerMessage != null && !_isSuccess
                      ? const Color(0xFFFCA5A5)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: Color(0xFF2563EB), width: 2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Username
          const Text(
            'Username',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _usernameController,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => FocusScope.of(context).nextFocus(),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              hintText: 'Choose a username',
              hintStyle: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 14,
              ),
              prefixIcon: const Icon(
                Icons.person_outline,
                color: Color(0xFF94A3B8),
              ),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: _bannerMessage != null && !_isSuccess
                      ? const Color(0xFFFCA5A5)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: Color(0xFF2563EB), width: 2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Password
          const Text(
            'Password',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _newPasswordController,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => FocusScope.of(context).nextFocus(),
            onChanged: (value) {
              if (_passwordError != null) {
                setState(() {
                  _passwordError = _validatePassword(value.trim());
                });
              }
            },
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              hintText: 'Create a password',
              hintStyle: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 14,
              ),
              prefixIcon: const Icon(
                Icons.lock_outline,
                color: Color(0xFF94A3B8),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: const Color(0xFF94A3B8),
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
              errorText: _passwordError,
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: _passwordError != null
                      ? const Color(0xFFFCA5A5)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: Color(0xFF2563EB), width: 2),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: Color(0xFFDC2626), width: 1.5),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: Color(0xFFDC2626), width: 2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Confirm Password
          const Text(
            'Confirm Password',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _completeInvite(),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              hintText: 'Confirm your password',
              hintStyle: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 14,
              ),
              prefixIcon: const Icon(
                Icons.lock_outline,
                color: Color(0xFF94A3B8),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_off
                      : Icons.visibility,
                  color: const Color(0xFF94A3B8),
                ),
                onPressed: () => setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: _bannerMessage != null && !_isSuccess
                      ? const Color(0xFFFCA5A5)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: Color(0xFF2563EB), width: 2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Get Started button — same style as login's Log in
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _completeInvite,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3C83F6),
                disabledBackgroundColor: const Color(0xFF3C83F6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Get Started',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ],
    );
  }
}