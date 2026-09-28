import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global theme mode notifier. main.dart listens to this via
/// ValueListenableBuilder so changing it anywhere in the app immediately
/// updates the whole MaterialApp.
final ValueNotifier<ThemeMode> themeModeNotifier =
    ValueNotifier(ThemeMode.light);

class ThemeService {
  static const _key = 'theme_mode';

  static Future<void> loadSavedTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    switch (saved) {
      case 'dark':
        themeModeNotifier.value = ThemeMode.dark;
        break;
      case 'system':
        themeModeNotifier.value = ThemeMode.system;
        break;
      default:
        themeModeNotifier.value = ThemeMode.light;
    }
  }

  static Future<void> setTheme(ThemeMode mode) async {
    themeModeNotifier.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }

  static String labelFor(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'Dark Mode';
      case ThemeMode.system:
        return 'System Default';
      case ThemeMode.light:
        return 'Light Mode';
    }
  }

  /// Convenience for the header icon: flips between light and dark.
  /// If the current mode is `system`, it resolves against the platform
  /// brightness and picks the *opposite* of what's currently showing, so
  /// the user's tap always produces a visible change.
  static Future<void> toggle(BuildContext context) async {
    final current = themeModeNotifier.value;
    if (current == ThemeMode.system) {
      final platformIsDark =
          MediaQuery.of(context).platformBrightness == Brightness.dark;
      await setTheme(platformIsDark ? ThemeMode.light : ThemeMode.dark);
      return;
    }
    await setTheme(
      current == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
    );
  }

  /// Resolves the effective brightness for a given BuildContext, taking
  /// `ThemeMode.system` into account. Used by the header icon to decide
  /// which SVG to show.
  static bool isDark(BuildContext context) {
    final mode = themeModeNotifier.value;
    if (mode == ThemeMode.system) {
      return MediaQuery.of(context).platformBrightness == Brightness.dark;
    }
    return mode == ThemeMode.dark;
  }
}