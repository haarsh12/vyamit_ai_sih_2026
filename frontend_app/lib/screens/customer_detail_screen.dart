import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';
import '../models/customer.dart';
import '../services/customer_service.dart';
import '../services/api_client.dart';
import '../widgets/bill_type_badge.dart';

class CustomerDetailScreen extends StatefulWidget {
  final int customerId;
  final String customerName;

  const CustomerDetailScreen({
    super.key,
    required this.customerId,
    required this.customerName,
  });

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  late final CustomerService _customerService;
  Map<String, dynamic>? _customerData;
  List<CustomerBillItem> _bills = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _customerService = CustomerService(ApiClient());
    _loadCustomerData();
  }

  Future<void> _loadCustomerData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final details = await _customerService.getCustomerDetails(widget.customerId);
      final billsData = await _customerService.getCustomerBills(widget.customerId);

      if (mounted) {
        setState(() {
          _customerData = details;
          _bills = billsData['bills'] as List<CustomerBillItem>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load customer data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd MMM yyyy, hh:mm a').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.customerName),
        backgroundColor: AppColors.primaryGreen,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadCustomerData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Customer Info Header
                    _buildCustomerHeader(),
                    
                    const SizedBox(height: 16),
                    
                    // Statistics Cards
                    _buildStatisticsSection(),
                    
                    const SizedBox(height: 24),
                    
                    // Bill History
                    _buildBillHistorySection(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildCustomerHeader() {
    if (_customerData == null) return const SizedBox();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withOpacity(0.1),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: AppColors.primaryGreen,
            child: Text(
              widget.customerName.isNotEmpty 
                  ? widget.customerName[0].toUpperCase() 
                  : 'C',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.customerName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_customerData!['phone_number'] != null)
            Text(
              _customerData!['phone_number'],
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatisticsSection() {
    if (_customerData == null) return const SizedBox();

    final printedCount = _bills.where((b) => b.billType == 'printed').length;
    final virtualCount = _bills.where((b) => b.billType == 'virtual').length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Statistics',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Total Bills',
                  _customerData!['total_bills'].toString(),
                  Icons.receipt_long,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Total Spent',
                  '₹${(_customerData!['total_spent'] as double).toStringAsFixed(0)}',
                  Icons.currency_rupee,
                  Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Printed',
                  printedCount.toString(),
                  Icons.print,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Virtual',
                  virtualCount.toString(),
                  Icons.phone_android,
                  Colors.blue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillHistorySection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Purchase History',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          if (_bills.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No bills yet',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ),
            )
          else
            ..._bills.map((bill) => _buildBillCard(bill)).toList(),
        ],
      ),
    );
  }

  Widget _buildBillCard(CustomerBillItem bill) {
    final isVirtual = bill.billType == 'virtual';
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        leading: Icon(
          bill.billingSource == 'frequent'
              ? Icons.bolt_rounded
              : isVirtual
                  ? Icons.phone_android
                  : Icons.print,
          color: bill.billingSource == 'frequent'
              ? Colors.orange
              : isVirtual
                  ? Colors.blue
                  : Colors.green,
        ),
        title: Row(
          children: [
            Text(
              'Bill #${bill.id}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(width: 8),
            BillTypeBadge(billType: bill.billType),
            const SizedBox(width: 6),
            BillingSourceBadge(billingSource: bill.billingSource),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '₹${bill.totalAmount.toStringAsFixed(2)} • ${bill.totalItems} items',
              style: const TextStyle(fontSize: 14),
            ),
            Text(
              _formatDate(bill.billDate),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Items:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                ...bill.items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${item['name']} (${item['quantity']} ${item['unit']})',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        '₹${item['total']}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                )).toList(),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Payment: ${bill.paymentMethod}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    Text(
                      'Total: ₹${bill.totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
