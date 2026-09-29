import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/customer.dart';
import '../services/api_client.dart';
import '../services/customer_service.dart';
import 'customer_detail_screen.dart';

class VerifiedCustomersScreen extends StatefulWidget {
  const VerifiedCustomersScreen({super.key});

  @override
  State<VerifiedCustomersScreen> createState() =>
      _VerifiedCustomersScreenState();
}

class _VerifiedCustomersScreenState extends State<VerifiedCustomersScreen> {
  late final CustomerService _customerService;
  final TextEditingController _searchController = TextEditingController();
  List<VerifiedCustomer> _customers = const [];
  bool _isLoading = true;
  String _sortBy = 'name';
  String _query = '';
  int _totalCustomers = 0;
  double _totalOutstanding = 0;

  @override
  void initState() {
    super.initState();
    _customerService = CustomerService(ApiClient());
    _searchController.addListener(
        () => setState(() => _query = _searchController.text.trim()));
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    if (mounted && _customers.isEmpty) setState(() => _isLoading = true);
    try {
      final result =
          await _customerService.getVerifiedCustomerList(orderBy: _sortBy);
      if (!mounted) return;
      setState(() {
        _customers = result.customers;
        _totalCustomers = result.total;
        _totalOutstanding = result.totalOutstandingLedger;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (_customers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Could not load customers: $error'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  List<VerifiedCustomer> get _visibleCustomers {
    if (_query.isEmpty) return _customers;
    final term = _query.toLowerCase();
    return _customers.where((customer) {
      return customer.name.toLowerCase().contains(term) ||
          (customer.phoneNumber?.contains(term) ?? false);
    }).toList();
  }

  String _money(double amount) => '₹${amount.toStringAsFixed(0)}';

  void _showSortSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(99))),
            const SizedBox(height: 18),
            const Align(
                alignment: Alignment.centerLeft,
                child: Text('Sort customers',
                    style:
                        TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
            const SizedBox(height: 10),
            _sortOption('name', 'Name, A to Z', Icons.sort_by_alpha_rounded),
            _sortOption('recent', 'Recent activity', Icons.schedule_rounded),
            _sortOption(
                'total_spent', 'Highest spend', Icons.trending_up_rounded),
          ],
        ),
      ),
    );
  }

  Widget _sortOption(String value, String label, IconData icon) {
    final selected = _sortBy == value;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
            color: selected ? AppColors.lightGreenBg : const Color(0xFFF5F7F7),
            borderRadius: BorderRadius.circular(14)),
        child: Icon(icon,
            color: selected ? AppColors.primaryGreen : Colors.black54),
      ),
      title: Text(label,
          style: TextStyle(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
      trailing: selected
          ? const Icon(Icons.check_circle_rounded,
              color: AppColors.primaryGreen)
          : null,
      onTap: () {
        Navigator.pop(context);
        if (_sortBy == value) return;
        setState(() => _sortBy = value);
        _loadCustomers();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final customers = _visibleCustomers;
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFA),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: const Color(0xFFFAFBFA),
        foregroundColor: AppColors.textBlack,
        title: const Text('Customers',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
              onPressed: _showSortSheet,
              icon: const Icon(Icons.tune_rounded),
              tooltip: 'Sort customers'),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primaryGreen,
        onRefresh: _loadCustomers,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            _ledgerSummary(),
            const SizedBox(height: 18),
            TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search by name or phone',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _searchController.clear),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 15),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.grey.shade200)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.grey.shade200)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(
                        color: AppColors.primaryGreen, width: 1.5)),
              ),
            ),
            const SizedBox(height: 22),
            Row(children: [
              Text(_query.isEmpty ? 'Verified customers' : 'Search results',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('${customers.length} shown',
                  style:
                      const TextStyle(color: AppColors.textGrey, fontSize: 12)),
            ]),
            const SizedBox(height: 12),
            if (_isLoading)
              const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primaryGreen)))
            else if (customers.isEmpty)
              _emptyState()
            else
              ...customers.map(_customerCard),
          ],
        ),
      ),
    );
  }

  Widget _ledgerSummary() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0A5B45), Color(0xFF123B32)]),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF0A5B45).withOpacity(.18),
              blurRadius: 20,
              offset: const Offset(0, 10))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.account_balance_wallet_rounded,
                color: Color(0xFFC8F2D2), size: 20),
            SizedBox(width: 8),
            Text('TOTAL OUTSTANDING UDHAAR',
                style: TextStyle(
                    color: Color(0xFFC8F2D2),
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    letterSpacing: .6)),
          ]),
          const SizedBox(height: 10),
          Text(_money(_totalOutstanding),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.5)),
          const SizedBox(height: 15),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(.12),
                borderRadius: BorderRadius.circular(10)),
            child: Text(
                '$_totalCustomers verified ${_totalCustomers == 1 ? 'customer' : 'customers'}',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _customerCard(VerifiedCustomer customer) {
    final hasDue = customer.ledgerBalance > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () async {
            await Navigator.push<void>(
                context,
                MaterialPageRoute(
                    builder: (_) => CustomerDetailScreen(
                        customerId: customer.id, customerName: customer.name)));
            if (mounted) _loadCustomers();
          },
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.grey.shade200)),
            child: Row(children: [
              CircleAvatar(
                radius: 24,
                backgroundColor:
                    hasDue ? const Color(0xFFFFF1E8) : AppColors.lightGreenBg,
                child: Text(
                    customer.name.isEmpty
                        ? 'C'
                        : customer.name[0].toUpperCase(),
                    style: TextStyle(
                        color: hasDue
                            ? const Color(0xFFB54708)
                            : AppColors.primaryGreen,
                        fontWeight: FontWeight.w800,
                        fontSize: 17)),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(customer.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 3),
                      Text(
                          customer.phoneNumber?.isNotEmpty == true
                              ? customer.phoneNumber!
                              : '${customer.totalBills} bills • ${_money(customer.totalSpent)} spent',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.textGrey, fontSize: 12)),
                      const SizedBox(height: 9),
                      Row(children: [
                        const Icon(Icons.receipt_long_outlined,
                            size: 14, color: AppColors.textGrey),
                        const SizedBox(width: 4),
                        Text('${customer.totalBills} bills',
                            style: const TextStyle(
                                color: AppColors.textGrey, fontSize: 12))
                      ]),
                    ]),
              ),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(hasDue ? 'UDHAAR DUE' : 'SETTLED',
                    style: TextStyle(
                        color: hasDue
                            ? const Color(0xFFB54708)
                            : const Color(0xFF137333),
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                        letterSpacing: .35)),
                const SizedBox(height: 4),
                Text(_money(customer.ledgerBalance),
                    style: TextStyle(
                        color: hasDue
                            ? const Color(0xFFB54708)
                            : AppColors.textBlack,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
              ]),
              const SizedBox(width: 3),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF9AA4A2)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    final searching = _query.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 44),
      child: Center(
          child: Column(children: [
        Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
                color: AppColors.lightGreenBg, shape: BoxShape.circle),
            child: Icon(
                searching
                    ? Icons.search_off_rounded
                    : Icons.people_outline_rounded,
                size: 34,
                color: AppColors.primaryGreen)),
        const SizedBox(height: 14),
        Text(searching ? 'No matching customer' : 'No verified customers yet',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 5),
        Text(
            searching
                ? 'Try a different name or phone number.'
                : 'Save a named bill to start a customer ledger.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textGrey)),
      ])),
    );
  }
}
