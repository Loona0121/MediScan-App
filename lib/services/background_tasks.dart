import 'package:workmanager/workmanager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';
import 'push_notification_service.dart';
import '../constants/env.dart';


// ─────────────────────────────────────────────────────────────────
// WorkManager background task — periodically checks inventory for
// expiring/expired items even when the app isn't open, so alerts
// don't depend on the user happening to reload the Dashboard.
// ─────────────────────────────────────────────────────────────────

const String kExpiryCheckTaskName = 'mediscan_expiry_check';
const String kExpiryCheckTaskUniqueName = 'mediscan_expiry_check_periodic';

/// Entry point for the background isolate. WorkManager runs this in
/// a completely separate isolate from your running app — it does NOT
/// share the already-initialized Supabase client from main(), so
/// everything this callback needs must be set up from scratch here.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // Re-initialize Supabase in this isolate. Use the SAME url/anon
      // key you pass in your main() Supabase.initialize() call —
      // copy them from wherever that currently lives (likely
      // main.dart or a config/constants file).
      await Supabase.initialize(
        url: 'Env.supabaseUrl',
        anonKey: 'Env.supabaseAnonKey',
      );

      switch (task) {
        case kExpiryCheckTaskName:
          final data = await SupabaseService.fetchInventory();
          await PushNotificationService.checkAndSendExpiryAlerts(data);
          break;
      }

      return Future.value(true);
    } catch (e) {
      // Returning false tells WorkManager the task failed so it can
      // retry on its own backoff policy instead of silently dropping it.
      print('❌ Background expiry check failed: $e');
      return Future.value(false);
    }
  });
}

class BackgroundTasks {
  /// Call once from main(), BEFORE runApp(). Sets up the WorkManager
  /// plugin and registers the periodic expiry check.
  static Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false, // set true temporarily while testing
    );

    await Workmanager().registerPeriodicTask(
      kExpiryCheckTaskUniqueName,
      kExpiryCheckTaskName,
      // Android enforces a 15-minute floor on periodic tasks — anything
      // shorter is silently clamped to 15 by the OS.
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 5),
    );
  }

  /// Useful for a manual "check now" debug button, or to trigger a
  /// one-off check right after a manual add-item save.
  static Future<void> runOnceNow() async {
    await Workmanager().registerOneOffTask(
      '${kExpiryCheckTaskUniqueName}_manual_${DateTime.now().millisecondsSinceEpoch}',
      kExpiryCheckTaskName,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  static Future<void> cancelAll() async {
    await Workmanager().cancelAll();
  }
}