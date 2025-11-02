import 'dart:async';
import 'package:flutter/material.dart';
// 1. IMPORT FIREBASE LIBS
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RoleSplashPage extends StatefulWidget {
  // The 'role' parameter is now the USER'S UID
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

  // 2. Add state variables for the text
  String _welcomeMessage = 'Loading...';
  String _error = '';

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    // Your UI animations (unchanged)
    _logoScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );

    _textOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.4, 1.0, curve: Curves.easeIn),
    );

    // 3. --- NEW LOGIC ---
    // Start fetching the user role right away
    _fetchUserRoleAndNavigate();
  }

  // 4. --- NEW FUNCTION TO GET ROLE FROM DATABASE ---
  Future<void> _fetchUserRoleAndNavigate() async {
    String actualRole = 'unknown';

    try {
      // Look in 'canteenStaff' for a document matching the user's UID
      final doc = await FirebaseFirestore.instance
          .collection('canteenStaff')
          .doc(widget.role) // widget.role now holds the UID
          .get();

      if (doc.exists) {
        // We found the user! Get their role.
        actualRole = doc.data()?['role'] ?? 'unknown';

        // Set the welcome message
        setState(() {
          _welcomeMessage = (actualRole == 'admin') ? 'Welcome Admin' : 'Welcome Cashier';
        });

      } else {
        // This user logged in, but has no role in the database!
        setState(() {
          _welcomeMessage = 'Error!';
          _error = 'User role not found in database.';
        });
      }
    } catch (e) {
      // Handle errors like no internet
      setState(() {
        _welcomeMessage = 'Error!';
        _error = 'Error checking role: $e';
      });
    }

    // Start the UI animation
    _controller.forward();

    // After animation ends, go to dashboard
    Timer(const Duration(seconds: 3), () {
      if (!mounted) return;

      if (actualRole == 'admin') {
        Navigator.pushReplacementNamed(context, '/admin_dashboard');
      } else if (actualRole == 'cashier') {
        Navigator.pushReplacementNamed(context, '/billing_dashboard');
      } else {
        // If role is "unknown", sign them out and send back to login
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
    // Your gradient (unchanged)
    final gradientColors = [Colors.blue.shade700, Colors.blue.shade400];

    // 5. --- YOUR UI IS 100% UNCHANGED ---
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
                  // 6. Use the new state variable for the text
                  _welcomeMessage,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white, // must be white for ShaderMask
                  ),
                ),
              ),
            ),
            // 7. Add an error text if something goes wrong
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Text(
                  _error,
                  style: const TextStyle(fontSize: 16, color: Colors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }
}