import 'package:flutter/material.dart';

import '../services/account_service.dart';
import '../services/push_notification_service.dart';
import '../services/session_service.dart';
import '../services/supabase_service.dart';

import '../widgets/app_bottom_nav.dart';
import '../widgets/branded_loader.dart';
import '../widgets/web_shell.dart';

import 'notifications.dart';
import 'reports.dart';
import 'manual_add_item.dart';
import '../widgets/app_toast.dart';
import '../utils/image_utils.dart';
import '../utils/app_palette.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// ─────────────────────────────────────────────────────────────────────
// SVG for the export icon (tray with downward arrow).
// Embedded inline so no extra asset file is needed.
// ─────────────────────────────────────────────────────────────────────
const String _svgExport =
    '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><rect width="256" height="256" fill="none"/><path d="M208,216H48a8,8,0,0,1-8-8V72L56,40H200l16,32V208A8,8,0,0,1,208,216Z" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/><line x1="40" y1="72" x2="216" y2="72" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/><line x1="128" y1="104" x2="128" y2="184" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/><polyline points="96 152 128 184 160 152" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/></svg>''';

class MedicineItem {
  final int id;
  final String productName;
  final String expiryDate;
  final String category;
  final bool isRead;
  final String? imageUrl;
  final DateTime? createdAt;
  final int? quantity;

  const MedicineItem({
    required this.id,
    required this.productName,
    required this.expiryDate,
    required this.category,
    required this.isRead,
    this.imageUrl,
    this.createdAt,
    this.quantity,
  });

  factory MedicineItem.fromMap(Map<String, dynamic> map) {
    return MedicineItem(
      id: map['id'] is int
          ? map['id']
          : int.tryParse(map['id']?.toString() ?? '') ?? 0,
      productName: map['product_name']?.toString() ?? '',
      expiryDate: map['expiry_date']?.toString() ?? '',
      category: map['category']?.toString() ?? '',
      isRead: map['is_read'] == true,
      imageUrl: map['image_url']?.toString(),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
      quantity: map['quantity'] is int
          ? map['quantity']
          : int.tryParse(map['quantity']?.toString() ?? ''),
    );
  }

  String get normalizedName =>
      productName.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  DateTime? get expiry {
    if (expiryDate.trim().isEmpty) return null;

    final parsed = DateTime.tryParse(expiryDate);
    if (parsed != null) {
      return DateTime(parsed.year, parsed.month, parsed.day);
    }

    final parts = expiryDate.split('-');

    if (parts.length >= 2) {
      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final day = parts.length >= 3 ? int.tryParse(parts[2]) ?? 1 : 1;

      if (year != null && month != null) {
        return DateTime(year, month, day);
      }
    }

    return null;
  }

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  ExpiryStatus get status {
    final expiryDateValue = expiry;
    if (expiryDateValue == null) return ExpiryStatus.safe;

    final difference = expiryDateValue.difference(_today).inDays;

    if (difference < 0) return ExpiryStatus.expired;
    if (difference <= 90) return ExpiryStatus.warning;
    return ExpiryStatus.safe;
  }

  int get daysRemaining {
    final expiryDateValue = expiry;
    if (expiryDateValue == null) return 0;
    return expiryDateValue.difference(_today).inDays;
  }

  String get formattedExpiry {
    final expiryDateValue = expiry;
    if (expiryDateValue == null) return expiryDate;

    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    return '${months[expiryDateValue.month]}/${expiryDateValue.year.toString().substring(2)}';
  }

  String get fullExpiryLabel {
    final expiryDateValue = expiry;
    if (expiryDateValue == null) return expiryDate;

    return '${expiryDateValue.month.toString().padLeft(2, '0')}/${expiryDateValue.year}';
  }

  String get formattedQuantity => quantity?.toString() ?? '—';

  String get daysRemainingLabel {
    if (expiry == null) return '—';
    if (daysRemaining < 0) return 'Expired';
    if (daysRemaining == 0) return 'Today';
    if (daysRemaining == 1) return '1 Day';
    return '$daysRemaining Days';
  }
}

enum ExpiryStatus { safe, warning, expired }

class InventoryScreen extends StatefulWidget {
  static String? initialStatusFilter;

  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _selectedCategoryFilter = 'All Categories';
  String _selectedStatusFilter = 'All Status';

