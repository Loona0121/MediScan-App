import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'login.dart';
import 'dashboard.dart';
import '../services/session_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const Color _blue = Color(0xFF3C83F6);

  @override
  void initState() {
    super.initState();
    _decideDestination();
  }

  Future<void> _decideDestination() async {
    // Runs the login check WHILE the splash screen is still showing,
    // so the destination is already known by the time we navigate —
    // Login never gets a chance to flash on screen for logged-in users.
    final isLoggedIn = await SessionService.isLoggedIn;

    // Keep the delay so the splash is still visible for a beat, rather
    // than an instant flash-through on fast devices/cached sessions.
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => isLoggedIn ? const Dashboard() : const Login(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _blue,
      body: Center(
        child: Text(
          'MediScan',
          style: GoogleFonts.poppins(
            fontSize: 44,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}