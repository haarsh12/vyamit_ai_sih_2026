import 'package:flutter/material.dart';
import '../models/customer.dart';
import '../core/theme.dart';

class CustomerVerificationDialog extends StatefulWidget {
  final CustomerVerificationSuggestion suggestion;
  final Future<void> Function() onYes;
  final VoidCallback onNo;

  const CustomerVerificationDialog({
    super.key,
    required this.suggestion,
    required this.onYes,
    required this.onNo,
  });

  @override
  State<CustomerVerificationDialog> createState() =>
      _CustomerVerificationDialogState();
}

class _CustomerVerificationDialogState
    extends State<CustomerVerificationDialog> {
  bool _isSaving = false;

  Future<void> _confirm() async {
    setState(() => _isSaving = true);
    try {
      await widget.onYes();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final suggestion = widget.suggestion;
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                suggestion.isDuplicate ? Icons.people_alt : Icons.person_add,
                color: AppColors.primaryGreen,
                size: 30,
              ),
            ),

            const SizedBox(height: 16),

            // Title
            Text(
              suggestion.isDuplicate
                  ? 'Add Bill to Customer?'
                  : 'Save Customer?',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),

            const SizedBox(height: 12),

            // Message
            if (suggestion.isDuplicate &&
                suggestion.existingCustomerName != null)
              Text(
                'Existing verified customer: ${suggestion.existingCustomerName}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange,
                ),
                textAlign: TextAlign.center,
              ),

            if (suggestion.isDuplicate &&
                suggestion.existingCustomerName != null)
              const SizedBox(height: 8),

            Text(
              suggestion.message,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSaving ? null : widget.onNo,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey[400]!),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'No',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            suggestion.isDuplicate
                                ? 'Yes, Add Bill'
                                : 'Yes, Save',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