  List<MedicineItem> _items = [];

  bool _isLoading = true;
  bool _hasUnread = false;

  Set<int> _selectedItems = {};

  String? _userPhotoUrl;
  String? _userDisplayName;
  String? _userRoleLabel;

  bool? _isAdmin;

  bool get _canManageInventory => _isAdmin == true;
  bool get _canEditInventory => _isAdmin != null;

  List<String> get _categoryOptions {
    final categories = _items
        .map((item) => item.category)
        .where((category) => category.trim().isNotEmpty)
        .toSet()
        .toList();

    categories.sort();

    return ['All Categories', ...categories];
  }

  Map<String, List<MedicineItem>> get _batchGroups {
    final groups = <String, List<MedicineItem>>{};
    for (final item in _items) {
      groups.putIfAbsent(item.normalizedName, () => []).add(item);
    }
    return groups;
  }

  String? _otherBatchesLabel(MedicineItem item) {
    final siblings = _batchGroups[item.normalizedName] ?? const [];
    final others = siblings.where((i) => i.id != item.id).toList();
    if (others.isEmpty) return null;

    final allBatches = [...others, item]..sort((a, b) {
        final ae = a.expiry;
        final be = b.expiry;
        if (ae == null && be == null) return 0;
        if (ae == null) return 1;
        if (be == null) return -1;
        return ae.compareTo(be);
      });
    final soonest = allBatches.first;

    final batchWord = others.length == 1 ? 'batch' : 'batches';
    return '+${others.length} other $batchWord · soonest exp ${soonest.formattedExpiry}';
  }

  // Ordered so display labels can differ from the underlying filter
  // value (e.g. "All Items" shown, but "All Status" used internally
  // to match the existing web dropdown's option set).
  static const Map<String, String> _statusChipLabels = {
    'All Status': 'All Items',
    'Safe': 'Safe',
    'Expired': 'Expired',
    'Expiring': 'Expiring',
  };

  static const List<String> _statusOptions = [
    'All Status',
    'Safe',
    'Expired',
    'Expiring',
  ];

  @override
  void initState() {
    super.initState();

    final pendingFilter = InventoryScreen.initialStatusFilter;
    if (pendingFilter != null) {
      _selectedStatusFilter = pendingFilter;
      InventoryScreen.initialStatusFilter = null;
    }

    _loadInventory();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    try {
      final email = await SessionService.email;

      if (email == null || email.isEmpty) {
        if (mounted) setState(() => _isAdmin = false);
        return;
      }

      final results = await Future.wait([
        AccountService.getPhotoUrl(email),
        AccountService.getFullName(email),
        AccountService.isAdmin(email),
      ]);

      if (!mounted) return;

      setState(() {
        _userPhotoUrl = bustCache(results[0] as String?);
        _userDisplayName = results[1] as String?;
        _isAdmin = results[2] as bool;
        _userRoleLabel = _isAdmin == true ? 'Manager' : 'Staff';
        if (_isAdmin != true) {
          _selectedItems.clear();
        }
      });
    } catch (e) {
      debugPrint('Error loading profile: $e');
      if (mounted) setState(() => _isAdmin = false);
    }
  }

  Future<void> _loadInventory() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final data = await SupabaseService.fetchInventory();
      final unread = await SupabaseService.hasUnreadNotifications();

      if (!mounted) return;

      setState(() {
        _items = data.map((item) => MedicineItem.fromMap(item)).toList();
        _hasUnread = unread;
        _selectedItems.clear();
      });

      try {
        await PushNotificationService.checkAndSendExpiryAlerts(data);
      } catch (e) {
        debugPrint('Push notification check error: $e');
      }

