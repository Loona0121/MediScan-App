import 'package:flutter/material.dart';

import '../services/auth_service_complete.dart';
import '../widgets/success_dialog.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final pharmacyNameController = TextEditingController();
  final addressController = TextEditingController();
  final usernameController = TextEditingController();
  final fullnameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool obscurePassword = true;
  bool obscureConfirmPassword = true;
  bool _isSubmitting = false;

  String? _emailError;
  String? _usernameError;
  String? _passwordError;

  String pharmacyType = 'Retail Pharmacy';

  int _currentStep = 0;

  bool _showOtpScreen = false;
  bool _isPasswordReset = false;
  String? _tempEmail;

  final List<TextEditingController> _otpControllers =
      List.generate(6, (_) => TextEditingController());

  final List<FocusNode> _otpFocusNodes =
      List.generate(6, (_) => FocusNode());

  bool _isVerifying = false;
  bool _otpComplete = false;

  // ─────────────────────────────────────────────────────────────
  // Field styling — mirrors login.dart exactly
  // ─────────────────────────────────────────────────────────────
  InputDecoration pillDecoration({
  String? hint,
  Widget? suffixIcon,
  String? errorText,
}) {
  return InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xFFA1A9B8), fontSize: 14),
    filled: true,
    fillColor: const Color(0xFFF1F4F9),
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    suffixIcon: suffixIcon,
    errorText: errorText,
    errorStyle: const TextStyle(fontSize: 11),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(28),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(28),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(28),
      borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(28),
      borderSide: const BorderSide(color: Colors.red, width: 1.2),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(28),
      borderSide: const BorderSide(color: Colors.red, width: 1.5),
    ),
  );
}

Widget _fieldLabel(String text) {
  return Padding(
    padding: const EdgeInsets.only(left: 6, bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF334155),
      ),
    ),
  );
}

