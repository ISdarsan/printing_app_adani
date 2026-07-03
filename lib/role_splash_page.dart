import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme.dart';

class RoleSplashPage extends StatefulWidget {
  final String role;
  const RoleSplashPage({super.key, required this.role});

  @override
  State<RoleSplashPage> createState() => _RoleSplashPageState();
}

class _RoleSplashPageState extends State<RoleSplashPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _logoScale;
  late Animation<double> _textOpacity;

  String _welcomeMessage = 'Verifying your account...';
  String _subMessage = 'Please wait a moment';
  String _error = '';
  bool _showDots = true;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _logoScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );

    _textOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.4, 1.0, curve: Curves.easeIn),
    );

    _fetchUserRoleAndNavigate();
  }

  Future<void> _fetchUserRoleAndNavigate() async {
    String actualRole = 'unknown';

    try {
      final doc = await FirebaseFirestore.instance
          .collection('canteenStaff')
          .doc(widget.role)
          .get();

      if (doc.exists) {
        actualRole = doc.data()?['role'] ?? 'unknown';
        if (mounted) {
          setState(() {
            if (actualRole == 'admin') {
              _welcomeMessage = 'Welcome, Admin! 👑';
              _subMessage = 'Loading your dashboard...';
            } else {
              _welcomeMessage = 'Welcome, Cashier! 💳';
              _subMessage = 'Loading your dashboard...';
            }
            _showDots = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _welcomeMessage = 'Access Denied';
            _subMessage = 'User role not found.';
            _error = 'Contact your administrator.';
            _showDots = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _welcomeMessage = 'Connection Error';
          _subMessage = 'Check your internet connection.';
          _error = e.toString();
          _showDots = false;
        });
      }
    }

    _controller.forward();

    Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (actualRole == 'admin') {
        Navigator.pushReplacementNamed(context, '/admin_dashboard');
      } else if (actualRole == 'cashier') {
        Navigator.pushReplacementNamed(context, '/billing_dashboard');
      } else {
        FirebaseAuth.instance.signOut();
        Navigator.pushReplacementNamed(context, '/login');
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.darkBg),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── Glowing Logo ──────────────────────────────
              ScaleTransition(
                scale: _logoScale,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.gradBlue.withValues(alpha: 0.6),
                        blurRadius: 50,
                        spreadRadius: 10,
                      ),
                      BoxShadow(
                        color: AppColors.gradPurple.withValues(alpha: 0.3),
                        blurRadius: 80,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: Image.asset(
                      'assets/LOGO.png',
                      width: 140,
                      height: 140,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 36),

              // ── Welcome Message ───────────────────────────
              FadeTransition(
                opacity: _textOpacity,
                child: ShaderMask(
                  shaderCallback: (b) => AppGradients.brand
                      .createShader(Rect.fromLTWH(0, 0, b.width, b.height)),
                  child: Text(
                    _welcomeMessage,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              FadeTransition(
                opacity: _textOpacity,
                child: Text(
                  _subMessage,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),

              // ── Loading dots ──────────────────────────────
              if (_showDots)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.gradBlue),
                    strokeWidth: 2.5,
                  ),
                ),

              // ── Error ─────────────────────────────────────
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 20, left: 32, right: 32),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.accentRed.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.accentRed.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.accentRed, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error,
                            style: GoogleFonts.poppins(
                                fontSize: 12, color: AppColors.accentRed),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
