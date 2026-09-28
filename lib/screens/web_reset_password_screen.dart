// lib/screens/web_reset_password_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'complete_invite.dart';

class WebResetPasswordScreen extends StatefulWidget {
  const WebResetPasswordScreen({super.key});

  @override
  State<WebResetPasswordScreen> createState() =>
      _WebResetPasswordScreenState();
}

class _WebResetPasswordScreenState extends State<WebResetPasswordScreen> {
  StreamSubscription<AuthState>? _authSub;
  Timer? _timeoutTimer;

  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _listenForAuthResult();
  }

  void _listenForAuthResult() {
    final auth = Supabase.instance.client.auth;

    // If a session already exists by the time this screen builds
    // (e.g. supabase_flutter finished parsing the URL before we
    // attached the listener), handle it immediately.
    final existingSession = auth.currentSession;
    if (existingSession != null) {
      _onVerified(existingSession);
      return;
    }

    // Otherwise, wait for the auth state to change as the SDK
    // finishes parsing the invite token from the URL.
    _authSub = auth.onAuthStateChange.listen(
      (data) {
        final session = data.session;
        if (session != null) {
          _onVerified(session);
        }
      },
      onError: (error) {
        _onFailed(_friendlyMessage(error.toString()));
      },
    );

    // Supabase never explicitly tells us "this token is expired" via
    // the stream — an expired/invalid link simply never produces a
    // session. So if nothing happens within a few seconds, treat it
    // as expired/invalid rather than spinning forever.
    _timeoutTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted || _hasError) return;
      if (Supabase.instance.client.auth.currentSession == null) {
        _onFailed(
          'This invite link has expired or is invalid. '
          'Please ask your admin to send you a new invite.',
        );
      }
    });
  }

  void _onVerified(Session session) {
    if (!mounted) return;
    _authSub?.cancel();
    _timeoutTimer?.cancel();

    final email = session.user.email ?? '';
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CompleteInviteScreen(email: email),
      ),
    );
  }

  void _onFailed(String message) {
    if (!mounted) return;
    _authSub?.cancel();
    _timeoutTimer?.cancel();
    setState(() {
      _hasError = true;
      _errorMessage = message;
    });
  }

  String _friendlyMessage(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('expired') || lower.contains('invalid') ||
        lower.contains('token')) {
      return 'This invite link has expired or is invalid. '
          'Please ask your admin to send you a new invite.';
    }
    return 'Something went wrong verifying your invite link. '
        'Please try again or ask your admin to resend it.';
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _hasError ? _buildErrorState() : _buildLoadingState(),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text('Verifying your link...'),
      ],
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFDC2626), size: 40),
          const SizedBox(height: 16),
          const Text(
            'Link Expired',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E3A8A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}