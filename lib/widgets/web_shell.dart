import 'package:flutter/material.dart';
import '../screens/dashboard.dart';
import '../screens/inventory.dart';
import '../screens/notifications.dart';
import '../screens/reports.dart';
import '../screens/settings.dart';
import '../screens/login.dart';
import '../screens/staff_management.dart';
import '../services/session_service.dart';
import '../services/supabase_service.dart';
import '../services/account_service.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/theme_service.dart';

const webPrimaryBlue = Color(0xFF3C83F6);

// Below this content width, the sidebar switches from a permanent
// fixed/collapsible column to a hidden-by-default drawer that
// overlays the content on a dimmed backdrop when toggled open.
const double _kDrawerBreakpoint = 1024;

class WebShell extends StatefulWidget {
  final String activeRoute;
  final String? activeSubRoute;
  final Widget child;
  final Widget? headerBar;
  final String? photoUrl;
  final String? displayName;

  const WebShell({
    super.key,
    required this.activeRoute,
    this.activeSubRoute,
    required this.child,
    this.headerBar,
    this.photoUrl,
    this.displayName,
  });

  /// Session-scoped cache of the admin role. Once resolved by any
  /// WebShell instance, subsequent mounts read this synchronously so
  /// the Staff Management nav item doesn't flicker in and out on
  /// every navigation. Cleared on logout.
  static bool? cachedIsAdmin;

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> {
  bool _isCollapsed = false;
  // Drawer-mode open/closed state (narrow widths only). Sidebar
  // starts hidden off-screen; toggled via the top bar's menu icon.
  bool _isDrawerOpen = false;
  bool _hasUnreadNotifications = false;
  bool? _isAdmin;

  // Settings sub-menu (Profile / Pharmacy / Security) expand state.
  // Starts open whenever Settings is the active page so the current
  // sub-section is visible without an extra tap.
  late bool _settingsExpanded;

  @override
  void initState() {
    super.initState();
    _settingsExpanded = widget.activeRoute == 'settings';
    // Seed synchronously from the session cache so the Staff
    // Management nav item is present on frame 1 whenever we already
    // know the role. Only hit the network on a cold cache.
    _isAdmin = WebShell.cachedIsAdmin;
    _checkUnreadNotifications();
    if (_isAdmin == null) {
      _loadRole();
    }
  }

  Future<void> _checkUnreadNotifications() async {
    final hasUnread = await SupabaseService.hasUnreadNotifications();
    if (mounted) {
      setState(() => _hasUnreadNotifications = hasUnread);
    }
  }

  Future<void> _loadRole() async {
    try {
      final email = await SessionService.email;
      if (email == null) {
        WebShell.cachedIsAdmin = false;
        if (mounted) setState(() => _isAdmin = false);
        return;
      }
      final isAdmin = await AccountService.isAdmin(email);
      WebShell.cachedIsAdmin = isAdmin;
      if (mounted) setState(() => _isAdmin = isAdmin);
    } catch (e) {
      debugPrint('WebShell role check failed: $e');
      WebShell.cachedIsAdmin = false;
      if (mounted) setState(() => _isAdmin = false);
    }
  }

  void _go(BuildContext context, String route) {
    // Always close the drawer on a nav tap, even if we're already on
    // that route (user tapped the current page's item to dismiss).
    if (_isDrawerOpen) {
      setState(() => _isDrawerOpen = false);
    }

    if (route == widget.activeRoute) return;
    if (route == 'staff' && _isAdmin != true) return;

    Widget destination;
    switch (route) {
      case 'dashboard':
        destination = const Dashboard();
        break;
      case 'inventory':
        destination = const InventoryScreen();
        break;
      case 'notifications':
        destination = const NotificationsScreen();
        break;
      case 'reports':
        destination = const ReportsScreen();
        break;
      case 'staff':
        destination = const StaffManagementScreen();
        break;
      case 'settings':
        destination = const SettingsScreen();
        break;
      default:
        return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => destination),
    );
  }

