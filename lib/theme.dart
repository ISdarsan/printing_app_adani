import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────
//  APP THEME  –  FoodPrint Dark-Mode Design System
// ─────────────────────────────────────────────────────────────

class AppColors {
  // Backgrounds
  static const bgDark = Color(0xFF0A0E1A);
  static const bgCard = Color(0xFF111827);
  static const bgInput = Color(0xFF1A2235);
  static const bgDivider = Color(0xFF1E2D45);

  // Brand gradient stops
  static const gradBlue = Color(0xFF0066B3);
  static const gradPurple = Color(0xFF6C3FB5);
  static const gradPink = Color(0xFFE91E63);

  // Accent colours
  static const accentGreen = Color(0xFF00E5A0);
  static const accentOrange = Color(0xFFFF8C42);
  static const accentBlue = Color(0xFF4FC3F7);
  static const accentRed = Color(0xFFFF4C6A);
  static const accentPurple = Color(0xFF9C27B0);

  // Text
  static const textPrimary = Color(0xFFF0F4FF);
  static const textSecondary = Color(0xFF8899AA);
  static const textHint = Color(0xFF4A5568);

  // Glass
  static const glassBorder = Color(0x1AFFFFFF); // 10% white
  static const glassFill = Color(0x0DFFFFFF); // 5%  white
}

class AppGradients {
  static const brand = LinearGradient(
    colors: [AppColors.gradBlue, AppColors.gradPurple, AppColors.gradPink],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const brandVertical = LinearGradient(
    colors: [AppColors.gradBlue, AppColors.gradPurple, AppColors.gradPink],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const greenAccent = LinearGradient(
    colors: [Color(0xFF00C980), Color(0xFF00E5A0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const orangeAccent = LinearGradient(
    colors: [Color(0xFFFF6B35), Color(0xFFFF8C42)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const blueAccent = LinearGradient(
    colors: [Color(0xFF2196F3), Color(0xFF4FC3F7)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const redAccent = LinearGradient(
    colors: [Color(0xFFE91E63), Color(0xFFFF4C6A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const darkBg = LinearGradient(
    colors: [Color(0xFF0A0E1A), Color(0xFF111827)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

// ─────────────────────────────────────────────────────────────
//  DECORATION HELPERS
// ─────────────────────────────────────────────────────────────

BoxDecoration glassCard({
  double radius = 20,
  Color? borderColor,
  List<BoxShadow>? shadows,
}) {
  return BoxDecoration(
    color: AppColors.glassFill,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: borderColor ?? AppColors.glassBorder, width: 1),
    boxShadow: shadows ??
        [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
  );
}

BoxDecoration gradientCard({
  required Gradient gradient,
  double radius = 20,
  List<BoxShadow>? shadows,
}) {
  return BoxDecoration(
    gradient: gradient,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: shadows ??
        [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
  );
}

BoxDecoration darkInputDecoration({double radius = 14}) {
  return BoxDecoration(
    color: AppColors.bgInput,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: AppColors.glassBorder),
  );
}

// ─────────────────────────────────────────────────────────────
//  SHARED WIDGETS
// ─────────────────────────────────────────────────────────────

/// Gradient AppBar used on every page
PreferredSizeWidget buildGradientAppBar({
  required String title,
  List<Widget>? actions,
  Widget? leading,
  bool centerTitle = true,
}) {
  return PreferredSize(
    preferredSize: const Size.fromHeight(56),
    child: AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: leading,
      iconTheme: const IconThemeData(color: Colors.white),
      flexibleSpace: Container(
        decoration: const BoxDecoration(gradient: AppGradients.brand),
      ),
      title: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      centerTitle: centerTitle,
      actions: actions,
    ),
  );
}

/// Full-width gradient button
Widget buildGradientButton({
  required String label,
  required VoidCallback? onPressed,
  bool isLoading = false,
  double height = 54,
  Gradient gradient = AppGradients.brand,
  IconData? icon,
}) {
  return GestureDetector(
    onTap: onPressed,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: height,
      decoration: BoxDecoration(
        gradient: onPressed == null
            ? const LinearGradient(
                colors: [Color(0xFF2A2A2A), Color(0xFF3A3A3A)])
            : gradient,
        borderRadius: BorderRadius.circular(30),
        boxShadow: onPressed == null
            ? []
            : [
                BoxShadow(
                  color: AppColors.gradBlue.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Center(
        child: isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
      ),
    ),
  );
}

/// Dark styled InputDecoration
InputDecoration darkInput({
  required String label,
  IconData? prefixIcon,
  Widget? suffixIconWidget,
  String? hint,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    labelStyle:
        GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: 14),
    hintStyle: GoogleFonts.poppins(color: AppColors.textHint, fontSize: 14),
    prefixIcon: prefixIcon != null
        ? Icon(prefixIcon, color: AppColors.textSecondary, size: 20)
        : null,
    suffixIcon: suffixIconWidget,
    filled: true,
    fillColor: AppColors.bgInput,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.glassBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.glassBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.gradBlue, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.accentRed),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.accentRed, width: 1.5),
    ),
  );
}

/// Small pill/chip badge
Widget buildBadge(String text, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    ),
  );
}

/// Stat card with gradient icon background
Widget buildStatCard({
  required IconData icon,
  required String label,
  required String value,
  required Gradient gradient,
  VoidCallback? onTap,
}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: glassCard(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 14),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          if (onTap != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Text(
                    'View details',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: AppColors.accentBlue,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.arrow_forward_ios,
                      size: 10, color: AppColors.accentBlue),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

/// Section title
Widget sectionTitle(String title) {
  return Text(
    title,
    style: GoogleFonts.poppins(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
    ),
  );
}

// ─────────────────────────────────────────────────────────────
//  GLOBAL ThemeData
// ─────────────────────────────────────────────────────────────

ThemeData buildAppTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bgDark,
    primaryColor: AppColors.gradBlue,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.gradBlue,
      secondary: AppColors.gradPurple,
      surface: AppColors.bgCard,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: AppColors.textPrimary,
    ),
    textTheme:
        GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme).copyWith(
      bodyLarge: GoogleFonts.poppins(color: AppColors.textPrimary),
      bodyMedium: GoogleFonts.poppins(color: AppColors.textSecondary),
      titleLarge: GoogleFonts.poppins(
          color: AppColors.textPrimary, fontWeight: FontWeight.w700),
      headlineMedium: GoogleFonts.poppins(
          color: AppColors.textPrimary, fontWeight: FontWeight.w700),
    ),
    cardColor: AppColors.bgCard,
    dividerColor: AppColors.bgDivider,
    iconTheme: const IconThemeData(color: AppColors.textSecondary),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.bgDark,
      foregroundColor: AppColors.textPrimary,
      titleTextStyle: GoogleFonts.poppins(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
      elevation: 0,
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: AppColors.bgCard,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.bgCard,
      contentTextStyle: GoogleFonts.poppins(color: AppColors.textPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.bgInput,
      labelStyle: GoogleFonts.poppins(color: AppColors.textSecondary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.glassBorder),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.gradBlue,
    ),
  );
}
