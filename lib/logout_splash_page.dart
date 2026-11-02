import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'theme.dart';
import 'connection_probe.dart';

class LogoutSplashPage extends StatefulWidget {
  const LogoutSplashPage({super.key});

  @override
  State<LogoutSplashPage> createState() => _LogoutSplashPageState();
}

class _LogoutSplashPageState extends State<LogoutSplashPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fadeAnim;
  Timer? _navTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);

    // End the Firebase session only once the dashboard (and its live
    // Firestore listeners) is gone, otherwise those listeners briefly error.
    _navTimer = Timer(const Duration(seconds: 2), () async {
      ConnectionProbe.stop(); // also clears sync state of the signed-out user
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheBrandLogo(context);
  }

  @override
  void dispose() {
    _navTimer?.cancel();
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
                const BrandLogo(size: 120, radius: 24),
                const SizedBox(height: 32),
                Text(
                  'Logging Out...',
                  style: AppText.style(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'See you next time!',
                  style: AppText.style(
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
                        AlwaysStoppedAnimation<Color>(AppColors.gradBlue),
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
