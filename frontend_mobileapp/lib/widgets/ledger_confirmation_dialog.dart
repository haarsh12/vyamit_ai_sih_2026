import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Shared final guard for voice and touch-based ledger changes.
///
/// The backend receives only a draft before this dialog is accepted.
class LedgerConfirmationDialog extends StatefulWidget {
  final Map<String, dynamic> draft;

  /// Returns null after a successful write, otherwise a user-facing error.
  ///
  /// The dialog owns navigation so a caller never pops this route while this
  /// widget is still awaiting the confirmation request.
  final Future<String?> Function() onConfirm;

  const LedgerConfirmationDialog({
    super.key,
    required this.draft,
    required this.onConfirm,
  });

  @override
  State<LedgerConfirmationDialog> createState() =>
      _LedgerConfirmationDialogState();
}

class _LedgerConfirmationDialogState extends State<LedgerConfirmationDialog> {
  bool _isConfirming = false;
  String? _confirmationError;

  double _amount(String key) => (widget.draft[key] as num?)?.toDouble() ?? 0;

  Future<void> _confirm() async {
    setState(() {
      _isConfirming = true;
      _confirmationError = null;
    });

    String? error;
    try {
      error = await widget.onConfirm();
    } catch (exception) {
      error = 'Ledger was not updated: $exception';
    }
    if (!mounted) return;

    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _isConfirming = false;
      _confirmationError = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isUdhaar = widget.draft['entry_type']?.toString() == 'udhaar';
    final amount = _amount('amount');
    final current = _amount('current_balance');
    final proposed = _amount('proposed_balance');
    final accent = isUdhaar ? const Color(0xFFB54708) : AppColors.primaryGreen;
    final customer =
        widget.draft['customer_name']?.toString() ?? 'this customer';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.center,
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                    color: accent.withOpacity(.12), shape: BoxShape.circle),
                child: Icon(
                    isUdhaar ? Icons.add_card_rounded : Icons.payments_rounded,
                    color: accent,
                    size: 28),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isUdhaar ? 'Add udhaar?' : 'Record payment?',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            Text(
              '${isUdhaar ? 'Add' : 'Reduce'} ₹${amount.toStringAsFixed(2)} ${isUdhaar ? 'to' : 'from'} $customer\'s ledger.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textGrey, height: 1.35),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: const Color(0xFFF7F9F8),
                  borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  Expanded(
                      child: _balance('Current due', current, Colors.black87)),
                  Container(width: 1, height: 36, color: Colors.grey.shade300),
                  Expanded(
                      child: _balance('After confirmation', proposed, accent)),
                ],
              ),
            ),
            if ((widget.draft['note']?.toString().trim().isNotEmpty ??
                false)) ...[
              const SizedBox(height: 12),
              Text('Note: ${widget.draft['note']}',
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.textGrey)),
            ],
            if (_confirmationError != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _confirmationError!,
                  style:
                      const TextStyle(color: Color(0xFFB42318), fontSize: 12),
                ),
              ),
            ],
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isConfirming
                        ? null
                        : () => Navigator.of(context).pop(false),
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
                    onPressed: _isConfirming ? null : _confirm,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: _isConfirming
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Yes, confirm',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _balance(String label, double amount, Color color) {
    return Column(
      children: [
        Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 10,
                color: AppColors.textGrey,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('₹${amount.toStringAsFixed(2)}',
            style: TextStyle(
                color: color, fontWeight: FontWeight.w800, fontSize: 15)),
      ],
    );
  }
}
