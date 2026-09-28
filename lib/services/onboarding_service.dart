import 'package:shared_preferences/shared_preferences.dart';

class OnboardingService {
  static const _scanInstructionsKey = 'hasSeenScanInstructions';

  /// Whether the user has already gone through the scan instructions once.
  static Future<bool> hasSeenScanInstructions() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_scanInstructionsKey) ?? false;
  }

  /// Call this once the user proceeds past the scan instructions screen.
  static Future<void> markScanInstructionsSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_scanInstructionsKey, true);
  }
}