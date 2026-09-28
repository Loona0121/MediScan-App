import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'notification_service.dart';
import 'supabase_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PushNotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    print('🔔 Initializing Local Notifications...');

    _initLocalNotifications();

    final androidImplementation = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final androidGranted = await androidImplementation?.requestNotificationsPermission();
    print('🔔 Android local notification permission granted: $androidGranted');
  }

  static void _initLocalNotifications() {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings();

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    _localNotifications.initialize(settings);
  }

  static Future<void> updateInAppBadge() async {
    await NotificationService.instance.refresh();
  }

  // ===== NOTIFICATIONS ENABLED FLAG =====
  static const _notificationsEnabledPref = 'notifications_enabled';

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notificationsEnabledPref) ?? true;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationsEnabledPref, enabled);
  }

  // ===== SEND EXPIRY ALERT =====
  static Future<void> sendExpiryAlert({
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    if (!await isEnabled()) return;   // ← gate

    try {
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
            'mediscan_channel',
            'MediScan Notifications',
            channelDescription: 'Notifications from MediScan',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          );

      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(),
      );

      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        details,
      );

      await SupabaseService.saveNotification(
        title: title,
        body: body,
        type: 'expiry_alert',
      );

      await updateInAppBadge();

    } catch (e) {
      print('❌ Failed to send expiry alert: $e');
    }
  }

  // ===== DATE PARSING HELPER =====
  static DateTime? _parseExpiry(String expiryDateStr) {
    final parts = expiryDateStr.split('-');
    if (parts.length < 2) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null) return null;
    final day = parts.length >= 3 ? int.tryParse(parts[2]) ?? 1 : 1;
    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  // ===== PER-ITEM DEDUPLICATION =====
  static const _notifiedKeysPref = 'notified_expiry_keys';
  static const _notifiedDatePref = 'notified_expiry_date';

  static String _todayStr() {
    final t = DateTime.now();
    return '${t.year}-${t.month}-${t.day}';
  }

  static String _productKey(dynamic product) {
    if (product is Map) {
      final id = product['id']?.toString();
      if (id != null && id.isNotEmpty) return 'id:$id';
      final name = product['product_name'] ?? '';
      final exp  = product['expiry_date'] ?? '';
      return 'ne:$name|$exp';
    }
    return 'ne:${product.productName}|${product.expiryDate}';
  }

  static Future<Set<String>> _notifiedToday() async {
    final prefs = await SharedPreferences.getInstance();
    final storedDate = prefs.getString(_notifiedDatePref);
    if (storedDate != _todayStr()) {
      await prefs.remove(_notifiedKeysPref);
      await prefs.setString(_notifiedDatePref, _todayStr());
      return <String>{};
    }
    return (prefs.getStringList(_notifiedKeysPref) ?? const []).toSet();
  }

  static Future<void> _markNotified(Set<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await _notifiedToday();
    existing.addAll(keys);
    await prefs.setStringList(_notifiedKeysPref, existing.toList());
    await prefs.setString(_notifiedDatePref, _todayStr());
  }

  // ===== CHECK AND SEND EXPIRY ALERTS =====
  static Future<void> checkAndSendExpiryAlerts(List<dynamic> products) async {
    try {
      final alreadyNotified = await _notifiedToday();

      final now = DateTime.now();
      final expiringProducts = <Map<String, dynamic>>[];
      final expiredProducts  = <Map<String, dynamic>>[];
      final newKeys          = <String>{};

      for (var product in products) {
        final key = _productKey(product);
        if (alreadyNotified.contains(key)) continue;

        String productName;
        String expiryDateStr;
        String category;

        if (product is Map) {
          productName   = product['product_name'] ?? '';
          expiryDateStr = product['expiry_date'] ?? '';
          category      = product['category'] ?? '';
        } else {
          productName   = product.productName;
          expiryDateStr = product.expiryDate;
          category      = product.category;
        }

        if (expiryDateStr.isEmpty) continue;

        final expiryDate = _parseExpiry(expiryDateStr);
        if (expiryDate == null) continue;

        final daysRemaining = expiryDate.difference(now).inDays;

        final productData = {
          'name': productName,
          'category': category,
          'daysRemaining': daysRemaining,
          'expiryDate': expiryDate,
        };

        if (daysRemaining < 0) {
          expiredProducts.add(productData);
          newKeys.add(key);
        } else if (daysRemaining <= 30) {
          expiringProducts.add(productData);
          newKeys.add(key);
        }
      }

      bool sentAny = false;

      if (expiredProducts.isNotEmpty) {
        final count = expiredProducts.length;
        final names = expiredProducts.map((p) => p['name'] as String).toList();
        final daysAgo = (expiredProducts.first['daysRemaining'] as int).abs();

        String title;
        String body;

        if (count == 1) {
          title = '🚨 URGENT: 1 Product Has EXPIRED!';
          body = '${names.first} expired ${daysAgo} day${daysAgo > 1 ? 's' : ''} ago. Immediate action required!';
        } else {
          title = '🚨 URGENT: $count Products Have EXPIRED!';
          body = '${names.take(3).join(', ')}${count > 3 ? '...' : ''} - Check inventory now!';
        }

        await sendExpiryAlert(title: title, body: body);
        sentAny = true;
      }

      if (expiringProducts.isNotEmpty) {
        final count = expiringProducts.length;
        final names = expiringProducts.map((p) => p['name'] as String).toList();
        final daysLeft = (expiringProducts.first['daysRemaining'] as int);

        String title;
        String body;

        if (count == 1) {
          title = '⚠️ REMINDER: 1 Product Expiring Soon';
          body = '${names.first} will expire in $daysLeft day${daysLeft > 1 ? 's' : ''}. Please check inventory.';
        } else {
          title = 'REMINDER: $count Products Expiring Soon';
          body = '${names.take(3).join(', ')}${count > 3 ? '...' : ''} - Please check inventory.';
        }

        await sendExpiryAlert(title: title, body: body);
        sentAny = true;
      }

      if (sentAny) {
        await _markNotified(newKeys);
      }

    } catch (e) {
      print('❌ Error checking expiry alerts: $e');
    }
  }
}