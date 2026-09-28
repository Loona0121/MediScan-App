import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../services/session_service.dart';
import '../services/account_service.dart';
import '../widgets/web_shell.dart';
import 'inventory.dart';
import '../services/notification_service.dart';
import '../utils/image_utils.dart';
import '../utils/app_palette.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isLoading = true;
  List<MedicineItem> _alerts = [];
  final Set<int> _dismissedIds = {};
  bool _showSearch = false;

  String? _userPhotoUrl;
  String? _userDisplayName;
  String? _userRoleLabel;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
    _loadUserProfile();
  }

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

  Future<void> _loadAlerts() async {
    setState(() => _isLoading = true);
    try {
      final rehosted = await SupabaseService.ensureProductImagesBackfilled();
      final data = await SupabaseService.fetchInventory();
      final items = data.map((e) => MedicineItem.fromMap(e)).toList();

      final alerts = items
          .where(
            (item) =>
                item.status == ExpiryStatus.expired ||
                item.status == ExpiryStatus.warning,
          )
          .toList();

      alerts.sort((a, b) {
        if (a.status != b.status) {
          return a.status == ExpiryStatus.expired ? -1 : 1;
        }
        return a.expiryDate.compareTo(b.expiryDate);
      });

      setState(() => _alerts = alerts);
      await NotificationService.instance.refresh();
      if (rehosted > 0) {
        debugPrint('Notifications refreshed after rehosting $rehosted images');
      }
    } catch (e) {
      debugPrint('Notifications fetch error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _markAllRead() async {
    await SupabaseService.markAllNotificationsAsRead();
    await _loadAlerts();
    await NotificationService.instance.refresh();
  }

  List<MedicineItem> get _visibleAlerts {
    return _alerts.where((item) {
      if (_dismissedIds.contains(item.id)) return false;
      if (_searchQuery.isEmpty) return true;
      return item.productName.toLowerCase().contains(
        _searchQuery.toLowerCase(),
      );
    }).toList();
  }

  /// Unread items first (preserving expired > warning, soonest-expiry order
  /// within each group), then read items.
  List<MedicineItem> get _sortedForMobile {
    final unread = <MedicineItem>[];
    final read = <MedicineItem>[];
    for (final item in _visibleAlerts) {
      (item.isRead ? read : unread).add(item);
    }
    return [...unread, ...read];
  }

  Widget _buildMobileAlertCard(MedicineItem item, bool isDark, AppPalette p) {
    final isRead = item.isRead;
    final isExpired = item.status == ExpiryStatus.expired;
    final days = item.daysRemaining;
    final statusColor = isExpired ? kDangerRed : kWarningOrange;
    final statusText = isExpired ? 'Expired' : 'Expires in $days days';

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.grey.shade500,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.close, color: Colors.white, size: 24),
      ),
      onDismissed: (_) {
        setState(() => _dismissedIds.add(item.id));
      },
      child: GestureDetector(
        onTap: () => _showItemDetails(item),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: p.cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isRead
                  ? p.cardBorder
                  : statusColor.withValues(alpha: 0.35),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              _mobileThumbnail(item, statusColor, isExpired),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.productName,
                      style: TextStyle(
                        fontWeight: isRead ? FontWeight.w500 : FontWeight.bold,
                        fontSize: 14,
                        color: p.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!isRead)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(left: 8),
                  decoration: const BoxDecoration(
                    color: kPrimaryBlue,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mobileSectionHeader(String label, AppPalette p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: p.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Future<void> _showItemDetails(MedicineItem item) async {
    if (!item.isRead) {
      await SupabaseService.markNotificationAsRead(item.id);
      await _loadAlerts();
      await NotificationService.instance.refresh();
    }

    if (!mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette(isDark);

    final statusColor = item.status == ExpiryStatus.expired
        ? kDangerRed
        : kWarningOrange;
    final statusLabel = item.status == ExpiryStatus.expired
        ? 'EXPIRED'
        : 'EXPIRING SOON';

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        backgroundColor: p.cardBg,
        surfaceTintColor: p.cardBg,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.cardBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                // ── Header: thumbnail + name + status icon ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                          ? Image.network(
                              item.imageUrl!,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _detailThumbnailFallback(statusColor, p),
                            )
                          : _detailThumbnailFallback(statusColor, p),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.productName,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              height: 1.3,
                              color: p.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  statusLabel,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // ── Details ──
                _detailRow('Category', item.category, p),
                _detailRow('Expiry Date', item.fullExpiryLabel, p),
                _detailRow('Quantity', item.formattedQuantity, p),
                _detailRow('Status', statusLabel, p, valueColor: statusColor),
                const SizedBox(height: 20),
                Divider(height: 1, color: p.cardBorder),
                const SizedBox(height: 16),
                Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryBlue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(120, 44),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailThumbnailFallback(Color statusColor, AppPalette p) {
    return Container(
      width: 80,
      height: 80,
      color: p.fallbackThumbBg,
      child: Icon(Icons.medication_outlined, color: statusColor, size: 32),
    );
  }

  Widget _detailRow(
    String label,
    String value,
    AppPalette p, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: p.textSecondary, fontSize: 14)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: valueColor ?? p.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileThumbnail(
    MedicineItem item,
    Color statusColor,
    bool isExpired,
  ) {
    final url = item.imageUrl;
    final fallback = Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(
        isExpired ? Icons.error_outline : Icons.access_time_rounded,
        color: statusColor,
        size: 20,
      ),
    );

    if (url == null || url.isEmpty) return fallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        url,
        width: 38,
        height: 38,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return SizedBox(
            width: 38,
            height: 38,
            child: Center(
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: statusColor,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _webThumbnail(
    MedicineItem item,
    Color color,
    bool isRead,
    IconData icon,
  ) {
    final url = item.imageUrl;
    final fallback = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: isRead ? 0.08 : 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        icon,
        color: color.withValues(alpha: isRead ? 0.6 : 1),
        size: 20,
      ),
    );

    if (url == null || url.isEmpty) return fallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        url,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette(isDark);

    final visible = _visibleAlerts;
    final unreadCount = visible.where((e) => !e.isRead).length;
    final isWeb = kIsWeb;

    if (isWeb) {
      return _buildWebLayout(context, visible, unreadCount);
    }

    return Scaffold(
      backgroundColor: p.scaffoldBg,
      appBar: AppBar(
        backgroundColor: p.appBarBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: p.textPrimary),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: _showSearch
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: p.textPrimary),
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Search notifications',
                  hintStyle: TextStyle(color: p.textSecondary),
                  border: InputBorder.none,
                ),
              )
            : Text(
                'Notifications',
                style: TextStyle(
                  color: p.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
        actions: [
          IconButton(
            icon: Icon(
              _showSearch ? Icons.close : Icons.search,
              color: p.textPrimary,
            ),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchQuery = '';
                  _searchController.clear();
                }
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  unreadCount > 0 ? '$unreadCount unread' : 'All caught up',
                  style: TextStyle(color: p.textSecondary, fontSize: 13),
                ),
                TextButton(
                  onPressed: unreadCount == 0 ? null : _markAllRead,
                  child: Text(
                    'Mark all as read',
                    style: TextStyle(
                      color: unreadCount == 0 ? p.textMuted : kPrimaryBlue,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _visibleAlerts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.notifications_off_outlined,
                          size: 48,
                          color: p.textMuted,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No alerts right now',
                          style: TextStyle(color: p.textSecondary),
                        ),
                      ],
                    ),
                  )
                : Builder(
                    builder: (context) {
                      final sorted = _sortedForMobile;
                      final cutoff = DateTime.now().subtract(
                        const Duration(hours: 24),
                      );
                      final todayItems = <MedicineItem>[];
                      final earlierItems = <MedicineItem>[];

                      for (final item in sorted) {
                        if (item.createdAt != null &&
                            item.createdAt!.isAfter(cutoff)) {
                          todayItems.add(item);
                        } else {
                          earlierItems.add(item);
                        }
                      }

                      return RefreshIndicator(
                        onRefresh: _loadAlerts,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                          children: [
                            if (todayItems.isNotEmpty) ...[
                              _mobileSectionHeader('TODAY', p),
                              ...todayItems.map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _buildMobileAlertCard(
                                    item,
                                    isDark,
                                    p,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                            ],
                            if (earlierItems.isNotEmpty) ...[
                              _mobileSectionHeader('EARLIER', p),
                              ...earlierItems.map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _buildMobileAlertCard(
                                    item,
                                    isDark,
                                    p,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebLayout(
    BuildContext context,
    List<MedicineItem> visible,
    int unreadCount,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette(isDark);

    final today = <MedicineItem>[];
    final earlier = <MedicineItem>[];

    final cutoff = DateTime.now().subtract(const Duration(hours: 24));

    for (final item in visible) {
      if (item.createdAt != null && item.createdAt!.isAfter(cutoff)) {
        today.add(item);
      } else {
        earlier.add(item);
      }
    }

    Widget rowFor(MedicineItem item) {
      final isExpired = item.status == ExpiryStatus.expired;
      final isRead = item.isRead;

      final color = isExpired ? kDangerRed : kWarningOrange;

      final label = isExpired ? 'EXPIRED' : 'EXPIRES SOON';

      final icon = isExpired
          ? Icons.error_outline
          : Icons.warning_amber_rounded;

      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: ValueKey(item.id),
          onTap: () => _showItemDetails(item),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: isRead ? p.searchBg : p.cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isRead ? p.cardBorder : color.withValues(alpha: 0.35),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 4,
                    color: isRead
                        ? (isDark
                              ? const Color(0xFF334155)
                              : const Color(0xFFCBD5E1))
                        : color,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          _webThumbnail(item, color, isRead, icon),

                          const SizedBox(width: 14),

                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.productName,
                                  style: TextStyle(
                                    fontWeight: isRead
                                        ? FontWeight.w500
                                        : FontWeight.bold,
                                    color: isRead
                                        ? p.textSecondary
                                        : p.textPrimary,
                                  ),
                                ),

                                const SizedBox(height: 4),

                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: color.withValues(
                                          alpha: isRead ? 0.10 : 0.15,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        label,
                                        style: TextStyle(
                                          color: color.withValues(
                                            alpha: isRead ? 0.75 : 1,
                                          ),
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),

                                    const SizedBox(width: 8),

                                    Expanded(
                                      child: Text(
                                        isExpired
                                            ? 'Immediate removal from shelf required.'
                                            : 'Consider batch rotation or restocking order.',
                                        style: TextStyle(
                                          color: p.textSecondary,
                                          fontSize: 12.5,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          if (!isRead)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(left: 8, right: 8),
                              decoration: const BoxDecoration(
                                color: kPrimaryBlue,
                                shape: BoxShape.circle,
                              ),
                            ),

                          Icon(Icons.chevron_right, color: p.textMuted),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return WebShell(
      activeRoute: 'notifications',
      photoUrl: _userPhotoUrl,
      displayName: _userDisplayName,
      headerBar: WebTopBar(
        pageTitle: 'Notifications',
        pageSubtitle: 'Track your inventory status and expiration alerts',
        hasUnread: _alerts.any((e) => !e.isRead),
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

      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrowShell = MediaQuery.of(context).size.width < 1024;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isNarrowShell) const SizedBox(height: 8),

              // =====================================================
              // MARK ALL AS READ
              // (search bar removed here — web view only)
              // =====================================================
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: unreadCount == 0 ? null : _markAllRead,
                  icon: Icon(
                    Icons.done_all,
                    size: 18,
                    color: unreadCount == 0 ? p.textMuted : kPrimaryBlue,
                  ),
                  label: Text(
                    'Mark all as read',
                    style: TextStyle(
                      color: unreadCount == 0 ? p.textMuted : kPrimaryBlue,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: kPrimaryBlue,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // =====================================================
              // CONTENT
              // =====================================================
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.notifications_off_outlined,
                          size: 48,
                          color: p.textMuted,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No alerts right now',
                          style: TextStyle(color: p.textSecondary),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                // ===================================================
                // TODAY
                // ===================================================
                if (today.isNotEmpty) ...[
                  Text(
                    'TODAY',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: p.textSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),

                  const SizedBox(height: 10),

                  ...today.map(rowFor),

                  const SizedBox(height: 16),
                ],

                // ===================================================
                // EARLIER
                // ===================================================
                if (earlier.isNotEmpty) ...[
                  Text(
                    'EARLIER',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: p.textSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),

                  const SizedBox(height: 10),

                  ...earlier.map(rowFor),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}