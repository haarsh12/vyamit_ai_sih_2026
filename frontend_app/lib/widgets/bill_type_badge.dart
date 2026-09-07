import 'package:flutter/material.dart';

class BillTypeBadge extends StatelessWidget {
  final String billType;

  const BillTypeBadge({
    super.key,
    required this.billType,
  });

  @override
  Widget build(BuildContext context) {
    final isVirtual = billType == 'virtual';
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isVirtual 
            ? Colors.blue.shade100 
            : Colors.green.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isVirtual ? 'VIRTUAL' : 'PRINTED',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: isVirtual 
              ? Colors.blue.shade700 
              : Colors.green.shade700,
        ),
      ),
    );
  }
}

class BillTypeIcon extends StatelessWidget {
  final String billType;
  final double size;

  const BillTypeIcon({
    super.key,
    required this.billType,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    final isVirtual = billType == 'virtual';
    
    return Icon(
      isVirtual ? Icons.phone_android : Icons.print,
      color: isVirtual ? Colors.blue : Colors.green,
      size: size,
    );
  }
}

class BillingSourceBadge extends StatelessWidget {
  final String billingSource;

  const BillingSourceBadge({
    super.key,
    required this.billingSource,
  });

  @override
  Widget build(BuildContext context) {
    final isFrequent = billingSource == 'frequent';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isFrequent ? Colors.orange.shade100 : Colors.purple.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isFrequent ? Icons.bolt_rounded : Icons.mic_rounded,
            size: 12,
            color: isFrequent ? Colors.orange.shade800 : Colors.purple.shade700,
          ),
          const SizedBox(width: 3),
          Text(
            isFrequent ? 'FREQUENT' : 'VOICE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isFrequent ? Colors.orange.shade800 : Colors.purple.shade700,
            ),
          ),
        ],
      ),
    );
  }
}