  // Navigates straight to a specific Settings sub-tab (Profile /
  // Pharmacy / Security), used by the sidebar's Settings sub-items.
  // Unlike _go, this always navigates even if Settings is already
  // the active route, since the sub-tab itself may be changing.
  void _goSettingsTab(BuildContext context, int tabIndex) {
    if (_isDrawerOpen) {
      setState(() => _isDrawerOpen = false);
    }
    SettingsScreen.initialTab = tabIndex;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  static const double _navIconSize = 24;
  static const double _navFontSize = 14;

  Widget _navItem(
    BuildContext context,
    String route,
    String label,
    IconData icon, {
    bool collapsed = false,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    final selected = route == widget.activeRoute;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final selectedColor = const Color(0xFF3C83F6);
    final unselectedColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    final content = InkWell(
      onTap: onTap ?? () => _go(context, route),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: EdgeInsets.symmetric(
          horizontal: collapsed ? 8 : 16,
          vertical: 4,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: collapsed ? 0 : 16,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF3C83F6).withValues(alpha: .10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: collapsed
            ? Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    icon,
                    size: _navIconSize,
                    color: selected ? selectedColor : unselectedColor,
                  ),
                  if (trailing != null)
                    Positioned(right: 0, top: 0, child: trailing),
                ],
              )
            : Row(
                children: [
                  Icon(
                    icon,
                    size: _navIconSize,
                    color: selected ? selectedColor : unselectedColor,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: selected ? selectedColor : unselectedColor,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        fontSize: _navFontSize,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing,
                ],
              ),
      ),
    );

    return collapsed ? Tooltip(message: label, child: content) : content;
  }

