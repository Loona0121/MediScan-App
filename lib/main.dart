import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';
import 'screens/dashboard.dart';
import 'screens/reset_password.dart';
import 'screens/complete_invite.dart';
import 'services/push_notification_service.dart';
import 'services/theme_service.dart';
import 'screens/web_reset_password_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'screens/login.dart';
import 'screens/signup.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'services/background_tasks.dart';
import 'constants/env.dart';

// Global navigator key so both the mobile deep-link handler and the web
// auth-redirect listener can push a screen from outside the widget tree.
final navigatorKey = GlobalKey<NavigatorState>();

void main() async {

  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    usePathUrlStrategy();
  }

  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.implicit,
    ),
  );

  await PushNotificationService.initialize();

  // Load the persisted theme choice BEFORE runApp so the app boots
  // straight into the user's preferred mode.
  await ThemeService.loadSavedTheme();

 if (!kIsWeb) {
  await BackgroundTasks.initialize();
}

  // Mobile: custom-scheme deep links (mediscan://reset-password...).
  _initDeepLinkListener();

  // Web: supabase_flutter auto-parses the session from the page's own
  // URL fragment/query on load (that's what implicit flow does), then
  // fires this event. AppLinks doesn't cover this case, so it needs its
  // own listener rather than reusing _handleDeepLink.
  if (kIsWeb) {
    _initWebAuthRedirectListener();
  }

  runApp(const MyApp());
}

void _initDeepLinkListener() {
  final appLinks = AppLinks();

  appLinks.getInitialLink().then((uri) {
    if (uri != null) {
      _handleDeepLink(uri);
    }
  });

  appLinks.uriLinkStream.listen(_handleDeepLink);
}

Future<void> _handleDeepLink(Uri uri) async {
  final isRecognizedLink = uri.scheme == 'mediscan' ||
      (uri.scheme == 'https' && uri.host == 'app.mediscan.space');
  if (!isRecognizedLink) return;

  try {
    await Supabase.instance.client.auth.getSessionFromUrl(uri);

    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email == null) return;

    final type = uri.queryParameters['type'] ??
        Uri.splitQueryString(uri.fragment)['type'];

    _routeAfterAuthLink(type: type, email: email);
  } catch (e) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This invite link is invalid or has expired. Please ask your admin to resend it.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

// Web: no custom-scheme uri to inspect, so `type` has to be read off the
// real browser URL (Uri.base) instead — same param, different source.
void _initWebAuthRedirectListener() {
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    if (data.event != AuthChangeEvent.passwordRecovery) return;

    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email == null) return;

    final uri = Uri.base;
    final fragmentParams = Uri.splitQueryString(uri.fragment);
    final type = uri.queryParameters['type'] ?? fragmentParams['type'];

    _routeAfterAuthLink(type: type, email: email);
  });
}

// Shared by both platforms once a session has been established from a
// recovery/invite link — only the source of `type` differs above.
void _routeAfterAuthLink({required String? type, required String email}) {
  if (type == 'invite') {
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => CompleteInviteScreen(email: email)),
      (route) => false,
    );
  } else {
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => ResetPasswordScreen(email: email)),
      (route) => false,
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'MediScan',
          themeMode: mode,
          routes: {
            '/dashboard': (context) => const Dashboard(),
            '/reset-password': (context) => const WebResetPasswordScreen(),
            '/accept-invite': (context) => const WebResetPasswordScreen(),
            '/login': (context) => const Login(),
          },
          // ── Light theme ──
          theme: ThemeData(
            brightness: Brightness.light,
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: const Color(0xFFF8FAFC),
            textTheme: GoogleFonts.poppinsTextTheme(ThemeData.light().textTheme),
            dialogTheme: const DialogThemeData(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
            ),
            popupMenuTheme: const PopupMenuThemeData(
              color: Colors.white,
              surfaceTintColor: Colors.white,
            ),
          ),
          // ── Dark theme ──
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: const Color(0xFF0B1220),
            textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
            dialogTheme: const DialogThemeData(
              backgroundColor: Color(0xFF1E293B),
              surfaceTintColor: Color(0xFF1E293B),
            ),
            popupMenuTheme: const PopupMenuThemeData(
              color: Color(0xFF1E293B),
              surfaceTintColor: Color(0xFF1E293B),
            ),
          ),
          home: const Login(),
        );
      },
    );
  }
}