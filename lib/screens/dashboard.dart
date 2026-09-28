import 'inventory.dart';
import 'notifications.dart';
import 'settings.dart';
import 'login.dart';
import 'reports.dart';
import 'manual_add_item.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/web_shell.dart';
import '../widgets/branded_loader.dart';
import 'scan.dart';
import '../services/supabase_service.dart';
import '../services/session_service.dart';
import '../services/account_service.dart';
import '../services/push_notification_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../utils/image_utils.dart';
import '../utils/app_palette.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// Card colors
const Color cardExpiredColor  = Color(0xFFFFBDA3); // Expired (stat card)
const Color cardExpiringColor = Color(0xFFFFD6A6); // Expiring soon (stat card)
const Color cardSafeColor     = Color(0xFFB5E18B); // Safe
const Color cardBlueAccent    = Color(0xFFAEE2FF); // Total inventory

// Forecast chart bar colors
const Color kForecastExpiringColor = Color(0xFFFACE68);
const Color kForecastExpiredColor  = Color(0xFFFF9D9D);

// Kept for pill legends / status pills elsewhere
const Color kWarningOrange = Color(0xFFFB923C);
const Color kDangerRed     = Color(0xFFF87171);
const Color kSafeGreen     = Color(0xFF34D399);

// ── SVG icons for the stat cards ──
const String _svgInventory =
    '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><rect width="256" height="256" fill="none"/><path d="M223.68,66.15,135.68,18a15.88,15.88,0,0,0-15.36,0l-88,48.17a16,16,0,0,0-8.32,14v95.64a16,16,0,0,0,8.32,14l88,48.17a15.88,15.88,0,0,0,15.36,0l88-48.17a16,16,0,0,0,8.32-14V80.18A16,16,0,0,0,223.68,66.15ZM128,120,47.65,76,128,32l80.35,44Zm8,99.64V133.83l80-43.78v85.76Z"/></svg>''';

const String _svgSafe =
    '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><rect width="256" height="256" fill="none"/><path d="M208,40H48A16,16,0,0,0,32,56v56c0,52.72,25.52,84.67,46.93,102.19,23.06,18.86,46,25.26,47,25.53a8,8,0,0,0,4.2,0c1-.27,23.91-6.67,47-25.53C198.48,196.67,224,164.72,224,112V56A16,16,0,0,0,208,40Zm-34.32,69.66-56,56a8,8,0,0,1-11.32,0l-24-24a8,8,0,0,1,11.32-11.32L112,148.69l50.34-50.35a8,8,0,0,1,11.32,11.32Z"/></svg>''';

const String _svgExpired =
    '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><rect width="256" height="256" fill="none"/><path d="M208,32H184V24a8,8,0,0,0-16,0v8H88V24a8,8,0,0,0-16,0v8H48A16,16,0,0,0,32,48V208a16,16,0,0,0,16,16H208a16,16,0,0,0,16-16V48A16,16,0,0,0,208,32ZM157.66,170.34a8,8,0,0,1-11.32,11.32L128,163.31l-18.34,18.35a8,8,0,0,1-11.32-11.32L116.69,152,98.34,133.66a8,8,0,0,1,11.32-11.32L128,140.69l18.34-18.35a8,8,0,0,1,11.32,11.32L139.31,152ZM208,80H48V48H72v8a8,8,0,0,0,16,0V48h80v8a8,8,0,0,0,16,0V48h24Z"/></svg>''';

const String _svgExpiring =
    '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><rect width="256" height="256" fill="none"/><path d="M236.8,188.09,149.35,36.22h0a24.76,24.76,0,0,0-42.7,0L19.2,188.09a23.51,23.51,0,0,0,0,23.72A24.35,24.35,0,0,0,40.55,224h174.9a24.35,24.35,0,0,0,21.33-12.19A23.51,23.51,0,0,0,236.8,188.09ZM120,104a8,8,0,0,1,16,0v40a8,8,0,0,1-16,0Zm8,88a12,12,0,1,1,12-12A12,12,0,0,1,128,192Z"/></svg>''';