  // A smaller, indented nav row for a Settings sub-page (Profile,
  // Pharmacy, Security). Highlighted when it's the active sub-route
  // and Settings is the active page. Uses a smaller icon than the
  // parent items (18 vs 24) so the indent reads as a nested level.
  Widget _settingsSubItem(
  BuildContext context,
  String label,
  String subRoute,
  IconData icon,
  int tabIndex,
) {
  final selected =
      widget.activeRoute == 'settings' && widget.activeSubRoute == subRoute;
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final selectedColor = const Color(0xFF3C83F6);
  final unselectedColor = isDark
      ? const Color(0xFF94A3B8)
      : const Color(0xFF64748B);

  return InkWell(
    onTap: () => _goSettingsTab(context, tabIndex),
    borderRadius: BorderRadius.circular(10),
    child: Container(
      margin: const EdgeInsets.only(left: 44, right: 16, bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xFF3C83F6).withValues(alpha: .10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: _navIconSize,
            color: selected ? selectedColor : unselectedColor,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? selectedColor : unselectedColor,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                fontSize: _navFontSize,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

  Future<void> _logout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      WebShell.cachedIsAdmin = null;
      await SessionService.clear();
      if (!context.mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const Login()),
        (route) => false,
      );
    }
  }

  String _initialsFor(String? name) {
    if (name == null || name.trim().isEmpty) return 'AC';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  // ─────────────────────────────────────────────────────────────────
  // Sidebar content — shared between the fixed column (wide) and the
  // drawer panel (narrow). `collapsed` only ever applies in the fixed
  // layout; the drawer is always shown expanded (it has the space).
  // ─────────────────────────────────────────────────────────────────
  Widget _sidebarContent(BuildContext context, {required bool collapsed}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sidebarBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 12, 20),
          child: Row(
            mainAxisAlignment: collapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.spaceBetween,
            children: [
              if (!collapsed)
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        'assets/icon/icon.png',
                        width: 32,
                        height: 32,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFF3C83F6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.monitor_heart_outlined,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'MediScan',
                      style: TextStyle(
                        fontFamily: 'Gugi',
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: webPrimaryBlue,
                      ),
                    ),
                  ],
                )
              else
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/icon/icon.png',
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3C83F6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.monitor_heart_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              if (!collapsed && _showCollapseToggle)
                IconButton(
                  icon: const Icon(
                    Icons.menu_open,
                    color: Color(0xFF94A3B8),
                    size: 22,
                  ),
                  tooltip: 'Collapse sidebar',
                  onPressed: () => setState(() => _isCollapsed = true),
                ),
            ],
          ),
        ),

        if (collapsed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Center(
              child: IconButton(
                icon: const Icon(
                  Icons.menu,
                  color: Color(0xFF94A3B8),
                  size: 22,
                ),
                tooltip: 'Expand sidebar',
                onPressed: () => setState(() => _isCollapsed = false),
              ),
            ),
          ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _navItem(
                  context,
                  'dashboard',
                  'Dashboard',
                  Icons.dashboard_outlined,
                  collapsed: collapsed,
                ),
                _navItem(
                  context,
                  'inventory',
                  'Inventory',
                  Icons.inventory_2_outlined,
                  collapsed: collapsed,
                ),
                _navItem(
                  context,
                  'notifications',
                  'Notifications',
                  Icons.notifications_none,
                  collapsed: collapsed,
                  trailing: _hasUnreadNotifications
                      ? Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        )
                      : null,
                ),
                _navItem(
                  context,
                  'reports',
                  'Reports',
                  Icons.bar_chart_outlined,
                  collapsed: collapsed,
                ),
                if (_isAdmin == true)
                  _navItem(
                    context,
                    'staff',
                    'Staff Management',
                    Icons.groups_outlined,
                    collapsed: collapsed,
                  ),

                // Settings — a normal nav item when collapsed (icon
                // only, no room for a sub-menu); expandable with
                // Profile / Pharmacy / Security sub-items otherwise.
                if (collapsed)
                  _navItem(
                    context,
                    'settings',
                    'Settings',
                    Icons.settings_outlined,
                    collapsed: true,
                  )
                else ...[
                  _navItem(
                    context,
                    'settings',
                    'Settings',
                    Icons.settings_outlined,
                    collapsed: false,
                    onTap: () {
                      if (widget.activeRoute == 'settings') {
                        setState(() => _settingsExpanded = !_settingsExpanded);
                      } else {
                        setState(() => _settingsExpanded = true);
                        _go(context, 'settings');
                      }
                    },
                    trailing: Icon(
                      _settingsExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 18,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                  ),
                  if (_settingsExpanded) ...[
                    _settingsSubItem(
                      context,
                      'Profile',
                      'profile',
                      Icons.person_outline,
                      0,
                    ),
                    if (_isAdmin == true)
                      _settingsSubItem(
                        context,
                        'Pharmacy',
                        'pharmacy',
                        Icons.storefront_outlined,
                        1,
                      ),
                    _settingsSubItem(
                      context,
                      'Security',
                      'security',
                      Icons.shield_outlined,
                      2,
                    ),
                    const SizedBox(height: 4),
                  ],
                ],
              ],
            ),
          ),
        ),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            children: [
              Divider(height: 1, color: borderColor),
              const SizedBox(height: 12),
              InkWell(
                onTap: () => _logout(context),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: collapsed ? 0 : 16,
                    vertical: 12,
                  ),
                  child: collapsed
                      ? const Center(
                          child: Tooltip(
                            message: 'Logout',
                            child: Icon(
                              Icons.logout,
                              size: 24,
                              color: Color(0xFFEF4444),
                            ),
                          ),
                        )
                      : Row(
                          children: [
                            const Icon(
                              Icons.logout,
                              size: 24,
                              color: Color(0xFFEF4444),
                            ),
                            const SizedBox(width: 14),
                            const Text(
                              'Logout',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFFEF4444),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }

  bool _showCollapseToggle = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sidebarBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final mainBg = theme.scaffoldBackgroundColor;

    final width = MediaQuery.of(context).size.width;
    final isNarrow = width < _kDrawerBreakpoint;

    final iconColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    final mainColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Narrow top bar ──
        // Row 1: menu + logo + "MediScan" + theme/bell/avatar — all inline.
        // The headerBar supplied by each screen is NOT rendered here; a
        // full WebTopBar can't be placed inside an unbounded Row without
        // crashing layout. The narrow shell owns its own compact header.
        if (isNarrow)
          Container(
            decoration: BoxDecoration(
              color: sidebarBg,
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
                child: SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.menu, size: 22),
                        tooltip: 'Open menu',
                        onPressed: () =>
                            setState(() => _isDrawerOpen = true),
                      ),
                      const SizedBox(width: 2),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.asset(
                          'assets/icon/icon.png',
                          width: 26,
                          height: 26,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: const Color(0xFF3C83F6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'MediScan',
                        style: TextStyle(
                          fontFamily: 'Gugi',
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: webPrimaryBlue,
                        ),
                      ),
                      const Spacer(),
                      // Theme toggle
                      ValueListenableBuilder<ThemeMode>(
                        valueListenable: themeModeNotifier,
                        builder: (context, _, __) {
                          final dark = ThemeService.isDark(context);
                          return IconButton(
                            tooltip: dark
                                ? 'Switch to light mode'
                                : 'Switch to dark mode',
                            onPressed: () => ThemeService.toggle(context),
                            icon: SvgPicture.string(
                              dark ? _svgSun : _svgMoon,
                              width: 22,
                              height: 22,
                              color: dark
                                  ? const Color(0xFFE2E8F0)
                                  : const Color(0xFF64748B),
                            ),
                          );
                        },
                      ),
                      // Bell
                      Stack(
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.notifications_none,
                              size: 24,
                              color: iconColor,
                            ),
                            onPressed: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const NotificationsScreen(),
                                ),
                              );
                              _checkUnreadNotifications();
                            },
                          ),
                          if (_hasUnreadNotifications)
                            Positioned(
                              right: 8,
                              top: 8,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                      // Avatar
                      PopupMenuButton<String>(
                        tooltip: 'Account',
                        offset: const Offset(0, 56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onSelected: (value) async {
                          if (value == 'profile') {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const SettingsScreen(),
                              ),
                            );
                          } else if (value == 'logout') {
                            await _logout(context);
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'profile',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.person_outline,
                                  size: 20,
                                  color: Color(0xFF64748B),
                                ),
                                SizedBox(width: 12),
                                Text('Profile'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'logout',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.logout,
                                  size: 20,
                                  color: Colors.red,
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'Logout',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                        ],
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: const Color(0xFF3C83F6),
                          backgroundImage:
                              widget.photoUrl != null &&
                                      widget.photoUrl!.isNotEmpty
                                  ? NetworkImage(widget.photoUrl!)
                                  : null,
                          child: widget.photoUrl == null ||
                                  widget.photoUrl!.isEmpty
                              ? Text(
                                  _initialsFor(widget.displayName),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else if (widget.headerBar != null)
          SizedBox(
            height: 96,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 8),
              child: widget.headerBar!,
            ),
          ),

        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              isNarrow ? 16 : 32,
              0,
              isNarrow ? 16 : 32,
              32,
            ),
            child: widget.child,
          ),
        ),
      ],
    );

    if (!isNarrow) {
      // ── Wide layout: fixed/collapsible sidebar as a flex sibling ──
      _showCollapseToggle = true;
      return Scaffold(
        backgroundColor: mainBg,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: _isCollapsed ? 76 : 260,
              color: sidebarBg,
              child: _sidebarContent(context, collapsed: _isCollapsed),
            ),
            Expanded(child: mainColumn),
          ],
        ),
      );
    }

    // ── Narrow layout: drawer overlays content on a dimmed backdrop ──
    _showCollapseToggle = false;
    return Scaffold(
      backgroundColor: mainBg,
      body: Stack(
        children: [
          mainColumn,

          if (_isDrawerOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _isDrawerOpen = false),
                child: Container(color: Colors.black.withValues(alpha: 0.45)),
              ),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              width: 260,
              child: Material(
                color: sidebarBg,
                child: SafeArea(
                  child: _sidebarContent(context, collapsed: false),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Top bar — title on the left, icons on the right.
// Rendered by screens only in wide mode; the narrow shell draws its
// own compact header inline.
// ─────────────────────────────────────────────────────────────────
class WebTopBar extends StatefulWidget {
  final String searchHint;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onBellTap;
  final String initials;
  final bool hasUnread;
  final String? photoUrl;
  final String? displayName;
  final String? roleLabel;
  final bool showSearch;
  final TextEditingController? searchController;
  final String? pageTitle;
  final String? pageSubtitle;

  const WebTopBar({
    super.key,
    this.searchHint = 'Search...',
    this.onSearchChanged,
    this.onBellTap,
    this.hasUnread = false,
    this.initials = 'AC',
    this.photoUrl,
    this.displayName,
    this.roleLabel,
    this.showSearch = false,
    this.searchController,
    this.pageTitle,
    this.pageSubtitle,
  });

  @override
  State<WebTopBar> createState() => _WebTopBarState();
}

class _WebTopBarState extends State<WebTopBar> {
  late bool _hasUnread;

  @override
  void initState() {
    super.initState();
    _hasUnread = widget.hasUnread;
    _loadUnread();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadUnread());
  }

  Future<void> _loadUnread() async {
    final unread = await SupabaseService.hasUnreadNotifications();
    if (!mounted) return;
    setState(() => _hasUnread = unread);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark
        ? const Color(0xFFF1F5F9)
        : const Color(0xFF0F172A);
    final subTextColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    final iconBg = isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ── Page Title ──
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.pageTitle != null)
                Text(
                  widget.pageTitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                    height: 1.15,
                  ),
                ),
              if (widget.pageSubtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  widget.pageSubtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: subTextColor,
                    height: 1.2,
                  ),
                ),
              ],
            ],
          ),
        ),

        // ── Centered Search (optional) ──
        if (widget.showSearch)
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 390),
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: widget.searchController,
                    onChanged: widget.onSearchChanged,
                    style: TextStyle(color: textColor, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: widget.searchHint,
                      hintStyle: TextStyle(color: subTextColor, fontSize: 14),
                      prefixIcon: Icon(
                        Icons.search,
                        size: 21,
                        color: subTextColor,
                      ),
                      filled: true,
                      fillColor: iconBg,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 0,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: Color(0xFF3C83F6),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          )
        else
          const Spacer(),

        // ── Right icon group: theme toggle, bell, avatar ──
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Theme toggle
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: themeModeNotifier,
                  builder: (context, _, __) {
                    final dark = ThemeService.isDark(context);

                    return IconButton(
                      tooltip: dark
                          ? 'Switch to light mode'
                          : 'Switch to dark mode',
                      onPressed: () => ThemeService.toggle(context),
                      icon: SvgPicture.string(
                        dark ? _svgSun : _svgMoon,
                        width: 22,
                        height: 22,
                        color: dark
                            ? const Color(0xFFE2E8F0)
                            : const Color(0xFF64748B),
                      ),
                    );
                  },
                ),

                const SizedBox(width: 4),

                // Bell
                Stack(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.notifications_none,
                        size: 24,
                        color: subTextColor,
                      ),
                      onPressed: () async {
                        if (widget.onBellTap != null) {
                          widget.onBellTap!();
                        } else {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const NotificationsScreen(),
                            ),
                          );
                          _loadUnread();
                        }
                      },
                    ),
                    if (_hasUnread)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(width: 4),

                // Avatar + name/role
                PopupMenuButton<String>(
                  tooltip: 'Account',
                  offset: const Offset(0, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onSelected: (value) =>
                      _handleProfileSelection(context, value),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'profile',
                      child: Row(
                        children: [
                          Icon(
                            Icons.person_outline,
                            size: 20,
                            color: Color(0xFF64748B),
                          ),
                          SizedBox(width: 12),
                          Text('Profile'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'logout',
                      child: Row(
                        children: [
                          Icon(
                            Icons.logout,
                            size: 20,
                            color: Colors.red,
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Logout',
                            style: TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ],
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: const Color(0xFF3C83F6),
                        backgroundImage:
                            widget.photoUrl != null &&
                                    widget.photoUrl!.isNotEmpty
                                ? NetworkImage(widget.photoUrl!)
                                : null,
                        child: widget.photoUrl == null ||
                                widget.photoUrl!.isEmpty
                            ? Text(
                                widget.initials,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              widget.displayName ?? 'Account',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (widget.roleLabel != null &&
                                widget.roleLabel!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                widget.roleLabel!,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: subTextColor,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleProfileSelection(
    BuildContext context,
    String value,
  ) async {
    switch (value) {
      case 'profile':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
        break;
      case 'logout':
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Log out'),
            content: const Text('Are you sure you want to log out?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Log out'),
              ),
            ],
          ),
        );
        if (confirm == true) {
          WebShell.cachedIsAdmin = null;
          await SessionService.clear();
          if (!context.mounted) return;
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const Login()),
            (route) => false,
          );
        }
        break;
    }
  }
}

const String _svgMoon =
    '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><rect width="256" height="256" fill="none"/><path d="M235.54,150.21a104.84,104.84,0,0,1-37,52.91A104,104,0,0,1,32,120,103.09,103.09,0,0,1,52.88,57.48a104.84,104.84,0,0,1,52.91-37,8,8,0,0,1,10,10,88.08,88.08,0,0,0,109.8,109.8,8,8,0,0,1,10,10Z"/></svg>''';

const String _svgSun =
    '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><rect width="256" height="256" fill="none"/><path d="M120,40V16a8,8,0,0,1,16,0V40a8,8,0,0,1-16,0Zm8,24a64,64,0,1,0,64,64A64.07,64.07,0,0,0,128,64ZM58.34,69.66A8,8,0,0,0,69.66,58.34l-16-16A8,8,0,0,0,42.34,53.66Zm0,116.68-16,16a8,8,0,0,0,11.32,11.32l16-16a8,8,0,0,0-11.32-11.32ZM192,72a8,8,0,0,0,5.66-2.34l16-16a8,8,0,0,0-11.32-11.32l-16,16A8,8,0,0,0,192,72Zm5.66,114.34a8,8,0,0,0-11.32,11.32l16,16a8,8,0,0,0,11.32-11.32ZM48,128a8,8,0,0,0-8-8H16a8,8,0,0,0,0,16H40A8,8,0,0,0,48,128Zm80,80a8,8,0,0,0-8,8v24a8,8,0,0,0,16,0V216A8,8,0,0,0,128,208Zm112-88H216a8,8,0,0,0,0,16h24a8,8,0,0,0,0-16Z"/></svg>''';