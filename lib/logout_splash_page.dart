import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme.dart';

class LogoutSplashPage extends StatefulWidget {
  const LogoutSplashPage({super.key});

  @override
  State<LogoutSplashPage> createState() => _LogoutSplashPageState();
}

class _LogoutSplashPageState extends State<LogoutSplashPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.darkBg),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo with glow
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.gradPink.withValues(alpha: 0.4),
                        blurRadius: 40,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child:
                        Image.asset('assets/LOGO.png', width: 120, height: 120),
                  ),
                ),
                const SizedBox(height: 32),

                // Gradient "Logging Out" text
                Text(
                  'Logging Out...',
                  style: GoogleFonts.poppins(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'See you next time!',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 32),

                const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.gradPink),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
