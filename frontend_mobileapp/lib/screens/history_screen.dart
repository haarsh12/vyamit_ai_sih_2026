import 'package:flutter/material.dart';
import '../models/shop_details.dart';
import '../models/dashboard.dart';
import '../core/theme.dart';
import '../services/analytics_service.dart';
import '../services/auth_token_store.dart';
import '../widgets/dashboard_summary_card.dart';
import '../widgets/top_selling_items_widget.dart';
import '../widgets/category_pie_chart.dart';
import '../widgets/peak_hours_chart.dart';
import '../widgets/bill_type_badge.dart';
import '../models/customer.dart';
import '../services/api_client.dart';
import '../services/customer_service.dart';
import 'verified_customers_screen.dart';
import 'customer_detail_screen.dart';
import 'package:intl/intl.dart';

class HistoryScreen extends StatefulWidget {
  final ShopDetails shopDetails;

  const HistoryScreen({
    super.key,
    required this.shopDetails,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final AnalyticsService _analyticsService = AnalyticsService();
  late final CustomerService _customerService;
  DashboardData? _dashboardData;
  List<BillHistory> _bills = [];
  List<VerifiedCustomer> _verifiedCustomers = [];
  bool _isLoading = true;
  String? _token;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _customerService = CustomerService(ApiClient());
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      _token = await AuthTokenStore().read();
      if (_token == null) {
        throw const AnalyticsRequestException(
          'Your session has expired. Please sign in again.',
        );
      }

      final dashboard = await _analyticsService.getDashboard(_token!);
      final bills = await _analyticsService.getBills(_token!);
      final customers = await _customerService.getVerifiedCustomers(limit: 10);
      if (!mounted) return;
      setState(() {
        _dashboardData = dashboard;
        _bills = bills;
        _verifiedCustomers = customers;
        _loadError = null;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
        _isLoading = false;
      });
    }
  }