      final rehosted = await SupabaseService.ensureProductImagesBackfilled();
      if (rehosted > 0 && mounted) {
        final refreshed = await SupabaseService.fetchInventory();
        if (!mounted) return;
        setState(() {
          _items =
              refreshed.map((item) => MedicineItem.fromMap(item)).toList();
        });
      }
    } catch (e) {
      debugPrint('Fetch inventory error: $e');
      if (mounted) {
        AppToast.error(context, 'Failed to load inventory: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openManualAddItem() async {
    await ManualAddItemScreen.show(context);
    if (!mounted) return;
    await _loadInventory();
  }

  Future<void> _editItem(MedicineItem item) async {
    final result = await ManualAddItemScreen.show(context, existingItem: item);
    if (result == true && mounted) {
      await _loadInventory();
    }
  }

  Future<void> _openReports() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ReportsScreen()),
    );
    if (!mounted) return;
    await _loadInventory();
  }

  Future<void> _deleteItem(MedicineItem item) async {
    if (!_canManageInventory) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text('Remove "${item.productName}" from inventory?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await SupabaseService.deleteItem(item.id);
      await _loadInventory();
      if (!mounted) return;
      AppToast.success(context, 'Item deleted successfully.');
    } catch (e) {
      debugPrint('Delete error: $e');
      if (!mounted) return;
      AppToast.error(context, 'Failed to delete item: $e');
    }
  }

  Future<void> _deleteSelectedItems() async {
    if (!_canManageInventory || _selectedItems.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Selected Items'),
        content: Text(
          'Remove ${_selectedItems.length} selected item(s) from inventory?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final ids = List<int>.from(_selectedItems);
      for (final id in ids) {
        await SupabaseService.deleteItem(id);
      }
      await _loadInventory();
      if (!mounted) return;
      AppToast.success(context, '${ids.length} item(s) deleted successfully.');
    } catch (e) {
      debugPrint('Bulk delete error: $e');
      if (!mounted) return;
      AppToast.error(context, 'Failed to delete selected items: $e');
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    if (!mounted) return;
    await _loadInventory();
  }

  void _showDetails(MedicineItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette(isDark);

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

    final otherBatches = _otherBatchesLabel(item);

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: p.cardBg,
        surfaceTintColor: p.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.imageUrl != null && item.imageUrl!.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      item.imageUrl!,
                      width: double.infinity,
                      height: 120,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Text(
                  item.productName,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: p.textPrimary,
                  ),
                ),
                if (otherBatches != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    otherBatches,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? kWarningOrange
                          : Colors.orange.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _detailRow('Category', item.category, p),
                _detailRow('Expiry Date', item.fullExpiryLabel, p),
                _detailRow('Quantity', item.formattedQuantity, p),
                _detailRow('Status', statusLabel, p, valueColor: statusColor),
                if (_canManageInventory) ...[
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        _deleteItem(item);
                      },
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      label: const Text(
                        'Delete Item',
                        style: TextStyle(color: Colors.red),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
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

  List<MedicineItem> get _filtered {
    final search = _searchQuery.trim().toLowerCase();

    final result = _items.where((item) {
      final matchesSearch = item.productName.toLowerCase().contains(search) ||
          item.category.toLowerCase().contains(search);

      final matchesCategory = _selectedCategoryFilter == 'All Categories'
          ? true
          : item.category == _selectedCategoryFilter;

      final matchesStatus = switch (_selectedStatusFilter) {
        'Safe' => item.status == ExpiryStatus.safe,
        'Expired' => item.status == ExpiryStatus.expired,
        'Expiring' => item.status == ExpiryStatus.warning,
        _ => true,
      };

      return matchesSearch && matchesCategory && matchesStatus;
    }).toList();

    return result;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Status filter chips (mobile) ────────────────────────────────────────
  //
  // Mirrors _selectedStatusFilter (already used by the web dropdown) so
  // both layouts stay in sync — tapping a chip here filters the same way
  // picking a status from the web dropdown does.

  Widget _buildStatusFilterChips(AppPalette p) {
    final entries = _statusChipLabels.entries.toList();

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final value = entries[index].key;
          final label = entries[index].value;
          final selected = _selectedStatusFilter == value;

          return GestureDetector(
            onTap: () => setState(() => _selectedStatusFilter = value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? kPrimaryBlue : p.searchBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? kPrimaryBlue : p.cardBorder,
                ),
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : p.textSecondary,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = kIsWeb;

    if (isWeb) {
      return _buildWebLayout(context);
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette(isDark);

    return Scaffold(
      backgroundColor: p.scaffoldBg,
      appBar: AppBar(
        backgroundColor: p.appBarBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: p.textPrimary),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          'Inventory Report',
          style: TextStyle(
            color: p.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        // ← No more export icon in the AppBar.
      ),
      body: Column(
        children: [
          Container(
            color: p.appBarBg,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: p.searchBg,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: p.cardBorder),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Search icon, pinned to the left — doesn't affect
                        // the text field's layout width.
                        Positioned(
                          left: 14,
                          child: Icon(Icons.search, color: p.textSecondary, size: 20),
                        ),
                        // Text field fills the full pill; textAlignVertical
                        // centers the caret/text vertically within the 44px
                        // height (padding alone doesn't guarantee this),
                        // and textAlign + symmetric horizontal padding
                        // center it horizontally within the pill.
                        TextField(
                          controller: _searchController,
                          textAlign: TextAlign.center,
                          textAlignVertical: TextAlignVertical.center,
                          style: TextStyle(color: p.textPrimary),
                          onChanged: (value) {
                            setState(() => _searchQuery = value);
                          },
                          decoration: InputDecoration(
                            isCollapsed: true,
                            hintText: 'Search by Medicine Name',
                            hintStyle: TextStyle(color: p.textSecondary, fontSize: 14),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 40,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // ── Export button (replaces the old refresh button) ──
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: p.searchBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.cardBorder),
                  ),
                  child: IconButton(
                    tooltip: 'Export Report',
                    icon: SvgPicture.string(
                      _svgExport,
                      width: 20,
                      height: 20,
                      colorFilter: ColorFilter.mode(
                        p.textSecondary,
                        BlendMode.srcIn,
                      ),
                    ),
                    onPressed: _openReports,
                  ),
                ),
              ],
            ),
          ),
          // ── Status filter chips ──────────────────────────────────────────
          Container(
            color: p.appBarBg,
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildStatusFilterChips(p),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'TOTAL ITEMS (${_filtered.length})',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: p.textSecondary,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const BrandedLoading(label: 'Loading inventory...')
                : _filtered.isEmpty
                    ? RefreshIndicator(
                        onRefresh: _loadInventory,
                        child: ListView(
                          children: [
                            const SizedBox(height: 80),
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.inbox_outlined,
                                    size: 120,
                                    color: p.textSecondary.withOpacity(0.4),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No items found.',
                                    style: TextStyle(color: p.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadInventory,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, index) {
                            final item = _filtered[index];

          final card = _MedicineCard(
  item: item,
  onTap: () => _showDetails(item),
  otherBatchesLabel: _otherBatchesLabel(item),
);

// Show the swipe actions for any signed-in user. Staff get Edit only;
// Managers get Edit + Delete (toggled inside _SwipeActions via
// showDelete).
return _SwipeActions(
  key: ValueKey('swipe_${item.id}'),
  onEdit: () => _editItem(item),
  onDelete: () => _deleteItem(item),
  showDelete: _canManageInventory,
  child: card,
);
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'addItemFab',
        onPressed: _openManualAddItem,
        backgroundColor: kPrimaryBlue,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        tooltip: 'Add item manually',
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 2),
    );
  }

  Widget _buildDropdown<T>(
    String defaultLabel,
    T value,
    List<T> items,
    ValueChanged<T?> onChanged, {
    required double width,
    required AppPalette p,
  }) {
    final isSelected = value.toString() != defaultLabel;

    return Container(
      width: width,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: p.cardBg,
        border: Border.all(
          color: isSelected ? kPrimaryBlue : p.cardBorder,
          width: isSelected ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          dropdownColor: p.cardBg,
          isExpanded: true,
          items: items.map((item) {
            final isItemSelected = item == value;
            return DropdownMenuItem<T>(
              value: item,
              child: Text(
                item.toString(),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: isItemSelected ? kPrimaryBlue : p.textPrimary,
                  fontWeight:
                      isItemSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            );
          }).toList(),
          onChanged: onChanged,
          icon: Icon(
            Icons.arrow_drop_down,
            size: 20,
            color: isSelected ? kPrimaryBlue : p.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildWebLayout(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette(isDark);
    final filtered = _filtered;

    final allFilteredSelected = filtered.isNotEmpty &&
        filtered.every((item) => _selectedItems.contains(item.id));

    return WebShell(
      activeRoute: 'inventory',
      photoUrl: _userPhotoUrl,
      displayName: _userDisplayName,
      headerBar: WebTopBar(
        pageTitle: 'Inventory Report',
        pageSubtitle: '${_items.length} products registered',
        hasUnread: _hasUnread,
        photoUrl: _userPhotoUrl,
        displayName: _userDisplayName,
        roleLabel: _userRoleLabel,
        initials: _getInitials(_userDisplayName),
        onBellTap: _openNotifications,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Only show the wide desktop table when there's real room.
          // Below this, the table is wrapped in a horizontal scroll view
          // so columns keep their natural widths instead of squeezing.
          final wideContent = constraints.maxWidth >= 900;

          // WebShell's own narrow top bar has no bottom spacing before the
          // page content, so add a gap here to match the wide layout's
          // headerBar breathing room.
          final isNarrowShell = MediaQuery.of(context).size.width < 1024;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isNarrowShell) const SizedBox(height: 16),

              // SEARCH + ADD ITEM
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Container(
                      height: 44,
                      constraints: const BoxConstraints(
                        maxWidth: 900,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: p.searchBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: p.cardBorder,
                        ),
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
                              onChanged: (value) {
                                setState(() {
                                  _searchQuery = value;
                                });
                              },
                              decoration: InputDecoration(
                                hintText: 'Search inventory...',
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

                  ElevatedButton(
                    onPressed: _openManualAddItem,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                    ),
                    child: const Text(
                      'Add Item',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // FILTERS  (the Default / sort dropdown has been removed.)
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _buildDropdown<String>(
                    'All Categories',
                    _selectedCategoryFilter,
                    _categoryOptions,
                    (value) {
                      if (value == null) return;

                      setState(() {
                        _selectedCategoryFilter = value;
                      });
                    },
                    width: 160,
                    p: p,
                  ),

                  _buildDropdown<String>(
                    'All Status',
                    _selectedStatusFilter,
                    _statusOptions,
                    (value) {
                      if (value == null) return;

                      setState(() {
                        _selectedStatusFilter = value;
                      });
                    },
                    width: 140,
                    p: p,
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // BULK DELETE
              if (_canManageInventory && _selectedItems.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: p.cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: p.cardBorder,
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${_selectedItems.length} selected',
                        style: TextStyle(
                          color: p.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _deleteSelectedItems,
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 18,
                        ),
                        label: const Text('Delete Selected'),
                      ),
                    ],
                  ),
                ),

              if (_canManageInventory && _selectedItems.isNotEmpty)
                const SizedBox(height: 16),

              // INVENTORY TABLE
              // Wraps the table in a horizontal scroll on narrow widths
              // so columns keep their natural size instead of squeezing
              // into vertical letters.
              Container(
                decoration: BoxDecoration(
                  color: p.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: p.cardBorder,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(
                          child: BrandedLoader(),
                        ),
                      )
                    : filtered.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(40),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.inbox_outlined,
                                    size: 96,
                                    color: p.textSecondary.withOpacity(0.4),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No inventory items found.',
                                    style: TextStyle(
                                      color: p.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : wideContent
                            // Wide desktop — render the full table.
                            ? Column(
                                children: [
                                  _buildTableHeader(
                                    filtered,
                                    allFilteredSelected,
                                    p,
                                  ),
                                  ...filtered.asMap().entries.map(
                                    (entry) => _buildTableRow(
                                      entry.key,
                                      entry.value,
                                      p,
                                    ),
                                  ),
                                ],
                              )
                            // Narrow / mobile browser — same card list the
                            // native app uses, instead of a cramped table
                            // that needs horizontal scrolling to read.
                            : Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  children: [
                                    for (final item in filtered) ...[
                                      Builder(
                                        builder: (context) {
                                          final card = _MedicineCard(
                                            item: item,
                                            onTap: () => _showDetails(item),
                                            otherBatchesLabel:
                                                _otherBatchesLabel(item),
                                          );

                                         return _SwipeActions(
  key: ValueKey(
    'web_swipe_${item.id}',
  ),
  onEdit: () => _editItem(item),
  onDelete: () => _deleteItem(item),
  showDelete: _canManageInventory,
  child: card,
);
                                        },
                                      ),
                                      const SizedBox(height: 10),
                                    ],
                                  ],
                                ),
                              ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTableHeader(
    List<MedicineItem> filtered,
    bool allFilteredSelected,
    AppPalette p,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.cardBorder)),
      ),
      child: Row(
        children: [
          if (_canManageInventory)
            SizedBox(
              width: 44,
              child: Checkbox(
                value: allFilteredSelected,
                onChanged: (checked) {
                  setState(() {
                    if (checked == true) {
                      _selectedItems
                          .addAll(filtered.map((item) => item.id));
                    } else {
                      _selectedItems
                          .removeAll(filtered.map((item) => item.id));
                    }
                  });
                },
              ),
            ),
          if (_canManageInventory) const SizedBox(width: 8),
          SizedBox(
            width: 30,
            child: Text('#', style: _headerStyle(p)),
          ),
          const SizedBox(width: 38),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text('Product Name', style: _headerStyle(p)),
          ),
          SizedBox(
            width: 110,
            child: Text('Category', style: _headerStyle(p)),
          ),
          Expanded(
            flex: 2,
            child: Text('Expiry Date', style: _headerStyle(p)),
          ),
          Expanded(
            flex: 2,
            child: Text('Days Remaining', style: _headerStyle(p)),
          ),
          Expanded(
            flex: 1,
            child: Text('Qty', style: _headerStyle(p)),
          ),
          Expanded(
            flex: 2,
            child: Text('Status', style: _headerStyle(p)),
          ),
          if (_canEditInventory || _canManageInventory)
            SizedBox(
              width: 64,
              child: Text(
                'Actions',
                style: _headerStyle(p),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTableRow(int index, MedicineItem item, AppPalette p) {
    final isSelected = _selectedItems.contains(item.id);

    final statusColor = switch (item.status) {
      ExpiryStatus.expired => kDangerRed,
      ExpiryStatus.warning => kWarningOrange,
      ExpiryStatus.safe => kSafeGreen,
    };

    final statusLabel = switch (item.status) {
      ExpiryStatus.expired => 'EXPIRED',
      ExpiryStatus.warning => 'EXPIRING',
      ExpiryStatus.safe => 'SAFE',
    };

    final otherBatches = _otherBatchesLabel(item);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _showDetails(item),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: p.rowDivider),
              left: BorderSide(
                color: item.status == ExpiryStatus.expired
                    ? statusColor
                    : Colors.transparent,
                width: 3,
              ),
            ),
            color: isSelected
                ? kPrimaryBlue.withOpacity(0.06)
                : Colors.transparent,
          ),
          child: Row(
            children: [
              if (_canManageInventory)
                SizedBox(
                  width: 44,
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (checked) {
                      setState(() {
                        if (checked == true) {
                          _selectedItems.add(item.id);
                        } else {
                          _selectedItems.remove(item.id);
                        }
                      });
                    },
                  ),
                ),
              if (_canManageInventory) const SizedBox(width: 8),
              SizedBox(
                width: 30,
                child: Text(
                  (index + 1).toString().padLeft(2, '0'),
                  style: TextStyle(color: p.textSecondary),
                ),
              ),
              SizedBox(
                width: 38,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                      ? Image.network(
                          item.imageUrl!,
                          width: 36,
                          height: 36,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _fallbackIcon(p),
                        )
                      : _fallbackIcon(p),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.productName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.textPrimary),
                    ),
                    if (otherBatches != null)
                      Text(
                        otherBatches,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: p.isDark
                              ? kWarningOrange
                              : Colors.orange.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: 110,
                child: Text(
                  item.category,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.textPrimary),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  item.fullExpiryLabel,
                  style: TextStyle(color: p.textPrimary),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  item.daysRemainingLabel,
                  style: TextStyle(
                    color: item.status == ExpiryStatus.expired
                        ? kDangerRed
                        : p.textPrimary,
                  ),
                ),
              ),
              Expanded(
                flex: 1,
                child: Text(
                  item.formattedQuantity,
                  style: TextStyle(color: p.textPrimary),
                ),
              ),
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      statusLabel,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              if (_canEditInventory || _canManageInventory)
                SizedBox(
                  width: 64,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_canEditInventory)
                        IconButton(
                          tooltip: 'Edit item',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(
                            Icons.edit_outlined,
                            size: 18,
                            color: kPrimaryBlue,
                          ),
                 onPressed: () async {
  if (!_canEditInventory) return;
  final saved = await ManualAddItemScreen.show(
    context,
    existingItem: item,
  );
  if (saved == true && mounted) {
    await _loadInventory();
  }
},
                        ),
                      if (_canManageInventory)
                        IconButton(
                          tooltip: 'Delete item',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: Colors.red,
                          ),
                          onPressed: () => _deleteItem(item),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _getInitials(String? name) {
    if (name == null || name.trim().isEmpty) return 'AC';

    final parts = name.trim().split(RegExp(r'\s+'));

    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }

    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  Widget _fallbackIcon(AppPalette p) {
    return Container(
      width: 36,
      height: 36,
      color: p.fallbackThumbBg,
      child: const Icon(
        Icons.medication_outlined,
        color: kPrimaryBlue,
        size: 16,
      ),
    );
  }
}

TextStyle _headerStyle(AppPalette p) => TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: p.textSecondary,
    );

// ─────────────────────────────────────────────────────────────────────
// Swipe-to-reveal actions (mobile only)
// ─────────────────────────────────────────────────────────────────────
class _SwipeActions extends StatefulWidget {
  final Widget child;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// When false, only the Edit action is shown on swipe — used for
  /// Staff accounts so they can edit but not delete inventory items.
  final bool showDelete;

  const _SwipeActions({
    super.key,
    required this.child,
    required this.onEdit,
    required this.onDelete,
    this.showDelete = true,
  });

  @override
  State<_SwipeActions> createState() => _SwipeActionsState();
}

class _SwipeActionsState extends State<_SwipeActions> {
  static const double _actionWidth = 76;

  double get _totalActions =>
      widget.showDelete ? _actionWidth * 2 : _actionWidth;

  double _dragOffset = 0;
  bool _open = false;

  void _close() {
    if (!_open) return;
    setState(() {
      _open = false;
      _dragOffset = 0;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    final next = (_dragOffset + delta).clamp(-_totalActions, 0.0);
    setState(() => _dragOffset = next);
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final shouldOpen = _dragOffset < -_totalActions / 2 || velocity < -300;
    setState(() {
      _open = shouldOpen;
      _dragOffset = shouldOpen ? -_totalActions : 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette(isDark);

    return GestureDetector(
      onTap: _open ? _close : null,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _actionButton(
                      icon: Icons.edit_outlined,
                      label: 'Edit',
                      color: kPrimaryBlue,
                      onTap: () {
                        _close();
                        widget.onEdit();
                      },
                    ),
                    if (widget.showDelete)
                      _actionButton(
                        icon: Icons.delete_outline,
                        label: 'Delete',
                        color: Colors.red.shade600,
                        onTap: () {
                          _close();
                          widget.onDelete();
                        },
                      ),
                  ],
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(_dragOffset, 0, 0),
              child: widget.child,
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: _actionWidth,
        height: double.infinity,
        color: color,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MedicineCard extends StatelessWidget {
  final MedicineItem item;
  final VoidCallback onTap;
  final String? otherBatchesLabel;

  const _MedicineCard({
    required this.item,
    required this.onTap,
    this.otherBatchesLabel,
  });

  Color get _statusColor => switch (item.status) {
        ExpiryStatus.expired => kDangerRed,
        ExpiryStatus.warning => kWarningOrange,
        ExpiryStatus.safe => kSafeGreen,
      };

  String get _statusLabel => switch (item.status) {
        ExpiryStatus.expired => 'EXPIRED',
        ExpiryStatus.warning => 'EXPIRING',
        ExpiryStatus.safe => 'SAFE',
      };

  Widget _thumbnail(AppPalette p) {
    final url = item.imageUrl;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: url != null && url.isNotEmpty
          ? Image.network(
              url,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallback(p),
            )
          : _fallback(p),
    );
  }

  Widget _fallback(AppPalette p) {
    return Container(
      width: 56,
      height: 56,
      color: p.fallbackThumbBg,
      child: const Icon(
        Icons.medication_outlined,
        color: kPrimaryBlue,
        size: 24,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette(isDark);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: p.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.20 : 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 90,
              decoration: BoxDecoration(
                color: _statusColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: _thumbnail(p),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.productName,
                            style: TextStyle(
                              fontSize: 15,
                              color: p.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusBadge(
                          label: _statusLabel,
                          color: _statusColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.category,
                      style: TextStyle(
                        fontSize: 12,
                        color: p.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 12,
                          color: isDark
                              ? kPrimaryBlue
                              : Colors.blue.shade400,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Exp: ${item.formattedExpiry}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? kPrimaryBlue
                                : Colors.blue.shade400,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    if (otherBatchesLabel != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        otherBatchesLabel!,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? kWarningOrange
                              : Colors.orange.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(Icons.chevron_right, color: p.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}