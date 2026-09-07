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