  String _formatNumber(double value) {
    if (value == value.toInt()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  String _formatCurrency(double value) {
    if (value >= 100000) {
      return '₹${(value / 100000).toStringAsFixed(1)}L';
    } else if (value >= 1000) {
      return '₹${(value / 1000).toStringAsFixed(1)}K';
    }
    return '₹${_formatNumber(value)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Dashboard"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black87),
            onPressed: _loadData,
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF8F9FA),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    children: [
                      const SizedBox(height: 120),
                      const Icon(
                        Icons.cloud_off_rounded,
                        size: 60,
                        color: Colors.redAccent,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Dashboard data could not be loaded',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _loadError!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Pull down or tap refresh after reconnecting.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Summary Cards - 2x2 Grid
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.4,
                      children: [
                        DashboardSummaryCard(
                          title: 'Total Revenue',
                          value: _formatCurrency(_dashboardData?.summary.totalRevenue ?? 0),
                          icon: Icons.currency_rupee,
                          color: Colors.green,
                        ),
                        DashboardSummaryCard(
                          title: 'Total Bills',
                          value: (_dashboardData?.summary.totalBills ?? 0).toString(),
                          icon: Icons.receipt_long,
                          color: Colors.blue,
                        ),
                        DashboardSummaryCard(
                          title: 'Avg Bill Value',
                          value: _formatCurrency(_dashboardData?.summary.averageBillValue ?? 0),
                          icon: Icons.trending_up,
                          color: Colors.orange,
                        ),
                        DashboardSummaryCard(
                          title: 'Inventory Items',
                          value: (_dashboardData?.summary.totalInventoryItems ?? 0).toString(),
                          icon: Icons.inventory_2,
                          color: Colors.purple,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Top Selling Items and Category Chart - Side by Side
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TopSellingItemsWidget(
                            items: _dashboardData?.topSellingItems ?? [],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: CategoryPieChart(
                            categories: _dashboardData?.categoryBreakdown ?? [],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Peak Hours Chart - Full Width
                    PeakHoursChart(
                      peakHours: _dashboardData?.peakHours ?? [],
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Verified Customers Section
                    _buildVerifiedCustomersSection(),
                    
                    const SizedBox(height: 24),
                    
                    // Bills History Section
                    const Text(
                      'Bill History',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    if (_bills.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            children: [
                              Icon(
                                Icons.history_toggle_off_rounded,
                                size: 60,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'No bills found',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Print a bill to see it here',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _bills.length,
                        itemBuilder: (context, index) {
                          final bill = _bills[index];
                          return Card(
                            elevation: 2,
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            margin: const EdgeInsets.only(bottom: 12),
                            child: InkWell(
                              onTap: () => _showBillDetails(bill),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: bill.billType == 'virtual' 
                                          ? Colors.blue[50] 
                                          : AppColors.lightGreenBg,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        bill.billingSource == 'frequent'
                                            ? Icons.bolt_rounded
                                            : bill.billType == 'virtual'
                                                ? Icons.phone_android
                                                : Icons.print,
                                        color: bill.billType == 'virtual' 
                                            ? Colors.blue
                                            : bill.billingSource == 'frequent'
                                                ? Colors.orange
                                                : AppColors.primaryGreen,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 4,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              Text(
                                                'Bill #${bill.id}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              BillTypeBadge(billType: bill.billType),
                                              BillingSourceBadge(
                                                billingSource: bill.billingSource,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${DateFormat('dd MMM yyyy').format(bill.billDate)} • ${DateFormat('hh:mm a').format(bill.billDate)}',
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 12,
                                            ),
                                          ),
                                          if (bill.customerName != null)
                                            Text(
                                              bill.customerName!,
                                              style: TextStyle(
                                                color: Colors.grey[600],
                                                fontSize: 12,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      width: 70,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerRight,
                                            child: Text(
                                              '₹${_formatNumber(bill.totalAmount)}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 18,
                                                color: AppColors.primaryGreen,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${bill.totalItems} items',
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildVerifiedCustomersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Verified Customers',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const VerifiedCustomersScreen(),
                  ),
                ).then((_) => _loadData());
              },
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const Text('View All'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryGreen,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        if (_verifiedCustomers.isEmpty)
          Card(
            elevation: 1,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.people_outline,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No verified customers yet',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Print or share a named bill, then save the customer',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _verifiedCustomers.length,
              itemBuilder: (context, index) {
                final customer = _verifiedCustomers[index];
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CustomerDetailScreen(
                          customerId: customer.id,
                          customerName: customer.name,
                        ),
                      ),
                    ).then((_) => _loadData());
                  },
                  child: Container(
                    width: 140,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: AppColors.lightGreenBg,
                            child: Text(
                              customer.name[0].toUpperCase(),
                              style: const TextStyle(
                                color: AppColors.primaryGreen,
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            customer.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${customer.totalBills} bills',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  void _showBillDetails(BillHistory bill) {
    // Get shop details from widget
    final shopName = widget.shopDetails.shopName;
    final shopAddress = widget.shopDetails.address;
    final shopPhone1 = widget.shopDetails.phone1;
    final shopPhone2 = widget.shopDetails.phone2;
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 700),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Customer Name Header
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  bill.customerName ?? 'Walk-in',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
              
              // Phone Number
              if (bill.customerPhone != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Ph: ${bill.customerPhone}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                ),
              
              Divider(height: 1, color: Colors.grey[300]),
              
              // Bill details
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Bill ID and Date Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Bill ID: ${bill.id}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black87,
                            ),
                          ),
                          Text(
                            DateFormat('dd-MM-yyyy').format(bill.billDate),
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      
                      // Time and Cust ID Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Time: ${DateFormat('hh:mm:ss a').format(bill.billDate)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                          Text(
                            'Cust ID: ${bill.id.toString().padLeft(3, '0')}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Table Header
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: Colors.grey[300]!),
                            bottom: BorderSide(color: Colors.grey[300]!),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: Text(
                                'ITEM',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                'QTY',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                'RATE',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                'PRICE',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // Items List
                      ...bill.items.map((item) {
                        final name = item['name'] ?? '';
                        
                        // Try to get qty_display first, then fall back to qty/quantity
                        String qtyDisplay;
                        if (item['qty_display'] != null && item['qty_display'].toString().isNotEmpty) {
                          qtyDisplay = item['qty_display'].toString();
                        } else {
                          final qty = item['quantity'] ?? item['qty'] ?? 0;
                          final qtyDouble = qty is num ? qty.toDouble() : (double.tryParse(qty.toString()) ?? 0.0);
                          final unit = item['unit'] ?? '';
                          qtyDisplay = '${_formatNumber(qtyDouble)}${unit}';
                        }
                        
                        final unit = item['unit'] ?? '';
                        final price = item['price'] ?? item['rate'] ?? 0;
                        final total = item['total'] ?? 0;
                        
                        final priceDouble = price is num ? price.toDouble() : (double.tryParse(price.toString()) ?? 0.0);
                        final totalDouble = total is num ? total.toDouble() : (double.tryParse(total.toString()) ?? 0.0);
                        
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: Colors.grey[200]!),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 4,
                                child: Text(
                                  name.toString(),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  qtyDisplay,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '₹${_formatNumber(priceDouble)}/$unit',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '₹${_formatNumber(totalDouble)}',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      
                      const SizedBox(height: 16),
                      
                      // Total Section
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: Colors.grey[300]!, width: 1),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'TOTAL:',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            Text(
                              '₹${_formatNumber(bill.totalAmount)}',
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // Footer
                      Center(
                        child: Column(
                          children: [
                            Text(
                              'THANK YOU, VISIT AGAIN',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 12,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              shopName,
                              style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'App: Vyamit AI',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Close Button
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
