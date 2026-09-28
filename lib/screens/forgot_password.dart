import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../services/auth_service_complete.dart';
import 'reset_password.dart';

enum _BannerType { success, error, info }

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();

  // Segmented 6-digit OTP input
  static const int _otpLength = 6;
  final List<TextEditingController> _otpControllers =
      List.generate(_otpLength, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes =
      List.generate(_otpLength, (_) => FocusNode());

  bool _isLoading = false;
  bool _isResending = false;
  bool _otpSent = false; // step 2: enter code

  // Top banner state (replaces SnackBars for this flow)
  String? _bannerMessage;
  _BannerType _bannerType = _BannerType.info;

  String get _email => _emailController.text.trim();

  String get _otpCode => _otpControllers.map((c) => c.text).join();

  // Step 1: request the OTP
  Future<void> _requestOtp() async {
    final email = _email;

    if (email.isEmpty) {
      _showBanner('Please enter your email address', _BannerType.error);
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      _showBanner('Please enter a valid email address', _BannerType.error);
      return;
    }

    setState(() {
      _isLoading = true;
      _bannerMessage = null;
    });

    try {
      final exists = await AuthService.emailExists(email);
      if (!exists) {
        setState(() => _isLoading = false);
        _showBanner('No account found with this email address.', _BannerType.error);
        return;
      }

      await AuthService.sendPasswordResetOTP(email: email);

      setState(() {
        _isLoading = false;
        _otpSent = true;
      });

      _showBanner('Verification code sent! Check your inbox.', _BannerType.success);
    } catch (e) {
      setState(() => _isLoading = false);
      _showBanner(_cleanError(e), _BannerType.error);
    }
  }

  // Step 2: verify the OTP only — no password field on this screen
  Future<void> _verifyOtp() async {
    final code = _otpCode;

    if (code.length < _otpLength) {
      _showBanner('Please enter the full 6-digit code', _BannerType.error);
      return;
    }

    setState(() {
      _isLoading = true;
      _bannerMessage = null;
    });

    try {
      await AuthService.verifyPasswordResetOtp(email: _email, token: code);

      if (!mounted) return;
      setState(() => _isLoading = false);

      // Code confirmed — only now can the user reach the password screen.
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => ResetPasswordScreen(email: _email)),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      _showBanner(_cleanError(e), _BannerType.error);
      _clearOtpFields();
    }
  }

  Future<void> _resendOtp() async {
    setState(() => _isResending = true);
    try {
      await AuthService.sendPasswordResetOTP(email: _email);
      _showBanner('New verification code sent!', _BannerType.success);
      _clearOtpFields();
    } catch (e) {
      _showBanner(_cleanError(e), _BannerType.error);
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  void _clearOtpFields() {
    for (final c in _otpControllers) {
      c.clear();
    }
    _otpFocusNodes.first.requestFocus();
  }

  void _onOtpDigitChanged(int index, String value) {
    if (value.isNotEmpty) {
      if (index + 1 < _otpLength) {
        _otpFocusNodes[index + 1].requestFocus();
      } else {
        _otpFocusNodes[index].unfocus();
        _verifyOtp();
      }
    }
  }

  String _cleanError(Object e) {
    String message = e.toString();
    if (message.startsWith('Exception: ')) {
      message = message.substring(11);
    }
    return message;
  }

  void _showBanner(String message, _BannerType type) {
    setState(() {
      _bannerMessage = message;
      _bannerType = type;
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_otpSent) {
              setState(() {
                _otpSent = false;
                _bannerMessage = null;
                _clearOtpFields();
              });
            } else {
              Navigator.pop(context);
            }
          },
        ),
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
                    // Banner sits at the very top of the page content, not the
                    // bottom like a SnackBar.
                    _buildBanner(),

                    Text(
                      _otpSent ? 'Code Verification' : 'Forgot Password',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E3A8A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _otpSent
                          ? 'Enter the 6-digit code sent to $_email'
                          : 'Provide the email address linked with your account to reset your password.',
                      style: const TextStyle(
                        fontSize: 15,
                        color: Color(0xFF64748B),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 28),

                    if (_otpSent) _buildOtpForm() else _buildEmailForm(),
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

    late Color bg, border, text;
    late IconData icon;
    switch (_bannerType) {
      case _BannerType.success:
        bg = const Color(0xFFF0FDF4);
        border = const Color(0xFFBBF7D0);
        text = const Color(0xFF15803D);
        icon = Icons.check_circle_outline;
        break;
      case _BannerType.error:
        bg = const Color(0xFFFEF2F2);
        border = const Color(0xFFFECACA);
        text = const Color(0xFFB91C1C);
        icon = Icons.error_outline_rounded;
        break;
      case _BannerType.info:
        bg = const Color(0xFFEFF6FF);
        border = const Color(0xFFBFDBFE);
        text = const Color(0xFF1D4ED8);
        icon = Icons.info_outline_rounded;
        break;
    }

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

  Widget _buildEmailForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Email',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _requestOtp(),
          decoration: InputDecoration(
            hintText: 'you@example.com',
            prefixIcon: const Icon(Icons.email_outlined),
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
        const SizedBox(height: 8),
        Text(
          'Please enter your registered email',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _requestOtp,
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
                : const Text('Request Password Reset Link',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF2563EB),
              side: const BorderSide(color: Color(0xFF2563EB)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Cancel', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _buildOtpForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Segmented 6-digit code input
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(_otpLength, (index) {
            return SizedBox(
              width: 48,
              height: 56,
              child: TextField(
                controller: _otpControllers[index],
                focusNode: _otpFocusNodes[index],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 1,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF94A3B8), width: 1.5),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF94A3B8), width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2),
                  ),
                ),
                onChanged: (value) => _onOtpDigitChanged(index, value),
                onTap: () {
                  // Place cursor at the end so typing replaces existing digit
                  _otpControllers[index].selection = TextSelection.fromPosition(
                    TextPosition(offset: _otpControllers[index].text.length),
                  );
                },
                onSubmitted: (_) => _verifyOtp(),
              ),
            );
          }),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _verifyOtp,
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
                : const Text('Verify Code', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            onPressed: _isResending ? null : _resendOtp,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF2563EB),
              side: const BorderSide(color: Color(0xFF2563EB)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isResending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Resend Code', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}