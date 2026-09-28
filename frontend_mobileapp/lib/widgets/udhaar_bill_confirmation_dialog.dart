import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Explicit approval before a completed bill can increase a customer ledger.
class UdhaarBillConfirmationDialog extends StatelessWidget {
  final String customerName;
  final double amount;

  const UdhaarBillConfirmationDialog({
    super.key,
    required this.customerName,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                  color: Color(0xFFFFF1E8), shape: BoxShape.circle),
              child: const Icon(Icons.account_balance_wallet_rounded,
                  color: Color(0xFFB54708), size: 29),
            ),
            const SizedBox(height: 16),
            const Text('Set this bill as udhaar?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              '₹${amount.toStringAsFixed(2)} will be added to $customerName\'s ledger after this bill is saved.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textGrey, height: 1.35),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              decoration: BoxDecoration(
                  color: const Color(0xFFFFF8F2),
                  borderRadius: BorderRadius.circular(14)),
              child: const Row(children: [
                Icon(Icons.info_outline_rounded,
                    color: Color(0xFFB54708), size: 18),
                SizedBox(width: 8),
                Expanded(
                    child: Text('The bill and ledger entry are saved together.',
                        style: TextStyle(
                            color: Color(0xFF8A3B0A),
                            fontSize: 12,
                            fontWeight: FontWeight.w600))),
              ]),
            ),
            const SizedBox(height: 22),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  child: const Text('No, cancel',
                      style: TextStyle(
                          color: AppColors.textBlack,
                          fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFB54708),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  child: const Text('Yes, add udhaar',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
