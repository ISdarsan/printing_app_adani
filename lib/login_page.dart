import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'role_splash_page.dart';
import 'theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String _errorMessage = '';

  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      if (mounted && cred.user != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => RoleSplashPage(role: cred.user!.uid),
          ),
        );
      }
    } on FirebaseAuthException {
      setState(() => _errorMessage = 'Invalid email or password. Try again.');
    } catch (_) {
      setState(() => _errorMessage = 'An error occurred. Please try again.');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.darkBg),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight:
                        constraints.maxHeight - 48, // minus vertical padding
                  ),
                  child: IntrinsicHeight(
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: SlideTransition(
                        position: _slideAnim,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 48),
                            // ── Logo ──────────────────────────────────
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.gradBlue
                                        .withValues(alpha: 0.5),
                                    blurRadius: 40,
                                    spreadRadius: 8,
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: Image.asset(
                                  'assets/LOGO.png',
                                  width: 100,
                                  height: 100,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // ── Title ─────────────────────────────────
                            Text(
                              'Welcome Back',
                              style: GoogleFonts.poppins(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Sign in to FoodPrint',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 32),

                            // ── Email Field ───────────────────────────
                            TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              style: GoogleFonts.poppins(
                                  color: AppColors.textPrimary),
                              decoration: darkInput(
                                label: 'Email Address',
                                prefixIcon: Icons.email_outlined,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // ── Password Field ────────────────────────
                            TextField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              style: GoogleFonts.poppins(
                                  color: AppColors.textPrimary),
                              decoration: darkInput(
                                label: 'Password',
                                prefixIcon: Icons.lock_outline,
                                suffixIconWidget: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: AppColors.textSecondary,
                                    size: 20,
                                  ),
                                  onPressed: () => setState(() =>
                                      _obscurePassword = !_obscurePassword),
                                ),
                              ),
                            ),

                            // ── Error Message ─────────────────────────
                            if (_errorMessage.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: AppColors.accentRed
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: AppColors.accentRed
                                            .withValues(alpha: 0.4)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.error_outline,
                                          color: AppColors.accentRed, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _errorMessage,
                                          style: GoogleFonts.poppins(
                                            color: AppColors.accentRed,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            const SizedBox(height: 28),

                            // ── Login Button ──────────────────────────
                            SizedBox(
                              width: double.infinity,
                              child: buildGradientButton(
                                label: 'Sign In',
                                icon: Icons.login_rounded,
                                isLoading: _isLoading,
                                onPressed: _isLoading ? null : _handleLogin,
                                height: 56,
                              ),
                            ),

                            const SizedBox(height: 16),

                            // ── Forgot Password ───────────────────────
                            TextButton(
                              onPressed: () {},
                              child: Text(
                                'Forgot Password?',
                                style: GoogleFonts.poppins(
                                  color: AppColors.accentBlue,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),

                            const Spacer(),

                            // ── Footer ────────────────────────────────
                            Padding(
                              padding:
                                  const EdgeInsets.only(top: 24, bottom: 8),
                              child: Text(
                                'Adani CSR Canteen Management',
                                style: GoogleFonts.poppins(
                                  color: Colors.white60,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
