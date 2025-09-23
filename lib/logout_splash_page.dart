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
    // simulate logout process for 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
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
            // Logo in center
            Image.asset(
              'assets/LOGO.png',
              width: 150,
              height: 150,
            ),
            const SizedBox(height: 25),

            // Clean “Logging Out…” text
            const Text(
              'Logging Out...',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
                letterSpacing: 1.2,
              ),
            ),

            const SizedBox(height: 25),

            // Spinner
            const CircularProgressIndicator(
              strokeWidth: 3,
              color: Color(0xFF0066B3), // your brand blue
            ),
          ],
        ),
      ),
    );
  }
}
