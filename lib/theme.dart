import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────
//  APP THEME  –  FoodPrint Premium Dark Design System
//
//  Design notes
//  • One calm indigo brand hue; semantic accents only carry meaning
//    (green = money in, orange = pending, red = problem).
//  • Solid surfaces + hairline borders instead of translucent glass and
//    large blurred shadows: identical look on every GPU and far cheaper
//    to paint on low-end phones.
//  • Inter is bundled in assets/fonts, so there are no runtime font
//    downloads and text never flashes or falls back when offline.
// ─────────────────────────────────────────────────────────────

class AppColors {
  // Backgrounds
  static const bgDark = Color(0xFF080B14);
  static const bgCard = Color(0xFF0F1420);
  static const bgInput = Color(0xFF151B29);
  static const bgDivider = Color(0xFF1E2636);

  // Brand (single hue family: indigo → violet)
  static const gradBlue = Color(0xFF3D5AFE);
  static const gradPurple = Color(0xFF5B4BE0);
  static const gradPink = Color(0xFF7C4DDB);

  // Accent colours
  static const accentGreen = Color(0xFF2DD4A0);
  static const accentOrange = Color(0xFFFFA94D);
  static const accentBlue = Color(0xFF6CB6FF);
  static const accentRed = Color(0xFFFF5C7A);
  static const accentPurple = Color(0xFF9B7BFF);

  // Text
  static const textPrimary = Color(0xFFF2F5FC);
  static const textSecondary = Color(0xFF8E9BB0);
  static const textHint = Color(0xFF566176);

  // Surfaces / hairlines
  static const glassBorder = Color(0x14FFFFFF); // 8% white
  static const glassFill = Color(0xFF0F1420);
}

