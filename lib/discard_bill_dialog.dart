import 'package:flutter/material.dart';

import 'money.dart';
import 'theme.dart';

/// Asked when the cashier leaves the billing screen (back button, back swipe)
/// with items still in the cart. Returns true only if they chose to discard.
Future<bool> confirmDiscardBill(
  BuildContext context, {
  required int itemCount,
  required double total,
}) async {
  final discard = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        const Icon(Icons.shopping_cart_checkout_rounded,
            color: AppColors.accentOrange),
        const SizedBox(width: 10),
        Expanded(
          child: Text('Leave without saving?',
              style: AppText.style(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
        ),
      ]),
      content: Text(
        'This bill has $itemCount item${itemCount == 1 ? '' : 's'} '
        '(₹${formatRupees(total)}). If you leave now it will be discarded.',
        style: AppText.style(
            color: AppColors.textSecondary, fontSize: 13, height: 1.45),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Keep editing',
              style: AppText.style(
                  color: AppColors.accentBlue, fontWeight: FontWeight.w700)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('Discard bill',
              style: AppText.style(
                  color: AppColors.accentRed, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return discard == true;
}
