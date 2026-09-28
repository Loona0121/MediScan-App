import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/staff_service.dart';
import '../services/session_service.dart';
import '../services/account_service.dart';
import '../widgets/web_shell.dart';
import '../widgets/app_toast.dart';
import 'add_staff_dialog.dart';
import 'add_staff.dart';
import 'staff_detail.dart';
import '../utils/image_utils.dart';
import '../utils/app_palette.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class StaffManagementScreen extends StatefulWidget {
  const StaffManagementScreen({super.key});

  @override
  State<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen> {
  List<StaffMember> _staff = [];

  bool _isLoading = true;

  bool _isCheckingAccess = true;
  bool _isAdmin = false;

  String? _userPhotoUrl;
  String? _userDisplayName;
  String? _userRoleLabel;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<StaffMember> get _filteredStaff {
    if (_searchQuery.trim().isEmpty) return _staff;
    final q = _searchQuery.trim().toLowerCase();
    return _staff
        .where(
          (m) =>
              m.fullName.toLowerCase().contains(q) ||
              m.email.toLowerCase().contains(q) ||
              m.role.toLowerCase().contains(q),
        )
        .toList();
  }

  // =====================================================
  // CHECK ADMIN ACCESS
  // =====================================================

  Future<void> _checkAccess() async {
    try {
      final email = await SessionService.email;

      if (email == null || email.isEmpty) {
        if (mounted) {
          setState(() {
            _isAdmin = false;
            _isCheckingAccess = false;
          });
        }
        return;
      }

      final isAdmin = await AccountService.isAdmin(email);

      if (!mounted) return;

      setState(() {
        _isAdmin = isAdmin;
        _isCheckingAccess = false;
      });

      if (isAdmin) {
        await Future.wait([_load(), _loadUserProfile()]);
      }
    } catch (e) {
      debugPrint('Error checking admin access: $e');

      if (mounted) {
        setState(() {
          _isAdmin = false;
          _isCheckingAccess = false;
        });
      }
    }
  }

  // =====================================================
  // LOAD USER PROFILE
  // =====================================================

  Future<void> _loadUserProfile() async {
    try {
      final email = await SessionService.email;

      if (email != null) {
        final photoUrl = await AccountService.getPhotoUrl(email);
        final fullName = await AccountService.getFullName(email);
        final isAdmin = await AccountService.isAdmin(email);

        if (mounted) {
          setState(() {
            _userPhotoUrl = bustCache(photoUrl);
            _userDisplayName = fullName;
            _userRoleLabel = isAdmin ? 'Manager' : 'Staff';
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
  }

  // =====================================================
  // LOAD STAFF
  // =====================================================

  Future<void> _load() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final staff = await StaffService.fetchStaff();

      if (!mounted) return;

      setState(() {
        _staff = staff;
      });
    } catch (e) {
      debugPrint('Staff fetch error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // =====================================================
  // DELETE STAFF
  // =====================================================

  Future<void> _delete(StaffMember member) async {
    if (!_isAdmin) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Staff'),
        content: Text('Remove "${member.fullName}" from staff?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

if (confirm == true) {
  try {
    await StaffService.deleteStaff(member.id, email: member.email);
    await _load();
  } catch (e) {
    if (!mounted) return;
    AppToast.error(context, 'Failed to remove staff member: $e');
  }
}
  }

  // =====================================================
  // ADD STAFF
  // =====================================================

  Future<void> _goToAddStaff() async {
    if (!_isAdmin) return;

    final isWeb = MediaQuery.of(context).size.width >= 900;

    final bool? result;

    if (isWeb) {
      result = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (_) => const AddStaffDialog(),
      );
    } else {
      result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => AddStaffScreen()),
      );
    }

    if (result == true) {
      await _load();
      if (!mounted) return;
      AppToast.success(
        context,
        'Invite sent!',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette(isDark);

    final isWeb = kIsWeb;

    if (!isWeb && _isCheckingAccess) {
      return Scaffold(
        backgroundColor: p.scaffoldBg,
        body: const Center(
          child: CircularProgressIndicator(color: kPrimaryBlue),
        ),
      );
    }

    if (!isWeb && !_isAdmin) {
      return _buildAccessDenied(context);
    }

    if (isWeb) {
      return _buildWebLayout(context);
    }

    // =====================================================
    // MOBILE LAYOUT
    // =====================================================

    return Scaffold(
      backgroundColor: p.scaffoldBg,
      appBar: AppBar(
        backgroundColor: p.appBarBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kPrimaryBlue),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          'Staff Management (${_staff.length})',
          style: TextStyle(
            color: p.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _staff.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.groups_outlined, size: 48, color: p.textMuted),
                  const SizedBox(height: 12),
                  Text(
                    'No staff registered yet',
                    style: TextStyle(color: p.textSecondary),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: _staff.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final member = _staff[i];

                  return Dismissible(
                    key: Key(member.id.toString()),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      decoration: BoxDecoration(
                        color: Colors.red.shade400,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.delete_outline,
                        color: Colors.white,
                      ),
                    ),
                    confirmDismiss: (_) async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Remove Staff'),
                          content: Text(
                            'Remove "${member.fullName}" from staff?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                              child: const Text('Remove'),
                            ),
                          ],
                        ),
                      );
                      return confirm == true;
                    },
     onDismissed: (_) async {
  try {
    await StaffService.deleteStaff(
      member.id,
      email: member.email,
    );
    if (!mounted) return;
    setState(() {
      _staff.removeWhere((s) => s.id == member.id);
    });
  } catch (e) {
    debugPrint('Delete staff error: $e');
    if (!mounted) return;
    AppToast.error(
      context,
      'Failed to remove staff member: $e',
    );
  }
},
                    child: GestureDetector(
                      onTap: () async {
                        final result =
                            await StaffDetailDialog.show(context, member);
                        if (result == true) _load();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: p.cardBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: p.cardBorder),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: kPrimaryBlue,
                              backgroundImage:
                                  member.photoUrl != null &&
                                      member.photoUrl!.isNotEmpty
                                  ? NetworkImage(member.photoUrl!)
                                  : null,
                              child:
                                  member.photoUrl == null ||
                                      member.photoUrl!.isEmpty
                                  ? Text(
                                      member.fullName.isNotEmpty
                                          ? member.fullName[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    member.fullName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: p.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    member.role,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: p.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right, color: p.textMuted),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: FloatingActionButton.extended(
          onPressed: _goToAddStaff,
          backgroundColor: kPrimaryBlue,
          icon: const Icon(Icons.person_add_outlined, color: Colors.white),
          label: const Text('Add Staff', style: TextStyle(color: Colors.white)),
        ),
      ),
    );
  }

  Widget _buildAccessDenied(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette(isDark);

    return Scaffold(
      backgroundColor: p.scaffoldBg,
      appBar: AppBar(
        backgroundColor: p.appBarBg,
        surfaceTintColor: p.appBarBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kPrimaryBlue),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          'Access Restricted',
          style: TextStyle(
            color: p.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: p.emptyIconBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_outline,
                  size: 34,
                  color: kPrimaryBlue,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Access Restricted',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Only administrators can access Staff Management and manage staff accounts.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: p.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.maybePop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Go Back',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =====================================================
  // WEB LAYOUT
  // =====================================================

  Widget _buildWebLayout(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette(isDark);
    final filtered = _filteredStaff;

    // Add top spacing when WebShell is showing its own compact header
    // (narrow browser), matching Inventory / Reports / Dashboard.
    final isNarrowShell = MediaQuery.of(context).size.width < 1024;

    // Below this width, swap the wide table for a stacked-card layout
    // (same pattern the Inventory page uses). Above it, show the table.
    final wideContent = MediaQuery.of(context).size.width >= 900;

    return WebShell(
      activeRoute: 'staff',
      activeSubRoute: 'staff',
      photoUrl: _userPhotoUrl,
      displayName: _userDisplayName,
      headerBar: WebTopBar(
        pageTitle: 'Staff Management',
        pageSubtitle: 'Manage staff, roles, and system permissions.',
        photoUrl: _userPhotoUrl,
        displayName: _userDisplayName,
        roleLabel: _userRoleLabel,
        initials: _userDisplayName != null && _userDisplayName!.isNotEmpty
            ? _userDisplayName!
                .split(' ')
                .where((e) => e.isNotEmpty)
                .map((e) => e[0])
                .join('')
                .toUpperCase()
            : 'AC',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 👇 narrow-shell top spacer (matches Inventory / Reports / Dashboard)
          if (isNarrowShell) const SizedBox(height: 16),

          // =====================================================
          // SEARCH + ADD STAFF
          // =====================================================
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Container(
                  height: 44,
                  constraints: const BoxConstraints(maxWidth: 540),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: p.searchBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.cardBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search,
                        size: 20,
                        color: p.textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          style: TextStyle(
                            color: p.textPrimary,
                          ),
                          onChanged: (v) {
                            setState(() {
                              _searchQuery = v;
                            });
                          },
                          decoration: InputDecoration(
                            hintText: 'Search staff members...',
                            hintStyle: TextStyle(
                              fontSize: 14,
                              color: p.textSecondary,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _goToAddStaff,
                icon: const Icon(
                  Icons.add,
                  size: 19,
                ),
                label: const Text('Add Staff'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // =====================================================
          // SUMMARY CARDS (side by side)
          // =====================================================
          Row(
            children: [
              Expanded(
                child: _summaryCard(
                  p: p,
                  icon: SvgPicture.string(
                    '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256">
  <path d="M152,80a8,8,0,0,1,8-8h88a8,8,0,0,1,0,16H160A8,8,0,0,1,152,80Zm96,40H160a8,8,0,0,0,0,16h88a8,8,0,0,0,0-16Zm0,48H184a8,8,0,0,0,0,16h64a8,8,0,0,0,0-16ZM109.29,142a48,48,0,1,0-58.58,0c-20.62,8.73-36.87,26.3-42.46,48A8,8,0,0,0,16,200H144a8,8,0,0,0,7.75-10C146.16,168.29,129.91,150.72,109.29,142Z"/>
</svg>
''',
                    width: 20,
                    height: 20,
                    color: kPrimaryBlue,
                  ),
                  label: 'TOTAL STAFF',
                  value: '${_staff.length}',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _summaryCard(
                  p: p,
                  icon: SvgPicture.string(
                    '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256">
  <circle cx="128" cy="128" r="104" fill="#34D399"/>
</svg>
''',
                    width: 20,
                    height: 20,
                  ),
                  label: 'ACTIVE NOW',
                  value: '${_staff.length}',
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // =====================================================
          // PHARMACY TEAM
          // =====================================================
          Container(
            decoration: BoxDecoration(
              color: p.cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: p.cardBorder),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Pharmacy Team',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: p.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),

                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: Text(
                        _staff.isEmpty
                            ? 'No staff registered yet.'
                            : 'No staff match your search.',
                        style: TextStyle(color: p.textSecondary),
                      ),
                    ),
                  )
                else if (wideContent)
                  _buildWideTable(filtered, p, isDark)
                else
                  _buildNarrowList(filtered, p, isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Reusable summary card used by the TOTAL STAFF / ACTIVE NOW tiles.
  Widget _summaryCard({
    required AppPalette p,
    required Widget icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.cardBorder),
      ),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: p.textSecondary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: p.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // WIDE TABLE (>= 900px)
  // =====================================================

  Widget _buildWideTable(
    List<StaffMember> filtered,
    AppPalette p,
    bool isDark,
  ) {
    return Column(
      children: [
        // Header row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: p.cardBorder)),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Text('STAFF MEMBER', style: _webHeaderStyle(p)),
              ),
              Expanded(
                flex: 2,
                child: Text('ROLE', style: _webHeaderStyle(p)),
              ),
              Expanded(
                flex: 2,
                child: Text('STATUS', style: _webHeaderStyle(p)),
              ),
              SizedBox(
                width: 96,
                child: Text(
                  'ACTIONS',
                  style: _webHeaderStyle(p),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),

        // Rows
        ...filtered.map(
          (member) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.rowDivider)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Staff member (avatar + name + email)
                Expanded(
                  flex: 4,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: kPrimaryBlue,
                        backgroundImage:
                            member.photoUrl != null &&
                                    member.photoUrl!.isNotEmpty
                                ? NetworkImage(member.photoUrl!)
                                : null,
                        child: member.photoUrl == null ||
                                member.photoUrl!.isEmpty
                            ? Text(
                                member.fullName.isNotEmpty
                                    ? member.fullName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              member.fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: p.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              member.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: p.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Role
                Expanded(
                  flex: 2,
                  child: Text(
                    member.role,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.textPrimary),
                  ),
                ),

                // Status
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.circle,
                        size: 8,
                        color: kSafeGreen,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'ACTIVE',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? kSafeGreen
                              : const Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                ),

                // Actions
                SizedBox(
                  width: 96,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'Edit staff',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(
                          Icons.edit_outlined,
                          size: 18,
                          color: kPrimaryBlue,
                        ),
                        onPressed: () async {
                          final result = await StaffDetailDialog.show(
                            context,
                            member,
                          );
                          if (result == true) {
                            _load();
                          }
                        },
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        tooltip: 'Remove staff',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: Colors.red,
                        ),
                        onPressed: () => _delete(member),
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

  // =====================================================
  // NARROW LIST (< 900px) — stacked cards, no table
  // =====================================================

    // =====================================================
  // NARROW LIST (< 900px) — stacked cards, no table.
  // On phone-width web, the edit/delete icons and the ACTIVE
  // badge are hidden — tapping a card opens the detail dialog
  // instead, which offers both actions and role info.
  // =====================================================

  Widget _buildNarrowList(
    List<StaffMember> filtered,
    AppPalette p,
    bool isDark,
  ) {
    // Hide inline actions + status only when the browser is
    // phone-width (this method is web-only; the native mobile app
    // never reaches here).
    final isPhoneWeb = MediaQuery.of(context).size.width < 1024;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          for (final member in filtered) ...[
            GestureDetector(
              // Tapping the card opens the detail dialog with edit/delete
              // options, mirroring the mobile list's behavior.
              onTap: () async {
                final result =
                    await StaffDetailDialog.show(context, member);
                if (result == true) {
                  _load();
                }
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: p.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.cardBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: kPrimaryBlue,
                      backgroundImage:
                          member.photoUrl != null &&
                                  member.photoUrl!.isNotEmpty
                              ? NetworkImage(member.photoUrl!)
                              : null,
                      child: member.photoUrl == null ||
                              member.photoUrl!.isEmpty
                          ? Text(
                              member.fullName.isNotEmpty
                                  ? member.fullName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            member.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: p.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            member.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: p.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  member.role,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: p.textPrimary,
                                  ),
                                ),
                              ),
                              // Status pill + action icons only on
                              // wider web widths.
                              if (!isPhoneWeb) ...[
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.circle,
                                  size: 8,
                                  color: kSafeGreen,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'ACTIVE',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? kSafeGreen
                                        : const Color(0xFF10B981),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (!isPhoneWeb)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Edit staff',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(
                              Icons.edit_outlined,
                              size: 18,
                              color: kPrimaryBlue,
                            ),
                            onPressed: () async {
                              final result = await StaffDetailDialog.show(
                                context,
                                member,
                              );
                              if (result == true) {
                                _load();
                              }
                            },
                          ),
                          const SizedBox(height: 4),
                          IconButton(
                            tooltip: 'Remove staff',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: Colors.red,
                            ),
                            onPressed: () => _delete(member),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  TextStyle _webHeaderStyle(AppPalette p) => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: p.textSecondary,
      );
}