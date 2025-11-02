import 'dart:async';
import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _logoScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );

    _textOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.4, 1.0, curve: Curves.easeIn),
    );
    _controller.forward();

    // Navigate after 3 seconds
    Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (widget.role == 'admin') {
        // --- THIS IS THE FIX ---
        // Was '/adminDashboard', now matches main.dart
        Navigator.pushReplacementNamed(context, '/admin_dashboard');
      } else {
        // --- THIS IS THE FIX ---
        // Was '/billingDashboard', now matches main.dart
        Navigator.pushReplacementNamed(context, '/billing_dashboard');
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
    // Always blue gradient for text, regardless of role
    final gradientColors = [Colors.blue.shade700, Colors.blue.shade400];

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _logoScale,
              child: Image.asset(
                'assets/LOGO.png',
                width: 150,
                height: 150,
              ),
            ),
            const SizedBox(height: 20),
            FadeTransition(
              opacity: _textOpacity,
              child: ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: gradientColors,
                ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
                child: Text(
                  widget.role == 'admin' ? 'Welcome Admin' : 'Welcome Cashier',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white, // Must be white for ShaderMask
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}