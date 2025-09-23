import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'dart:async';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    // Stay on splash for 2 seconds then navigate
    Timer(const Duration(seconds: 2), () {
      Navigator.pushReplacementNamed(context, '/login');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Your logo in the center
            Image.asset(
              'assets/LOGO.png',
              width: 140,   // logo width
              height: 140,  // logo height
            ),
            const SizedBox(height: 20), // space between logo and ring
            // Smaller neon ring animation below the logo
            Lottie.asset(
              'assets/neon_ring.json',
              width: 80,   // smaller width
              height: 80,  // smaller height
              repeat: true,
            ),
          ],
        ),
      ),
    );
  }
}
