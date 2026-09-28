import 'package:flutter/material.dart';

/// MediScan's branded loading indicator: a thick blue ring using the app's
/// brand color instead of the default thin grey CircularProgressIndicator.
class BrandedLoader extends StatelessWidget {
  final double size;

  const BrandedLoader({super.key, this.size = 56});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: size * 0.09,
        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF3C83F6)),
        backgroundColor: const Color(0xFFE6F1FB),
      ),
    );
  }
}

/// Convenience widget for a centered [BrandedLoader] with an optional
/// caption underneath. Use this in place of
/// `Center(child: CircularProgressIndicator())` for full-page or
/// full-section loading states.
class BrandedLoading extends StatelessWidget {
  final String? label;
  final double size;

  const BrandedLoading({super.key, this.label, this.size = 56});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BrandedLoader(size: size),
          if (label != null) ...[
            const SizedBox(height: 14),
            Text(
              label!,
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}


