import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'theme.dart';
import 'connection_probe.dart';
import 'canteen_provider.dart';
import 'role_routing.dart';

/// Result of reading `canteenStaff/{uid}`.
typedef StaffRecord = ({bool exists, Map<String, dynamic>? data});
typedef StaffLoader = Future<StaffRecord> Function(String uid);

class RoleSplashPage extends StatefulWidget {
  final String role; // the signed-in user's uid (historical name)

  /// Injectable for tests. Defaults read the staff document from the SERVER
  /// (never the local cache) so a deactivation takes effect immediately.
  final StaffLoader? loadStaff;
  final Future<void> Function()? signOut;
  const RoleSplashPage(
      {super.key, required this.role, this.loadStaff, this.signOut});

  @override
  State<RoleSplashPage> createState() => _RoleSplashPageState();
}

class _RoleSplashPageState extends State<RoleSplashPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _logoScale;
  late Animation<double> _textOpacity;

  String _welcomeMessage = 'Verifying your account...';
  String _subMessage = 'Please wait a moment';
  String _error = '';
  bool _showDots = true;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _logoScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );

    _textOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.4, 1.0, curve: Curves.easeIn),
    );

    _fetchUserRoleAndNavigate();
  }

  static Future<StaffRecord> _defaultLoad(String uid) async {
    final doc = await FirebaseFirestore.instance
        .collection('canteenStaff')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    return (exists: doc.exists, data: doc.data());
  }

  bool _navigated = false;

  /// Authorise, then go. There is no fixed wait: an authorised user is sent to
  /// the dashboard the moment the staff document has been verified. A denied
  /// user sees the reason for a moment and is then signed out.
  Future<void> _fetchUserRoleAndNavigate() async {
    RoleDecision decision;
    try {
      final rec = await (widget.loadStaff ?? _defaultLoad)(widget.role);
      decision = decideRole(docExists: rec.exists, data: rec.data);
      if (decision.allowed) CanteenProvider.applyStaffData(rec.data);
    } catch (e) {
      decision = decideRole(docExists: false, error: e);
    }
    if (!mounted) return;

    setState(() {
      _welcomeMessage = decision.title;
      _subMessage = decision.subtitle;
      _error = decision.allowed ? '' : decision.detail;
      _showDots = false;
    });

    if (decision.allowed) {
      if (_navigated) return;
      _navigated = true;
      // Production path only (tests inject their own loader, no Firebase).
      if (widget.loadStaff == null) ConnectionProbe.start(widget.role);
      Navigator.pushReplacementNamed(context, decision.route!);
      return;
    }

    _controller.forward();
    await Future<void>.delayed(decision.denialHold);
    if (!mounted || _navigated) return;
    _navigated = true;
    try {
      await (widget.signOut ?? FirebaseAuth.instance.signOut)();
    } catch (_) {
      // Navigating to login is still the right outcome.
    }
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheBrandLogo(context);
  }

  @override
  void dispose() {
    _controller.dispose();
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
              // ── Glowing Logo ──────────────────────────────
              ScaleTransition(
                scale: _logoScale,
                child: BrandLogo(size: 120, radius: 28),
              ),
              const SizedBox(height: 36),

              // ── Welcome Message ───────────────────────────
              FadeTransition(
                opacity: _textOpacity,
                child: Text(
                  _welcomeMessage,
                  textAlign: TextAlign.center,
                  style: AppText.style(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              FadeTransition(
                opacity: _textOpacity,
                child: Text(
                  _subMessage,
                  style: AppText.style(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),

              // ── Loading dots ──────────────────────────────
              if (_showDots)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.gradBlue),
                    strokeWidth: 2.5,
                  ),
                ),

              // ── Error ─────────────────────────────────────
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 20, left: 32, right: 32),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.accentRed.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.accentRed.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.accentRed, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error,
                            style: AppText.style(
                                fontSize: 12, color: AppColors.accentRed),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
