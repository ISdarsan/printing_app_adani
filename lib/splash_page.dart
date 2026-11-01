import 'dart:async';
import 'package:flutter/material.dart';
import 'theme.dart';

/// Launch splash. Intentionally light: one short entrance animation and a
/// progress hairline. No blurred shadows or per-frame painters, so it runs
/// at full frame rate on low-end devices.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _logoScale;
  late final Animation<double> _textOpacity;
  late final Animation<Offset> _textSlide;
  Timer? _navTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..forward();

    _logoScale = Tween<double>(begin: 0.96, end: 1.0).animate(
      CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(0.0, 0.25, curve: Curves.easeOutCubic)),
    );
    _textOpacity = CurvedAnimation(
        parent: _ctrl, curve: const Interval(0.15, 0.4, curve: Curves.easeOut));
    _textSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _ctrl,
            curve: const Interval(0.15, 0.4, curve: Curves.easeOutCubic)));

    _navTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
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
        child: SafeArea(
          child: Column(
            children: [
              // Logo sits at the exact centre of the screen so it lines up
              // with the native launch screen (no jump on hand-over).
              Expanded(
                child: Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      ScaleTransition(
                        scale: _logoScale,
                        child: BrandLogo(size: 112, radius: 30),
                      ),
                      Positioned(
                        top: 112 + 28,
                        left: -120,
                        right: -120,
                        child: FadeTransition(
                          opacity: _textOpacity,
                          child: SlideTransition(
                            position: _textSlide,
                            child: Column(
                              children: [
                                Text(
                                  'FoodPrint',
                                  style: AppText.style(
                                    fontSize: 34,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textPrimary,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'CANTEEN BILLING SYSTEM',
                                  style: AppText.style(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                    letterSpacing: 2.4,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              FadeTransition(
                opacity: _textOpacity,
                child: SizedBox(
                  width: 160,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: AnimatedBuilder(
                      animation: _ctrl,
                      builder: (_, __) => LinearProgressIndicator(
                        value: _ctrl.value,
                        minHeight: 3,
                        backgroundColor: AppColors.bgInput,
                        valueColor:
                            const AlwaysStoppedAnimation(AppColors.gradBlue),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Adani CSR',
                style: AppText.style(
                  fontSize: 11,
                  color: AppColors.textHint,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}
