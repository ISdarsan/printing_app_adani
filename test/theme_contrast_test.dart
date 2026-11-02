import 'dart:math' as math;

import 'package:canteen_adani/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// WCAG 2.x contrast ratio between two opaque colours.
double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final hi = math.max(_lum(a), _lum(b)), lo = math.min(_lum(a), _lum(b));
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const surfaces = {
    'bgDark': AppColors.bgDark,
    'bgCard': AppColors.bgCard,
    'bgInput': AppColors.bgInput,
  };
  const text = {
    'textPrimary': AppColors.textPrimary,
    'textSecondary': AppColors.textSecondary,
    'textHint': AppColors.textHint,
    'accentGreen': AppColors.accentGreen,
    'accentOrange': AppColors.accentOrange,
    'accentRed': AppColors.accentRed,
    'accentBlue': AppColors.accentBlue,
  };

  for (final t in text.entries) {
    for (final s in surfaces.entries) {
      test('${t.key} on ${s.key} meets WCAG AA (4.5:1)', () {
        expect(contrast(t.value, s.value), greaterThanOrEqualTo(4.5));
      });
    }
  }

  test('white text on the brand button colours meets WCAG AA', () {
    expect(contrast(Colors.white, AppColors.gradBlue), greaterThanOrEqualTo(4.5));
    expect(contrast(Colors.white, AppColors.gradPurple), greaterThanOrEqualTo(4.5));
  });

  test('hint text stays visually below secondary text', () {
    expect(contrast(AppColors.textHint, AppColors.bgCard),
        lessThan(contrast(AppColors.textSecondary, AppColors.bgCard)));
  });
}
