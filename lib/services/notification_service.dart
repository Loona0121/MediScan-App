import 'package:flutter/material.dart';
import 'supabase_service.dart';

class NotificationService extends ChangeNotifier {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  bool _hasUnread = false;

  bool get hasUnread => _hasUnread;

  Future<void> refresh() async {
    final unread = await SupabaseService.hasUnreadNotifications();

    if (_hasUnread != unread) {
      _hasUnread = unread;
      notifyListeners();
    }
  }
}