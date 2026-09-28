import 'package:flutter/material.dart';

// ── Shared brand colors (k-prefixed to avoid name clashes) ──
const Color kPrimaryBlue   = Color(0xFF3C83F6);
const Color kSafeGreen     = Color(0xFF34D399);
const Color kWarningOrange = Color(0xFFFB923C);
const Color kDangerRed     = Color(0xFFF87171);
const Color kNeutralGray   = Color(0xFF94A3B8);

/// Shared theme-aware palette used across all web screens so light/dark
/// mode stays consistent.
class AppPalette {
  final bool isDark;
  const AppPalette(this.isDark);

  // Surfaces
  Color get scaffoldBg   => isDark ? const Color(0xFF0B1220) : const Color(0xFFF8FAFC);
  Color get appBarBg     => isDark ? const Color(0xFF1E293B) : Colors.white;
  Color get cardBg       => isDark ? const Color(0xFF1E293B) : Colors.white;
  Color get cardBorder   => isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  Color get rowDivider   => isDark ? const Color(0xFF273449) : const Color(0xFFF1F5F9);
  Color get searchBg     => isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);

  // Text
  Color get textPrimary   => isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
  Color get textSecondary => isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  Color get textMuted     => isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);

  // Chips / toggles
  Color get iconToggle     => isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B);
  Color get chipTrackBg    => isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);
  Color get chipSelectedBg => isDark ? const Color(0xFF334155) : Colors.white;

  // Misc
  Color get emptyIconBg     => isDark ? const Color(0xFF1E3A5F) : const Color(0xFFEFF6FF);
  Color get fallbackThumbBg => isDark ? const Color(0xFF1E3A5F) : const Color(0xFFEFF6FF);

  BoxDecoration get cardDecoration => BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      );
}