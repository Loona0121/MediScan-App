import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Centered success popup — Lottie checkmark plays in, then a title + message
/// + single action button. Pulled out of SignUpScreen's email-verification
/// dialog so every "X succeeded" moment in the app (report export, item
/// saved, item deleted, etc.) can use the same look instead of a bottom
/// SnackBar.
class SuccessDialog extends StatelessWidget {
  final String title;
  final String message;
  final String buttonText;
  final VoidCallback? onButtonPressed;

  const SuccessDialog({
    super.key,
    this.title = 'Success!',
    required this.message,
    this.buttonText = 'OK',
    this.onButtonPressed,
  });

  /// Convenience call site — e.g.
  /// `SuccessDialog.show(context, message: 'Report exported successfully!');`
  static Future<void> show(
    BuildContext context, {
    String title = 'Success!',
    required String message,
    String buttonText = 'OK',
    VoidCallback? onButtonPressed,
    bool barrierDismissible = false,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (_) => SuccessDialog(
        title: title,
        message: message,
        buttonText: buttonText,
        onButtonPressed: onButtonPressed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Lottie animation replaces the old static checkmark.
              SizedBox(
                width: 140,
                height: 140,
                child: Lottie.asset(
                  'assets/animations/success_check.json',
                  fit: BoxFit.contain,
                  repeat: false,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E3A8A),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: onButtonPressed ?? () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3C83F6),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    buttonText,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}