class AppGradients {
  static const brand = LinearGradient(
    colors: [AppColors.gradBlue, AppColors.gradPurple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const brandVertical = LinearGradient(
    colors: [AppColors.gradBlue, AppColors.gradPurple],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const greenAccent = LinearGradient(
    colors: [Color(0xFF14B889), Color(0xFF2DD4A0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const orangeAccent = LinearGradient(
    colors: [Color(0xFFF08A24), Color(0xFFFFA94D)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const blueAccent = LinearGradient(
    colors: [Color(0xFF3B82F6), Color(0xFF6CB6FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const redAccent = LinearGradient(
    colors: [Color(0xFFE5365A), Color(0xFFFF5C7A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const darkBg = LinearGradient(
    colors: [Color(0xFF080B14), Color(0xFF0D1220)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

// ─────────────────────────────────────────────────────────────
//  TYPOGRAPHY  (bundled Inter, tabular figures for aligned amounts)
// ─────────────────────────────────────────────────────────────

class AppText {
  static const String family = 'Inter';

  static TextStyle style({
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
    FontStyle? fontStyle,
  }) {
    return TextStyle(
      fontFamily: family,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
      fontStyle: fontStyle,
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  BRAND LOGO  (small pre-sized asset, precached, fades in – no pop-in)
// ─────────────────────────────────────────────────────────────

const AssetImage brandLogoImage = AssetImage('assets/appicon_small.png');

/// Loads the logo into the image cache so splash/login/logout never show an
/// empty frame while it decodes. Safe to call repeatedly.
Future<void> precacheBrandLogo(BuildContext context) =>
    precacheImage(brandLogoImage, context).catchError((_) {});

class BrandLogo extends StatelessWidget {
  final double size;
  final double radius;
  const BrandLogo({super.key, this.size = 112, this.radius = 30});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image(
          image: brandLogoImage,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          frameBuilder: (context, child, frame, sync) {
            if (sync) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 180),
              child: child,
            );
          },
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.restaurant_rounded, color: AppColors.accentBlue),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  DECORATION HELPERS
// ─────────────────────────────────────────────────────────────

/// Standard surface card: solid fill + hairline border (no blurred shadow
/// unless the caller asks for one).
BoxDecoration glassCard({
  double radius = 20,
  Color? borderColor,
  List<BoxShadow>? shadows,
}) {
  return BoxDecoration(
    color: AppColors.bgCard,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: borderColor ?? AppColors.glassBorder, width: 1),
    boxShadow: shadows,
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
            color: AppColors.gradBlue.withValues(alpha: 0.22),
            blurRadius: 14,
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

/// Flat AppBar used on every page: solid surface, hairline divider.
PreferredSizeWidget buildGradientAppBar({
  required String title,
  List<Widget>? actions,
  Widget? leading,
  bool centerTitle = true,
}) {
  return AppBar(
    backgroundColor: AppColors.bgCard,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    leading: leading,
    iconTheme: const IconThemeData(color: AppColors.textPrimary),
    actionsIconTheme: const IconThemeData(color: AppColors.textPrimary),
    shape: const Border(
      bottom: BorderSide(color: AppColors.glassBorder, width: 1),
    ),
    title: Text(
      title,
      style: AppText.style(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        letterSpacing: -0.2,
      ),
    ),
    centerTitle: centerTitle,
    actions: actions,
  );
}

/// Full-width gradient button with ripple feedback.
Widget buildGradientButton({
  required String label,
  required VoidCallback? onPressed,
  bool isLoading = false,
  double height = 54,
  Gradient gradient = AppGradients.brand,
  IconData? icon,
}) {
  final enabled = onPressed != null;
  return Semantics(
    button: true,
    enabled: enabled,
    label: label,
    child: Material(
      color: Colors.transparent,
      child: Ink(
        height: height,
        decoration: BoxDecoration(
          gradient: enabled
              ? gradient
              : const LinearGradient(
                  colors: [Color(0xFF1B2230), Color(0xFF1B2230)]),
          borderRadius: BorderRadius.circular(14),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon,
                            color: enabled ? Colors.white : AppColors.textHint,
                            size: 20),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        label,
                        style: AppText.style(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                          color: enabled ? Colors.white : AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
          ),
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
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: w),
      );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    labelStyle: AppText.style(color: AppColors.textSecondary, fontSize: 14),
    floatingLabelStyle:
        AppText.style(color: AppColors.accentBlue, fontSize: 13),
    hintStyle: AppText.style(color: AppColors.textHint, fontSize: 14),
    prefixIcon: prefixIcon != null
        ? Icon(prefixIcon, color: AppColors.textSecondary, size: 20)
        : null,
    suffixIcon: suffixIconWidget,
    filled: true,
    fillColor: AppColors.bgInput,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    border: border(AppColors.glassBorder),
    enabledBorder: border(AppColors.glassBorder),
    focusedBorder: border(AppColors.gradBlue, 1.5),
    errorBorder: border(AppColors.accentRed),
    focusedErrorBorder: border(AppColors.accentRed, 1.5),
  );
}

/// Small pill/chip badge
Widget buildBadge(String text, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.32)),
    ),
    child: Text(
      text,
      style: AppText.style(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    ),
  );
}

/// Stat card with a gradient icon tile
Widget buildStatCard({
  required IconData icon,
  required String label,
  required String value,
  required Gradient gradient,
  VoidCallback? onTap,
}) {
  return Material(
    color: Colors.transparent,
    child: Ink(
      decoration: glassCard(radius: 18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(height: 14),
              Text(
                label,
                style: AppText.style(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: AppText.style(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
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
                        style: AppText.style(
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
      ),
    ),
  );
}

/// Section title
Widget sectionTitle(String title) {
  return Text(
    title,
    style: AppText.style(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
      color: AppColors.textPrimary,
    ),
  );
}

// ─────────────────────────────────────────────────────────────
//  GLOBAL ThemeData
// ─────────────────────────────────────────────────────────────

ThemeData buildAppTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final textTheme = base.textTheme.apply(
    fontFamily: AppText.family,
    bodyColor: AppColors.textPrimary,
    displayColor: AppColors.textPrimary,
  );
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: w),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: AppText.family,
    scaffoldBackgroundColor: AppColors.bgDark,
    primaryColor: AppColors.gradBlue,
    // InkRipple is far cheaper than the default M3 InkSparkle shader, which
    // causes first-tap jank on low-end GPUs.
    splashFactory: InkRipple.splashFactory,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.gradBlue,
      secondary: AppColors.gradPurple,
      surface: AppColors.bgCard,
      error: AppColors.accentRed,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: AppColors.textPrimary,
    ),
    textTheme: textTheme,
    cardColor: AppColors.bgCard,
    dividerColor: AppColors.bgDivider,
    dividerTheme: const DividerThemeData(color: AppColors.bgDivider),
    iconTheme: const IconThemeData(color: AppColors.textSecondary),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.bgCard,
      foregroundColor: AppColors.textPrimary,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: AppText.style(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: AppColors.bgCard,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.bgCard,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.glassBorder),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.bgCard,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF1A2132),
      contentTextStyle: AppText.style(color: AppColors.textPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: AppText.style(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: AppText.style(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.bgInput,
      labelStyle: AppText.style(color: AppColors.textSecondary),
      hintStyle: AppText.style(color: AppColors.textHint),
      border: border(AppColors.glassBorder),
      enabledBorder: border(AppColors.glassBorder),
      focusedBorder: border(AppColors.gradBlue, 1.5),
      errorBorder: border(AppColors.accentRed),
      focusedErrorBorder: border(AppColors.accentRed, 1.5),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.gradBlue,
    ),
  );
}
