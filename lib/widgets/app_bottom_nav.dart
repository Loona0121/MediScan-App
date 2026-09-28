import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../screens/dashboard.dart';
import '../screens/inventory.dart';
import '../screens/settings.dart';
import '../screens/scan.dart';
import '../utils/app_palette.dart';

const Color _accentColor = Color(0xFF3C83F6);

class AppBottomNav extends StatelessWidget {
  final int currentIndex;

  const AppBottomNav({super.key, required this.currentIndex});

  Future<void> _onTap(BuildContext context, int index) async {
    if (index == currentIndex) return;

    Widget destination;
    switch (index) {
      case 0:
        destination = const Dashboard();
        break;
      case 1:
        destination = const ScanScreen();
        break;
      case 2:
        destination = const InventoryScreen();
        break;
      case 3:
        destination = const SettingsScreen();
        break;
      default:
        return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => destination),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette(isDark);

    // ── Dark-mode-aware navbar colors ──
    // Light mode: stays as it was (white pill, soft shadow).
    // Dark mode:  uses the app card color + subtle border so the bar
    //             blends into the rest of the dark UI.
    final navBg = isDark ? p.cardBg : Colors.white;
    final inactiveColor =
        isDark ? p.textSecondary : const Color(0xFF1E293B);
    final shadowColor =
        Colors.black.withValues(alpha: isDark ? 0.35 : 0.08);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          height: 76,
          decoration: BoxDecoration(
            color: navBg,
            borderRadius: BorderRadius.circular(28),
            border: isDark ? Border.all(color: p.cardBorder) : null,
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _NavItem(
                svgAsset: 'assets/icon/home.svg',
                label: 'Dashboard',
                selected: currentIndex == 0,
                inactiveColor: inactiveColor,
                onTap: () => _onTap(context, 0),
              ),
              _NavItem(
                svgAsset: 'assets/icon/scan.svg',
                label: 'Scan',
                selected: currentIndex == 1,
                inactiveColor: inactiveColor,
                onTap: () => _onTap(context, 1),
              ),
              _NavItem(
                svgAsset: 'assets/icon/inventory.svg',
                label: 'Inventory',
                selected: currentIndex == 2,
                inactiveColor: inactiveColor,
                onTap: () => _onTap(context, 2),
              ),
              _NavItem(
                svgAsset: 'assets/icon/settings.svg',
                label: 'Settings',
                selected: currentIndex == 3,
                inactiveColor: inactiveColor,
                onTap: () => _onTap(context, 3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String svgAsset;
  final String label;
  final bool selected;
  final Color inactiveColor;
  final VoidCallback onTap;

  const _NavItem({
    required this.svgAsset,
    required this.label,
    required this.selected,
    required this.inactiveColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = selected ? Colors.white : inactiveColor;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: selected ? _accentColor : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: SvgPicture.asset(
                svgAsset,
                width: 24,
                height: 24,
                // Uniform tint: all four icons render at 24×24 and get
                // recolored to match the selected/unselected state.
                colorFilter: ColorFilter.mode(
                  iconColor,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? _accentColor : inactiveColor,
            ),
          ),
        ],
      ),
    );
  }
}