const TextStyle kSectionHeaderStyle = TextStyle(
  fontWeight: FontWeight.bold,
  color: Color(0xFF1E293B),
  fontSize: 17,
);

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  bool _isLoading = true;
  bool _hasUnread = false;
  List<MedicineItem> _items = [];

  String? _userPhotoUrl;
  String? _userDisplayName;
  String? _userRoleLabel;
  String? _pharmacyName;

  String _forecastRange = '6 Months';
  bool _expiredOnlyFilter = false;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  int get _totalCount => _items.length;

  int get _urgentCount =>
      _items.where((i) => i.status == ExpiryStatus.warning).length;
  int get _expiredCount =>
      _items.where((i) => i.status == ExpiryStatus.expired).length;
  int get _safeCount =>
      _items.where((i) => i.status == ExpiryStatus.safe).length;

  int get _unreadCount => _hasUnread ? 1 : 0;

  int get _safeStockUnits => _items
      .where((i) => i.status == ExpiryStatus.safe)
      .fold<int>(0, (sum, i) => sum + (i.quantity ?? 0));

  List<MedicineItem> get _criticalItems {
    final critical = _items
        .where((i) =>
            i.status == ExpiryStatus.expired ||
            i.status == ExpiryStatus.warning)
        .toList();
    critical.sort((a, b) => a.daysRemaining.compareTo(b.daysRemaining));
    return critical;
  }

  List<MedicineItem> get _filteredCriticalItems {
    var list = _criticalItems;
    if (_expiredOnlyFilter) {
      list = list.where((i) => i.status == ExpiryStatus.expired).toList();
    }
    if (_searchQuery.isNotEmpty) {
      list = list
          .where((i) => i.productName.toLowerCase().contains(_searchQuery))
          .toList();
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    _loadInventory();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInventory() async {
    setState(() => _isLoading = true);

    try {
      final data = await SupabaseService.fetchInventory();
      final unread = await SupabaseService.hasUnreadNotifications();

      if (!mounted) return;

      setState(() {
        _items = data.map((e) => MedicineItem.fromMap(e)).toList();
        _hasUnread = unread;
      });

      await PushNotificationService.checkAndSendExpiryAlerts(data);

      final rehosted = await SupabaseService.ensureProductImagesBackfilled();
      if (rehosted > 0 && mounted) {
        final refreshed = await SupabaseService.fetchInventory();
        if (!mounted) return;
        setState(() {
          _items = refreshed.map((e) => MedicineItem.fromMap(e)).toList();
        });
      }
    } catch (e) {
      debugPrint('Dashboard fetch error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      final email = await SessionService.email;
      if (email != null) {
        await AccountService.refreshFromSupabase(email);

        final photoUrl = await AccountService.getPhotoUrl(email);
        final fullName = await AccountService.getFullName(email);
        final isAdmin = await AccountService.isAdmin(email);

        String? pharmacy;
        try {
          pharmacy = await SupabaseService.fetchPharmacyName();
        } catch (_) {
          pharmacy = null;
        }

        if (mounted) {
          setState(() {
            _userPhotoUrl = bustCache(photoUrl);
            _userDisplayName = fullName;
            _userRoleLabel = isAdmin ? 'Manager' : 'Staff';
            _pharmacyName = pharmacy;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 18) return 'Good Afternoon';
    return 'Good Evening';
  }

  String get _firstName {
    final name = _userDisplayName?.trim() ?? '';
    if (name.isEmpty) return 'there';
    return name.split(' ').first;
  }

  Future<void> startScanning() async {
    final status = await Permission.camera.request();

    if (status.isGranted) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ScanScreen()),
      );

      if (result != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Scanned: $result')));
        _loadInventory();
      }
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera permission is required.')),
      );
    }
  }

Future<void> _openManualAddItem() async {
  final saved = await ManualAddItemScreen.show(context);
  if (saved == true && mounted) {
    _loadInventory();
  }
}

  Future<void> _openInventoryFiltered(String status) async {
    InventoryScreen.initialStatusFilter = status;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const InventoryScreen()),
    );
    if (!mounted) return;
    _loadInventory();
  }

  Future<void> _openReports() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ReportsScreen()),
    );
    if (!mounted) return;
    _loadInventory();
  }

  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    if (!mounted) return;
    _loadInventory();
  }

  // ─────────────────────────────────────────────────────────────────
  // MOBILE BUILD
  // ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final hasInventory = _items.isNotEmpty;
    final isWeb = kIsWeb;

    if (isWeb) {
      return _buildWebLayout(context, hasInventory);
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette(isDark);

    return Scaffold(
      backgroundColor: p.scaffoldBg,
      appBar: AppBar(
        backgroundColor: p.appBarBg,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        title: const Text(
          'MediScan',
          style: TextStyle(
            fontFamily: 'Gugi',
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: kPrimaryBlue,
          ),
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                onPressed: _openNotifications,
                icon: SvgPicture.asset(
                  'assets/icon/notifications.svg',
                  width: 24,
                  height: 24,
                  colorFilter: ColorFilter.mode(
                    p.textPrimary,
                    BlendMode.srcIn,
                  ),
                ),
              ),
              if (_hasUnread)
                Positioned(
                  right: 10,
                  top: 10,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          PopupMenuButton<String>(
            tooltip: 'Account',
            offset: const Offset(0, 46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: (value) =>
                _handleMobileProfileSelection(context, value),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person_outline,
                        size: 18, color: Color(0xFF64748B)),
                    SizedBox(width: 10),
                    Text('Profile'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 18, color: Colors.red),
                    SizedBox(width: 10),
                    Text('Logout', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.only(right: 16, left: 4),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: kPrimaryBlue,
                backgroundImage:
                    (_userPhotoUrl != null && _userPhotoUrl!.isNotEmpty)
                        ? NetworkImage(_userPhotoUrl!)
                        : null,
                child: (_userPhotoUrl == null || _userPhotoUrl!.isEmpty)
                    ? Text(
                        _userDisplayName != null &&
                                _userDisplayName!.isNotEmpty
                            ? _userDisplayName!
                                .trim()
                                .split(' ')
                                .map((e) => e[0])
                                .take(2)
                                .join()
                                .toUpperCase()
                            : 'AC',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadInventory,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$_greeting, $_firstName',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              if (_pharmacyName != null)
                Row(
                  children: [
                    Icon(
                      Icons.local_pharmacy_outlined,
                      size: 14,
                      color: p.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _pharmacyName!,
                      style: TextStyle(
                        fontSize: 13,
                        color: p.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 20),

              _buildStatCardsGrid(p),

              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: p.cardDecoration,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Text('Expiry Forecast',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: p.textPrimary,
                              fontSize: 17,
                            )),
                        _buildRangeChips(p),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Units at risk of expiry over the next 6 months',
                      style: TextStyle(fontSize: 12, color: p.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 180,
                      child: _isLoading
                          ? const Center(child: BrandedLoading(size: 40))
                          : _buildForecastChart(p, barWidth: 32),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildLegendDot('Expiring', kForecastExpiringColor, p),
                        const SizedBox(width: 24),
                        _buildLegendDot('Expired', kForecastExpiredColor, p),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              _buildHighPriorityTable(p),
              const SizedBox(height: 20),

              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: BrandedLoading(label: 'Loading inventory...'),
                )
              else if (!hasInventory)
                _buildEmptyState(p)
              else
                _buildRecentActivity(p),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 0),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // WEB BUILD
  // ─────────────────────────────────────────────────────────────────
  Widget _buildWebLayout(BuildContext context, bool hasInventory) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette(isDark);
    final wideContent = MediaQuery.of(context).size.width >= 1100;
    final isNarrowShell = MediaQuery.of(context).size.width < 1024;

    return WebShell(
      activeRoute: 'dashboard',
      photoUrl: _userPhotoUrl,
      displayName: _userDisplayName,
      headerBar: WebTopBar(
        showSearch: true,
        searchHint: 'Search for anything...',
        searchController: _searchController,
        onSearchChanged: (value) {
          setState(() => _searchQuery = value.trim().toLowerCase());
        },
        hasUnread: _hasUnread,
        photoUrl: _userPhotoUrl,
        displayName: _userDisplayName,
        roleLabel: _userRoleLabel,
        initials: _userDisplayName != null && _userDisplayName!.isNotEmpty
            ? _userDisplayName!
                .split(' ')
                .map((e) => e[0])
                .join('')
                .toUpperCase()
            : 'AC',
        onBellTap: _openNotifications,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           if (isNarrowShell) const SizedBox(height: 16),
          Text(
            '$_greeting, $_firstName',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: p.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.local_pharmacy_outlined,
                size: 15,
                color: p.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                _pharmacyName ?? 'Your Pharmacy',
                style: TextStyle(
                  fontSize: 14,
                  color: p.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          _buildStatCardsGrid(p),
          const SizedBox(height: 20),

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 80),
              child: Center(
                child: BrandedLoading(label: 'Loading inventory...'),
              ),
            )
          else if (!hasInventory)
            _buildEmptyState(p, isWide: true)
          else ...[
            // 👈 Stack vertically on narrow widths, side-by-side on wide.
            if (wideContent)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 6,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: p.cardDecoration,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Expiry Forecast',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.bold,
                                          color: p.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Units at risk of expiry over the next 6 months',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: p.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                _buildRangeChips(p),
                              ],
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              height: 240,
                              child: _buildForecastChart(p),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _buildLegendDot(
                                    'Expiring', kForecastExpiringColor, p),
                                const SizedBox(width: 24),
                                _buildLegendDot(
                                    'Expired', kForecastExpiredColor, p),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 4,
                      child: _buildHighPriorityTable(p),
                    ),
                  ],
                ),
              )
            else ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: p.cardDecoration,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Text(
                          'Expiry Forecast',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: p.textPrimary,
                          ),
                        ),
                        _buildRangeChips(p),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Units at risk of expiry over the next 6 months',
                      style: TextStyle(
                        fontSize: 13,
                        color: p.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 220,
                      child: _buildForecastChart(p),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildLegendDot(
                            'Expiring', kForecastExpiringColor, p),
                        const SizedBox(width: 24),
                        _buildLegendDot(
                            'Expired', kForecastExpiredColor, p),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _buildHighPriorityTable(p),
            ],

            const SizedBox(height: 20),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: p.cardDecoration,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Recent Activity',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: p.textPrimary,
                          )),
                      TextButton(
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const InventoryScreen()),
                          );
                          if (!mounted) return;
                          _loadInventory();
                        },
                        child: const Text(
                          'See all',
                          style: TextStyle(
                            color: kPrimaryBlue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ..._recentItems()
                      .take(3)
                      .map((item) => _webActivityRow(item, p)),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          _buildQuickActionsGrid(p),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // Stat cards
  // ─────────────────────────────────────────────────────────────────
  // 👈 Now auto-switches between Row (wide) and 2-column Wrap (narrow)
  // based on available width instead of the kIsWeb flag.
  Widget _buildStatCardsGrid(AppPalette p) {
    final cards = <Widget>[
      _statCard(
        p: p,
        title: 'Expiring Soon',
        value: _isLoading ? '--' : '$_urgentCount',
        hint: 'Nearing expiry — tap to view list',
        accentColor: cardExpiringColor,
        svgIcon: _svgExpiring,
        onTap: _urgentCount == 0
            ? null
            : () => _openInventoryFiltered('Expiring'),
      ),
      _statCard(
        p: p,
        title: 'Expired Items',
        value: _isLoading ? '--' : '$_expiredCount',
        hint: 'Past expiry date — tap to view list',
        accentColor: cardExpiredColor,
        svgIcon: _svgExpired,
        onTap: _expiredCount == 0
            ? null
            : () => _openInventoryFiltered('Expired'),
      ),
      _statCard(
        p: p,
        title: 'Safe Items',
        value: _isLoading ? '--' : '$_safeCount',
        hint: 'Adequate stock — tap to view list',
        accentColor: cardSafeColor,
        svgIcon: _svgSafe,
        onTap: _safeCount == 0
            ? null
            : () => _openInventoryFiltered('Safe'),
      ),
      _statCard(
        p: p,
        title: 'Total Inventory',
        value: _isLoading ? '--' : '$_totalCount',
        hint: 'Products in your inventory',
        accentColor: cardBlueAccent,
        svgIcon: _svgInventory,
        onTap: () => _openInventoryFiltered('All'),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Wide enough to fit four cards side-by-side → keep Row.
        if (constraints.maxWidth >= 900) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < cards.length; i++) ...[
                  Expanded(child: cards[i]),
                  if (i != cards.length - 1) const SizedBox(width: 14),
                ],
              ],
            ),
          );
        }

        // Narrow → 2-column grid.
        const spacing = 12.0;
        final itemWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards
              .map((c) => SizedBox(width: itemWidth, child: c))
              .toList(),
        );
      },
    );
  }

    Widget _statCard({
    required AppPalette p,
    required String title,
    required String value,
    required String hint,
    required Color accentColor,
    required String svgIcon,
    VoidCallback? onTap,
  }) {
    return MouseRegion(
      cursor: onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: accentColor,
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFF1E293B),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      color: Color(0xFF1E293B),
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: SvgPicture.string(
                      svgIcon,
                      width: 24,
                      height: 24,
                      colorFilter: ColorFilter.mode(
                        accentColor,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // "View →" row replaces the old hint text
              Row(
                children: [
                  const Text(
                    'View',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF1E293B),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.arrow_forward,
                      size: 14,
                      color: Color(0xFF1E293B),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // Range chips
  // ─────────────────────────────────────────────────────────────────
  Widget _buildRangeChips(AppPalette p) {
    const options = ['30 Days', '3 Months', '6 Months'];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: p.chipTrackBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((label) {
          final selected = _forecastRange == label;
          return GestureDetector(
            onTap: () => setState(() => _forecastRange = label),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: selected ? p.chipSelectedBg : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? p.textPrimary : p.textSecondary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLegendDot(String label, Color color, AppPalette p) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: p.textSecondary,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // Forecast data
  // ─────────────────────────────────────────────────────────────────
  List<({String label, int expiredUnits, int expiringUnits})>
      _buildForecastData() {
    final now = DateTime.now();
    final months = List.generate(6, (i) {
      return DateTime(now.year, now.month + i, 1);
    });

    return months.map((monthDate) {
      final label = DateFormat('MMM').format(monthDate);
      final isCurrentMonth =
          monthDate.year == now.year && monthDate.month == now.month;

      int expiredUnits = 0;
      int expiringUnits = 0;

      for (final item in _items) {
        final qty = item.quantity ?? 0;

        if (item.status == ExpiryStatus.expired) {
          if (isCurrentMonth) {
            expiredUnits += qty;
          }
          continue;
        }

        if (item.status == ExpiryStatus.safe) {
          continue;
        }

        final parts = item.expiryDate.split('-');
        if (parts.length < 2) continue;
        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (y == null || m == null) continue;
        final itemMonth = DateTime(y, m, 1);

        final matchesBucket = itemMonth.year == monthDate.year &&
            itemMonth.month == monthDate.month;
        if (!matchesBucket) continue;

        expiringUnits += qty;
      }

      return (
        label: label,
        expiredUnits: expiredUnits,
        expiringUnits: expiringUnits,
      );
    }).toList();
  }

  // ─────────────────────────────────────────────────────────────────
  // Stacked bar chart
  // ─────────────────────────────────────────────────────────────────
  Widget _buildForecastChart(AppPalette p, {double barWidth = 52}) {
    final data = _buildForecastData();

    final maxTotal = data.fold<int>(
      0,
      (m, d) => (d.expiredUnits + d.expiringUnits) > m
          ? (d.expiredUnits + d.expiringUnits)
          : m,
    );

    final baseMax = maxTotal < 4 ? 4 : maxTotal + 1;
    final interval = (baseMax / 4).ceilToDouble();
    final chartMax = interval * 4;

    double minVisible(double value, {required bool singleSegment}) {
      if (value <= 0) return 0;
      if (!singleSegment) return value;
      final floor = chartMax * 0.02;
      return value < floor ? floor : value;
    }

    return BarChart(
      BarChartData(
        minY: 0,
        maxY: chartMax,
        alignment: BarChartAlignment.spaceAround,
        groupsSpace: 24,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (value) => FlLine(
            color: p.isDark
                ? Colors.white.withOpacity(0.08)
                : Colors.grey.withOpacity(0.15),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: interval,
              getTitlesWidget: (value, meta) => Text(
                value.toInt().toString(),
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= data.length) return const SizedBox();
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(
                    data[i].label,
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (group) => const Color(0xFF1E293B),
            tooltipRoundedRadius: 8,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final d = data[groupIndex];
              return BarTooltipItem(
                'Expiring: ${d.expiringUnits} units\nExpired: ${d.expiredUnits} units',
                const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              );
            },
          ),
        ),
        barGroups: List.generate(data.length, (i) {
          final d = data[i];
          final total = d.expiredUnits + d.expiringUnits;

          if (total == 0) {
            return BarChartGroupData(x: i, barRods: const []);
          }

          final hasExpiring = d.expiringUnits > 0;
          final hasExpired = d.expiredUnits > 0;
          final bothPresent = hasExpiring && hasExpired;
          final singleSegment = !bothPresent;

          final expiringTop = hasExpiring
              ? minVisible(d.expiringUnits.toDouble(),
                  singleSegment: singleSegment)
              : 0.0;
          final expiredTop = hasExpired
              ? expiringTop +
                  minVisible(d.expiredUnits.toDouble(),
                      singleSegment: singleSegment)
              : expiringTop;

          final stackItems = <BarChartRodStackItem>[];
          if (hasExpiring) {
            stackItems.add(BarChartRodStackItem(
              0,
              expiringTop,
              kForecastExpiringColor,
            ));
          }
          if (hasExpired && expiredTop > expiringTop) {
            stackItems.add(BarChartRodStackItem(
              expiringTop,
              expiredTop,
              kForecastExpiredColor,
            ));
          }

          final Color topColor =
              (hasExpired && expiredTop > expiringTop)
                  ? kForecastExpiredColor
                  : kForecastExpiringColor;

          final BorderRadius radius = stackItems.length > 1
              ? BorderRadius.zero
              : const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                );

          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: expiredTop,
                width: barWidth,
                color: topColor,
                borderRadius: radius,
                rodStackItems: stackItems,
              ),
            ],
          );
        }),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // High Priority Action Table
  // ─────────────────────────────────────────────────────────────────
  Widget _buildHighPriorityTable(AppPalette p) {
    final items = _filteredCriticalItems.take(5).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: p.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'High Priority Action Table',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: p.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Items requiring immediate attention',
                      style: TextStyle(fontSize: 13, color: p.textSecondary),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: _expiredOnlyFilter
                    ? 'Show all critical items'
                    : 'Show expired only',
                child: InkWell(
                  onTap: () => setState(
                      () => _expiredOnlyFilter = !_expiredOnlyFilter),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _expiredOnlyFilter
                          ? kPrimaryBlue.withOpacity(0.10)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _expiredOnlyFilter
                            ? kPrimaryBlue.withOpacity(0.30)
                            : p.cardBorder,
                      ),
                    ),
                    child: Icon(
                      Icons.filter_list_rounded,
                      size: 18,
                      color:
                          _expiredOnlyFilter ? kPrimaryBlue : p.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  _expiredOnlyFilter
                      ? 'No expired items right now.'
                      : 'No critical items right now.\nEverything looks safe.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: p.textSecondary,
                    height: 1.5,
                  ),
                ),
              ),
            )
          else ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: p.cardBorder),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text('MEDICINE',
                        style: _tableHeaderStyle(p)),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text('EXPIRY', style: _tableHeaderStyle(p)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'UNITS',
                      style: _tableHeaderStyle(p),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),

            ...items.map((item) {
              final days = item.daysRemaining;
              final isExpired = item.status == ExpiryStatus.expired;

              final Color pillBg;
              final Color pillText;
              final String pillLabel;
              if (isExpired) {
                pillBg = const Color(0xFFFEE2E2);
                pillText = const Color(0xFFB91C1C);
                pillLabel = 'EXPIRED';
              } else if (days <= 30) {
                pillBg = const Color(0xFFFEF3C7);
                pillText = const Color(0xFFB45309);
                pillLabel = '$days DAYS';
              } else {
                pillBg = const Color(0xFFFEF9C3);
                pillText = const Color(0xFF854D0E);
                pillLabel = '$days DAYS';
              }

              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _showItemDetails(item, p),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: p.rowDivider),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: Text(
                            item.productName,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: p.textPrimary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: pillBg,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                pillLabel,
                                style: TextStyle(
                                  color: pillText,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            item.formattedQuantity,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: p.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),

            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () => _openInventoryFiltered('Expiring'),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View full high-priority list',
                      style: TextStyle(
                        color: kPrimaryBlue,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.chevron_right,
                        size: 16, color: kPrimaryBlue),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // Recent Activity
  // ─────────────────────────────────────────────────────────────────
  List<MedicineItem> _recentItems() {
    var recent = [..._items]
      ..sort((a, b) {
        final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
    if (_searchQuery.isNotEmpty) {
      recent = recent
          .where((i) => i.productName.toLowerCase().contains(_searchQuery))
          .toList();
    }
    return recent;
  }

  Widget _buildRecentActivity(AppPalette p) {
    final topItems = _recentItems().take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Recent Activity',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: p.textPrimary,
                  fontSize: 17,
                )),
            TextButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const InventoryScreen()),
                );
                if (!mounted) return;
                _loadInventory();
              },
              child: const Text(
                'See all',
                style: TextStyle(
                  color: kPrimaryBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...topItems.map((item) => _buildActivityCard(item, p)),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: startScanning,
            icon: SvgPicture.asset(
              'assets/icon/scan.svg',
              width: 20,
              height: 20,
              colorFilter: const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
            ),
            label: const Text(
              'Scan Another Product',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActivityCard(MedicineItem item, AppPalette p) {
    final isUrgent = item.status == ExpiryStatus.expired ||
        item.status == ExpiryStatus.warning;
    final labelColor = isUrgent ? kDangerRed : kSafeGreen;
    final label = isUrgent ? 'URGENT ALERT' : 'INVENTORY UPDATE';

    final imageUrl = item.imageUrl;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: (imageUrl != null && imageUrl.isNotEmpty)
                ? Image.network(
                    imageUrl,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _thumbnailFallback(p),
                  )
                : _thumbnailFallback(p),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: labelColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        letterSpacing: 0.6,
                      ),
                    ),
                    Text(
                      _timeAgo(item.createdAt),
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.productName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: p.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _webActivityRow(MedicineItem item, AppPalette p) {
    final isExpired = item.status == ExpiryStatus.expired;
    final isWarning = item.status == ExpiryStatus.warning;

    final Color labelColor;
    final String label;
    if (isExpired) {
      labelColor = kDangerRed;
      label = 'URGENT ALERT';
    } else if (isWarning) {
      labelColor = const Color(0xFF3B82F6);
      label = 'INVENTORY UPDATE';
    } else {
      labelColor = kSafeGreen;
      label = 'STOCK SECURED';
    }

    final imageUrl = item.imageUrl;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.rowDivider)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: (imageUrl != null && imageUrl.isNotEmpty)
                ? Image.network(
                    imageUrl,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _smallFallback(p),
                  )
                : _smallFallback(p),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.productName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: p.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            _timeAgo(item.createdAt).toUpperCase(),
            style: TextStyle(
              color: p.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallFallback(AppPalette p) {
    return Container(
      width: 40,
      height: 40,
      color: p.fallbackThumbBg,
      child: const Icon(
        Icons.medication_outlined,
        color: kPrimaryBlue,
        size: 18,
      ),
    );
  }

  // 👈 Auto-switches between 4-across (wide) and 2-across (narrow).
  Widget _buildQuickActionsGrid(AppPalette p) {
    final tiles = <Widget>[
      _quickActionTile(
        icon: Icons.inventory_2_outlined,
        title: 'Add New Stock',
        subtitle: 'INVENTORY MANAGER',
        onTap: _openManualAddItem,
        p: p,
      ),
      _quickActionTile(
        icon: Icons.calendar_today_outlined,
        title: 'Review Expiries',
        subtitle: 'EXPIRY AUDIT',
        onTap: () => _openInventoryFiltered('Expiring'),
        p: p,
      ),
      _quickActionTile(
        icon: Icons.trending_up,
        title: 'Generate Report',
        subtitle: 'PERFORMANCE DATA',
        onTap: _openReports,
        p: p,
      ),
      _quickActionTile(
        icon: Icons.file_download_outlined,
        title: 'Export CSV',
        subtitle: 'DATA PORTABILITY',
        onTap: _openReports,
        p: p,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 16.0;
        final perRow = constraints.maxWidth >= 900 ? 4 : 2;
        final itemWidth =
            (constraints.maxWidth - spacing * (perRow - 1)) / perRow;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: tiles
              .map((t) => SizedBox(width: itemWidth, child: t))
              .toList(),
        );
      },
    );
  }

  Widget _quickActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required AppPalette p,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: p.cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: kPrimaryBlue),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: p.textSecondary,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showItemDetails(MedicineItem item, AppPalette p) {
    final statusColor = switch (item.status) {
      ExpiryStatus.expired => kDangerRed,
      ExpiryStatus.warning => kWarningOrange,
      ExpiryStatus.safe => kSafeGreen,
    };
    final statusLabel = switch (item.status) {
      ExpiryStatus.expired => 'EXPIRED',
      ExpiryStatus.warning => 'EXPIRING SOON',
      ExpiryStatus.safe => 'SAFE',
    };

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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: item.imageUrl != null &&
                              item.imageUrl!.isNotEmpty
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
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.12),
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
                    ),
                  ],
                ),
                const SizedBox(height: 20),
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
      child: Icon(
        Icons.medication_outlined,
        color: statusColor,
        size: 32,
      ),
    );
  }

  Widget _detailRow(String label, String value, AppPalette p,
      {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: p.textSecondary, fontSize: 14),
          ),
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

  Widget _thumbnailFallback(AppPalette p) {
    return Container(
      width: 44,
      height: 44,
      color: p.fallbackThumbBg,
      child: const Icon(
        Icons.medication_outlined,
        color: kPrimaryBlue,
        size: 20,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // Empty state
  // ─────────────────────────────────────────────────────────────────
  Widget _buildEmptyState(AppPalette p, {bool isWide = false}) {
    final illustrationSize = isWide ? 200.0 : 170.0;
    final circleSize = isWide ? 56.0 : 48.0;
    final iconSize = isWide ? 26.0 : 22.0;
    final arrowSize = isWide ? 18.0 : 16.0;
    final titleSize = isWide ? 20.0 : 16.0;
    final padding = isWide
        ? const EdgeInsets.symmetric(horizontal: 32, vertical: 40)
        : const EdgeInsets.all(20);

    Widget stepIcon(IconData icon, String label) {
      return Column(
        children: [
          Container(
            width: circleSize,
            height: circleSize,
            decoration: BoxDecoration(
              color: p.cardBg,
              shape: BoxShape.circle,
              border: Border.all(color: p.cardBorder),
            ),
            child: Icon(icon, size: iconSize, color: kPrimaryBlue),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: isWide ? 11 : 10,
              fontWeight: FontWeight.w700,
              color: p.textSecondary,
            ),
          ),
        ],
      );
    }

    Widget stepArrow() => Padding(
          padding: EdgeInsets.only(top: (circleSize - arrowSize) / 2),
          child: Icon(
            Icons.arrow_forward,
            size: arrowSize,
            color: p.textSecondary,
          ),
        );

    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: p.isDark
              ? [kPrimaryBlue.withOpacity(0.20), kPrimaryBlue.withOpacity(0.05)]
              : [kPrimaryBlue.withOpacity(0.08), Colors.white],
        ),
        borderRadius: BorderRadius.circular(isWide ? 16 : 20),
        border: Border.all(color: p.cardBorder),
      ),
      child: Column(
        children: [
          Image.asset(
            'assets/images/no_data.png',
            width: illustrationSize,
            height: illustrationSize,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 8),
          Text(
            'Your inventory is empty',
            style: TextStyle(
              fontSize: titleSize,
              fontWeight: FontWeight.bold,
              color: p.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: isWide ? 420 : double.infinity),
            child: Text(
              'Scan your first product to start tracking stock and catching expiry dates before they become a problem.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: p.textSecondary,
                height: 1.5,
                fontSize: isWide ? 14 : 12,
              ),
            ),
          ),
          SizedBox(height: isWide ? 28 : 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              stepIcon(Icons.qr_code_scanner, 'Scan'),
              stepArrow(),
              stepIcon(Icons.inventory_2_outlined, 'Track'),
              stepArrow(),
              stepIcon(Icons.notifications_active_outlined, 'Get Alerted'),
            ],
          ),
          SizedBox(height: isWide ? 28 : 18),
          if (isWide)
  Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      if (!kIsWeb) ...[
        ElevatedButton.icon(
          onPressed: startScanning,
          icon: SvgPicture.asset(
            'assets/icon/scan.svg',
            width: 18,
            height: 18,
            colorFilter: const ColorFilter.mode(
              Colors.white,
              BlendMode.srcIn,
            ),
          ),
          label: const Text(
            'Start Scanning',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
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
        ),
        const SizedBox(width: 12),
      ],
      OutlinedButton(
        onPressed: _openManualAddItem,
        child: Text(
          'Add Item Manually',
          style: TextStyle(
            color: p.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: p.cardBorder),
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    ],
  )
          else ...[
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: startScanning,
                icon: SvgPicture.asset(
                  'assets/icon/scan.svg',
                  width: 20,
                  height: 20,
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
                ),
                label: const Text(
                  'Start Scanning',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _openManualAddItem,
              child: const Text(
                'Or add an item manually',
                style:
                    TextStyle(color: kPrimaryBlue, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _timeAgo(DateTime? time) {
    if (time == null) return '';
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  Future<void> _handleMobileProfileSelection(
      BuildContext context, String value) async {
    switch (value) {
      case 'profile':
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
        if (result == true) {
          _loadUserProfile();
        }
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

TextStyle _tableHeaderStyle(AppPalette p) => TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: p.textSecondary,
      letterSpacing: 0.6,
    );

const String _svgMoon =
    '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><rect width="256" height="256" fill="none"/><path d="M235.54,150.21a104.84,104.84,0,0,1-37,52.91A104,104,0,0,1,32,120,103.09,103.09,0,0,1,52.88,57.48a104.84,104.84,0,0,1,52.91-37,8,8,0,0,1,10,10,88.08,88.08,0,0,0,109.8,109.8,8,8,0,0,1,10,10Z"/></svg>''';

const String _svgSun =
    '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><rect width="256" height="256" fill="none"/><path d="M120,40V16a8,8,0,0,1,16,0V40a8,8,0,0,1-16,0Zm8,24a64,64,0,1,0,64,64A64.07,64.07,0,0,0,128,64ZM58.34,69.66A8,8,0,0,0,69.66,58.34l-16-16A8,8,0,0,0,42.34,53.66Zm0,116.68-16,16a8,8,0,0,0,11.32,11.32l16-16a8,8,0,0,0-11.32-11.32ZM192,72a8,8,0,0,0,5.66-2.34l16-16a8,8,0,0,0-11.32-11.32l-16,16A8,8,0,0,0,192,72Zm5.66,114.34a8,8,0,0,0-11.32,11.32l16,16a8,8,0,0,0,11.32-11.32ZM48,128a8,8,0,0,0-8-8H16a8,8,0,0,0,0,16H40A8,8,0,0,0,48,128Zm80,80a8,8,0,0,0-8,8v24a8,8,0,0,0,16,0V216A8,8,0,0,0,128,208Zm112-88H216a8,8,0,0,0,0,16h24a8,8,0,0,0,0-16Z"/></svg>''';