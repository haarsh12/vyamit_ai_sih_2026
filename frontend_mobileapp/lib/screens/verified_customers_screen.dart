import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/customer.dart';
import '../services/customer_service.dart';
import '../services/api_client.dart';
import 'customer_detail_screen.dart';

class VerifiedCustomersScreen extends StatefulWidget {
  const VerifiedCustomersScreen({super.key});

  @override
  State<VerifiedCustomersScreen> createState() => _VerifiedCustomersScreenState();
}

class _VerifiedCustomersScreenState extends State<VerifiedCustomersScreen> {
  late final CustomerService _customerService;
  List<VerifiedCustomer> _customers = [];
  bool _isLoading = true;
  String _sortBy = 'name';

  @override
  void initState() {
    super.initState();
    _customerService = CustomerService(ApiClient());
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final customers = await _customerService.getVerifiedCustomers(
        orderBy: _sortBy,
      );
      
      if (mounted) {
        setState(() {
          _customers = customers;
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
            content: Text('Failed to load customers: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _changeSortOrder() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sort By',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildSortOption('name', 'Name (A-Z)', Icons.sort_by_alpha),
            _buildSortOption('recent', 'Recent Purchase', Icons.access_time),
            _buildSortOption('total_spent', 'Total Spent', Icons.trending_up),
          ],
        ),
      ),
    );
  }

  Widget _buildSortOption(String value, String label, IconData icon) {
    final isSelected = _sortBy == value;
    
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? AppColors.primaryGreen : Colors.grey,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? AppColors.primaryGreen : Colors.black87,
        ),
      ),
      trailing: isSelected
          ? const Icon(Icons.check, color: AppColors.primaryGreen)
          : null,
      onTap: () {
        Navigator.pop(context);
        setState(() {
          _sortBy = value;
        });
        _loadCustomers();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verified Customers'),
        backgroundColor: AppColors.primaryGreen,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _changeSortOrder,
            tooltip: 'Sort',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _customers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 80,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No verified customers yet',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadCustomers,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _customers.length,
                    itemBuilder: (context, index) {
                      final customer = _customers[index];
                      return _buildCustomerCard(customer);
                    },
                  ),
                ),
    );
  }

  Widget _buildCustomerCard(VerifiedCustomer customer) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 2,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        leading: CircleAvatar(
          backgroundColor: AppColors.primaryGreen.withOpacity(0.1),
          child: Text(
            customer.name.isNotEmpty ? customer.name[0].toUpperCase() : 'C',
            style: const TextStyle(
              color: AppColors.primaryGreen,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          customer.name,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            if (customer.phoneNumber != null)
              Text(
                customer.phoneNumber!,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.receipt, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  '${customer.totalBills} bills',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.currency_rupee, size: 14, color: Colors.grey[600]),
                Text(
                  customer.totalSpent.toStringAsFixed(0),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CustomerDetailScreen(
                customerId: customer.id,
                customerName: customer.name,
              ),
            ),
          );
        },
      ),
    );
  }
}
