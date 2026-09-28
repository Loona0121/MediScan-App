import 'package:flutter/material.dart';

class AppToast {
  /// Shows a success message as a floating green banner
  /// anchored to the top-right of the screen.
  ///
  /// [width] should be roughly 3/4 of the screen width.
static void success(
  BuildContext context,
  String message, {
  double widthFraction = 0.25,   // 👈 1/4 instead of 3/4
}) {
  final media = MediaQuery.of(context);
  final width = media.size.width * widthFraction;

  ScaffoldMessenger.of(context).clearSnackBars();

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: const Color(0xFF16A34A),
      behavior: SnackBarBehavior.floating,
      // Center horizontally, pin near the top.
      margin: EdgeInsets.only(
        top: media.padding.top + 16,
        left: (media.size.width - width) / 2,
        right: (media.size.width - width) / 2,
        bottom: media.size.height - 100,
      ),
      width: width,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      duration: const Duration(seconds: 3),
      elevation: 4,
    ),
  );
}

  /// Optional: same banner but red for errors.
  static void error(
    BuildContext context,
    String message, {
    double widthFraction = 0.75,
  }) {
    final media = MediaQuery.of(context);
    final width = media.size.width * widthFraction;

    ScaffoldMessenger.of(context).clearSnackBars();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          top: media.padding.top + 16,
          right: media.size.width * (1 - widthFraction) - 8,
          bottom: media.size.height - 120,
        ),
        width: width,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        duration: const Duration(seconds: 3),
        elevation: 4,
      ),
    );
  }
}