Widget _labeledField({
  required String label,
  required TextEditingController controller,
  String? hint,
  bool obscureText = false,
  Widget? suffixIcon,
  String? errorText,
  TextInputType? keyboardType,
  TextInputAction? textInputAction,
  ValueChanged<String>? onChanged,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _fieldLabel(label),
      TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        onChanged: onChanged,
        decoration: pillDecoration(
          hint: hint,
          suffixIcon: suffixIcon,
          errorText: errorText,
        ),
      ),
    ],
  );
}


  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showInfoSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF2563EB),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Sign Up Failed'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    pharmacyNameController.dispose();
    addressController.dispose();
    usernameController.dispose();
    fullnameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();

    for (final controller in _otpControllers) {
      controller.dispose();
    }
    for (final node in _otpFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // Validation — unchanged
  // ─────────────────────────────────────────────────────────────
  void _validateEmail(String value) {
    if (!mounted) return;
    setState(() {
      if (value.isNotEmpty &&
          !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
        _emailError = 'Enter a valid email';
      } else {
        _emailError = null;
      }
    });
  }

  void _validateUsername(String value) {
    if (!mounted) return;
    setState(() {
      if (value.isNotEmpty && value.length < 3) {
        _usernameError = 'At least 3 characters';
      } else if (value.isNotEmpty &&
          !RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
        _usernameError = 'Letters, numbers, and _ only';
      } else {
        _usernameError = null;
      }
    });
  }

  void _validatePassword(String value) {
    if (!mounted) return;
    setState(() {
      if (value.isNotEmpty && value.length < 8) {
        _passwordError = 'At least 8 characters';
      } else {
        _passwordError = null;
      }
    });
  }

  void _goToNextStep() {
    if (pharmacyNameController.text.trim().isEmpty ||
        addressController.text.trim().isEmpty) {
      _showError('Please fill in the pharmacy information first.');
      return;
    }
    setState(() => _currentStep = 1);
  }

  void _goToPreviousStep() {
    setState(() => _currentStep = 0);
  }

  void _onOtpChanged(String value, int index) {
    if (value.length == 1 && index < 5) {
      _otpFocusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _otpFocusNodes[index - 1].requestFocus();
    }

    final allFilled =
        _otpControllers.every((controller) => controller.text.length == 1);

    setState(() => _otpComplete = allFilled);

    if (allFilled && !_isVerifying) {
      _verifyOtp();
    }
  }

  String _getOtpCode() {
    return _otpControllers.map((controller) => controller.text).join();
  }

  Future<void> _createAccount() async {
    setState(() {
      _emailError = null;
      _usernameError = null;
      _passwordError = null;
    });

    if (pharmacyNameController.text.trim().isEmpty ||
        addressController.text.trim().isEmpty ||
        usernameController.text.trim().isEmpty ||
        fullnameController.text.trim().isEmpty ||
        emailController.text.trim().isEmpty ||
        passwordController.text.isEmpty ||
        confirmPasswordController.text.isEmpty) {
      _showErrorDialog('Please fill in all fields.');
      return;
    }

    final email = emailController.text.trim();
    final username = usernameController.text.trim();

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _showErrorDialog('Please enter a valid email address.');
      return;
    }
    if (username.length < 3) {
      _showErrorDialog('Username must be at least 3 characters.');
      return;
    }
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(username)) {
      _showErrorDialog(
          'Username can only contain letters, numbers, and underscores.');
      return;
    }
    if (passwordController.text.length < 8) {
      _showErrorDialog('Password must be at least 8 characters.');
      return;
    }
    if (passwordController.text != confirmPasswordController.text) {
      _showErrorDialog('Passwords do not match.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await AuthService.signUpPharmacy(
        pharmacyName: pharmacyNameController.text.trim(),
        address: addressController.text.trim(),
        type: pharmacyType,
        fullName: fullnameController.text.trim(),
        username: username,
        email: email,
        password: passwordController.text,
      );

      if (!mounted) return;

      for (final controller in _otpControllers) {
        controller.clear();
      }

      setState(() {
        _isSubmitting = false;
        _tempEmail = email;
        _isPasswordReset = false;
        _showOtpScreen = true;
        _otpComplete = false;
      });

      // NOTE: The "Verification code sent to $email" snackbar that used to
      // fire here has been removed — the OTP screen itself already displays
      // this information, so the extra bottom banner was redundant.
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);

      String errorMessage = e.toString();
      if (errorMessage.startsWith('Exception: ')) {
        errorMessage = errorMessage.substring(11);
      }
      if (errorMessage.contains('duplicate key') ||
          errorMessage.contains('23505')) {
        errorMessage = 'This email or username is already registered.';
      }
      _showErrorDialog(errorMessage);
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _getOtpCode();
    if (otp.length != 6 || _tempEmail == null) return;

    setState(() => _isVerifying = true);

    try {
      if (_isPasswordReset) {
        if (!mounted) return;
        setState(() => _isVerifying = false);
        _showError('Password reset is not available yet.');
        return;
      }

      await AuthService.verifyEmailOTP(email: _tempEmail!, token: otp);

      if (!mounted) return;
      setState(() => _isVerifying = false);
      _showSuccessVerificationDialog();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isVerifying = false);

      String errorMessage = e.toString();
      if (errorMessage.startsWith('Exception: ')) {
        errorMessage = errorMessage.substring(11);
      }

      if (errorMessage.contains('Invalid token')) {
        errorMessage = 'Invalid verification code. Please try again.';
        for (final controller in _otpControllers) {
          controller.clear();
        }
        setState(() => _otpComplete = false);
        _otpFocusNodes[0].requestFocus();
      } else if (errorMessage.contains('Expired')) {
        errorMessage = 'This code has expired. Please request a new one.';
      }

      _showError(errorMessage);
    }
  }

  void _showSuccessVerificationDialog() {
    SuccessDialog.show(
      context,
      title: 'Email Verified!',
      message:
          'Your email has been successfully verified.\nYou can now log in to your account.',
      buttonText: 'Continue to Login',
      onButtonPressed: () {
        Navigator.pop(context);
        Navigator.pop(context);
      },
    );
  }

  Future<void> _resendOtp() async {
    if (_tempEmail == null) return;
    setState(() => _isSubmitting = true);

    try {
      await AuthService.resendVerificationCode(email: _tempEmail!);
      if (!mounted) return;

      for (final controller in _otpControllers) {
        controller.clear();
      }
      setState(() {
        _isSubmitting = false;
        _otpComplete = false;
      });
      _otpFocusNodes[0].requestFocus();
      _showInfoSnackBar('New verification code sent.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showError('Error resending code: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // OTP screen — logic unchanged, UI centered
  // ─────────────────────────────────────────────────────────────
  Widget _buildOtpScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Verify Email',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () {
            for (final controller in _otpControllers) {
              controller.clear();
            }
            setState(() {
              _showOtpScreen = false;
              _otpComplete = false;
            });
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.email_outlined,
                      size: 68, color: Color(0xFF2563EB)),
                  const SizedBox(height: 20),
                  const Text(
                    'Check Your Email',
                    textAlign: TextAlign.center,  
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E3A8A),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('We sent a verification code to',
                   textAlign: TextAlign.center,   
                      style: TextStyle(fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text(
                    _tempEmail ?? '',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(6, (index) {
                      return SizedBox(
                        width: 42,
                        height: 54,
                        child: TextField(
                          controller: _otpControllers[index],
                          focusNode: _otpFocusNodes[index],
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: 1,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w700),
                          decoration: InputDecoration(
                            counterText: '',
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            contentPadding: EdgeInsets.zero,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                  color: Color(0xFFE2E8F0)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                  color: Color(0xFFE2E8F0)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                  color: Color(0xFF2563EB), width: 2),
                            ),
                          ),
                          onChanged: (value) => _onOtpChanged(value, index),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      onPressed:
                          (_isVerifying || !_otpComplete) ? null : _verifyOtp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3C83F6),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFF93B4F8),
                        disabledForegroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: _isVerifying
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text(
                              'Verify Code',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "Didn't receive it?",
                        style: TextStyle(
                            color: Color(0xFF64748B), fontSize: 13),
                      ),
                      TextButton(
                        onPressed: _isSubmitting ? null : _resendOtp,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Text(
                                'Resend',
                                style: TextStyle(
                                  color: Color(0xFF2563EB),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showOtpScreen) return _buildOtpScreen();

    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 768;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: isMobile
            ? _buildMobileLayout(context)
            : _buildWebLayout(context),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // WEB — centered card, two-column split
  // ─────────────────────────────────────────────────────────────
  Widget _buildWebLayout(BuildContext context) {
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
          // ── Left panel ────────────────────────────────────────
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
                    width: 200,
                    height: 170,
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

          // ── Right panel (form) ────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: _buildForm(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // MOBILE — stacked, single-column
  // ─────────────────────────────────────────────────────────────
Widget _buildMobileLayout(BuildContext context) {
  return Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: _buildForm(),
      ),
    ),
  );
}

  // ─────────────────────────────────────────────────────────────
  // Shared form
  // ─────────────────────────────────────────────────────────────
  Widget _buildForm() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      const Center(
        child: Text(
          'Create an account',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Center(
        child: Wrap(
          alignment: WrapAlignment.center,
          children: [
            const Text(
              'Already have an account? ',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
            ),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Text(
                'Log in',
                style: TextStyle(
                  color: Color(0xFF2563EB),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 28),

      _buildStepIndicator(),
      const SizedBox(height: 28),

      AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: _currentStep == 0
            ? _buildPharmacyStepFields(key: const ValueKey('step1'))
            : _buildAdminStepFields(key: const ValueKey('step2')),
      ),
      const SizedBox(height: 28),

      _buildStepNavButtons(height: 52),
    ],
  );
}

  // ─────────────────────────────────────────────────────────────
  // Step indicator
  // ─────────────────────────────────────────────────────────────
Widget _buildStepIndicator() {
  const labels = ['Pharmacy Info', 'Admin Setup'];

  return Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: const Color(0xFFF1F4F9),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      children: List.generate(2, (index) {
        final active = _currentStep == index;
        return Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: active ? const Color(0xFF2563EB) : Colors.transparent,
              borderRadius: BorderRadius.circular(26),
            ),
            child: Text(
              labels[index],
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : const Color(0xFF94A3B8),
              ),
            ),
          ),
        );
      }),
    ),
  );
}

  Widget _stepBadge(int number, String label, bool active, bool completed) {
    final circleColor =
        active || completed ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0);
    final textColor =
        active ? const Color(0xFF1E3A8A) : const Color(0xFF94A3B8);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active || completed
                ? const Color(0xFF2563EB)
                : Colors.white,
            border: Border.all(color: circleColor, width: 2),
            shape: BoxShape.circle,
          ),
          child: completed
              ? const Icon(Icons.check, size: 13, color: Colors.white)
              : Text(
                  '$number',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : const Color(0xFF94A3B8),
                  ),
                ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Step 1 fields
  // ─────────────────────────────────────────────────────────────
  Widget _buildPharmacyStepFields({Key? key}) {
  return Column(
    key: key,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _labeledField(
        label: 'Pharmacy Name',
        controller: pharmacyNameController,
        hint: 'e.g. Sloane Pharmacy',
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 18),
      _labeledField(
        label: 'Pharmacy Address',
        controller: addressController,
        hint: 'Street, city, province',
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 18),
      _fieldLabel('Pharmacy Type'),
      DropdownButtonFormField<String>(
        value: pharmacyType,
        isDense: true,
        decoration: pillDecoration().copyWith(
          hintText: null,
        ),
        items: const [
          DropdownMenuItem(
              value: 'Retail Pharmacy', child: Text('Retail Pharmacy')),
          DropdownMenuItem(
              value: 'Hospital Pharmacy', child: Text('Hospital Pharmacy')),
        ],
        onChanged: (value) {
          if (value == null) return;
          setState(() => pharmacyType = value);
        },
      ),
    ],
  );
}
  // ─────────────────────────────────────────────────────────────
  // Step 2 fields
  // ─────────────────────────────────────────────────────────────
  Widget _buildAdminStepFields({Key? key}) {
  return Column(
    key: key,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _labeledField(
        label: 'Username',
        controller: usernameController,
        hint: 'Choose a username',
        textInputAction: TextInputAction.next,
        errorText: _usernameError,
        onChanged: _validateUsername,
      ),
      const SizedBox(height: 18),
      _labeledField(
        label: 'Full Name',
        controller: fullnameController,
        hint: 'Your full name',
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 18),
      _labeledField(
        label: 'Email',
        controller: emailController,
        hint: 'you@example.com',
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        errorText: _emailError,
        onChanged: _validateEmail,
      ),
      const SizedBox(height: 18),
      _labeledField(
        label: 'Password',
        controller: passwordController,
        hint: 'At least 8 characters',
        obscureText: obscurePassword,
        textInputAction: TextInputAction.next,
        errorText: _passwordError,
        onChanged: _validatePassword,
        suffixIcon: IconButton(
          icon: Icon(
            obscurePassword
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            size: 18,
            color: const Color(0xFF94A3B8),
          ),
          onPressed: () => setState(() => obscurePassword = !obscurePassword),
        ),
      ),
      const SizedBox(height: 18),
      _labeledField(
        label: 'Confirm Password',
        controller: confirmPasswordController,
        hint: 'Re-enter your password',
        obscureText: obscureConfirmPassword,
        textInputAction: TextInputAction.done,
        suffixIcon: IconButton(
          icon: Icon(
            obscureConfirmPassword
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            size: 18,
            color: const Color(0xFF94A3B8),
          ),
          onPressed: () => setState(
              () => obscureConfirmPassword = !obscureConfirmPassword),
        ),
      ),
    ],
  );
}

  // ─────────────────────────────────────────────────────────────
  // Buttons
  // ─────────────────────────────────────────────────────────────
  Widget _buildStepNavButtons({required double height}) {
  if (_currentStep == 0) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: ElevatedButton(
        onPressed: _goToNextStep,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2563EB),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30)),
          elevation: 0,
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Continue',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            SizedBox(width: 8),
            Icon(Icons.arrow_forward, size: 18),
          ],
        ),
      ),
    );
  }

  return Row(
    children: [
      const SizedBox(width: 10),
      Expanded(
        child: SizedBox(
          height: height,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _createAccount,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30)),
              elevation: 0,
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Create account',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    ],
  );
}
}