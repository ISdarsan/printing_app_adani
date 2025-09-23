import 'package:flutter/material.dart';

class LogoutSplashPage extends StatefulWidget {
  const LogoutSplashPage({super.key});

  @override
  State<LogoutSplashPage> createState() => _LogoutSplashPageState();
}

class _LogoutSplashPageState extends State<LogoutSplashPage> {
  @override
  void initState() {
    super.initState();

    // simulate logout process for 2 seconds, then go back to login
    Future.delayed(const Duration(seconds: 2), () {
      // ✅ check widget is still mounted before using context
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    });
  }

  @override
  Widget build(BuildContext context) {
    // dark → light blue gradient for the text
    final Gradient blueGradient = const LinearGradient(
      colors: [
        Color(0xFF003C8F), // dark blue
        Color(0xFF2196F3), // light blue
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo in center
            Image.asset(
              'assets/LOGO.png',
              width: 150,
              height: 150,
            ),
            const SizedBox(height: 25),

            // Gradient “Logging Out…” text
            ShaderMask(
              shaderCallback: (bounds) =>
                  blueGradient.createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
              child: const Text(
                'Logging Out...',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white, // required for ShaderMask
                  letterSpacing: 1.5,
                ),
              ),
            ),

            const SizedBox(height: 25),

            // Spinner
            const CircularProgressIndicator(
              strokeWidth: 3,
              color: Color(0xFF2196F3), // matches light blue
            ),
          ],
        ),
      ),
    );
  }
}
