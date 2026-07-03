import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'theme.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.85, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    Timer(const Duration(seconds: 3), () {
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
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
              // Glowing logo
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, child) {
                  return Transform.scale(
                    scale: _pulseAnim.value,
                    child: child,
                  );
                },
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.gradBlue.withValues(alpha: 0.5),
                        blurRadius: 40,
                        spreadRadius: 10,
                      ),
                      BoxShadow(
                        color: AppColors.gradPurple.withValues(alpha: 0.3),
                        blurRadius: 60,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: Image.asset(
                      'assets/LOGO.png',
                      width: 130,
                      height: 130,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // App name with gradient
              ShaderMask(
                shaderCallback: (bounds) => AppGradients.brand.createShader(
                  Rect.fromLTWH(0, 0, bounds.width, bounds.height),
                ),
                child: const Text(
                  'FoodPrint',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Canteen Billing System',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 40),

              // Lottie neon ring
              Lottie.asset(
                'assets/neon_ring.json',
                width: 70,
                height: 70,
                repeat: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
