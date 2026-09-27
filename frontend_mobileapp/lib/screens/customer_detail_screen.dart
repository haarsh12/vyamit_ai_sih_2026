import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../models/customer.dart';
import '../services/api_client.dart';
import '../services/customer_service.dart';
import '../widgets/bill_type_badge.dart';
import '../widgets/ledger_confirmation_dialog.dart';

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
  List<CustomerBillItem> _bills = const [];
  CustomerLedgerStatement? _ledger;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _customerService = CustomerService(ApiClient());
    _loadCustomerData();
  }

  Future<void> _loadCustomerData() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final results = await Future.wait<dynamic>([
        _customerService.getCustomerDetails(widget.customerId),
        _customerService.getCustomerBills(widget.customerId),
        _customerService.getCustomerLedger(widget.customerId),
      ]);
      if (!mounted) return;
      final billsData = Map<String, dynamic>.from(results[1] as Map);
      setState(() {
        _customerData = Map<String, dynamic>.from(results[0] as Map);
        _bills = List<CustomerBillItem>.from(billsData['bills'] as List);
        _ledger = results[2] as CustomerLedgerStatement;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load customer details: $error'), backgroundColor: Colors.red),
      );
    }
  }

  String _money(double amount) => '₹${amount.toStringAsFixed(2)}';
  String _date(DateTime value) => DateFormat('dd MMM yyyy • hh:mm a').format(value.toLocal());

  Future<void> _showAdjustmentForm(String entryType) async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final isUdhaar = entryType == 'udhaar';
    Map<String, dynamic>? draft;
    try {
      draft = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) {
          var isPreparing = false;
          String? formError;
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              title: Row(children: [
                Icon(isUdhaar ? Icons.add_card_rounded : Icons.payments_rounded, color: isUdhaar ? const Color(0xFFB54708) : AppColors.primaryGreen),
                const SizedBox(width: 10),
                Text(isUdhaar ? 'Add udhaar' : 'Record payment'),
              ]),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(isUdhaar ? 'This will increase the customer’s outstanding balance.' : 'This will reduce the customer’s outstanding balance.', style: const TextStyle(color: AppColors.textGrey, fontSize: 13)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountController,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ ', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    maxLength: 240,
                    decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder()),
                  ),
                  if (formError != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(formError!, style: const TextStyle(color: Color(0xFFB42318), fontSize: 12)),
                    ),
                ],
              ),
              actions: [
                TextButton(onPressed: isPreparing ? null : () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: isPreparing
                      ? null
                      : () async {
                          final amount = double.tryParse(amountController.text.trim());
                          if (amount == null || amount <= 0) {
                            setDialogState(() => formError = 'Enter a valid amount.');
                            return;
                          }
                          setDialogState(() {
                            isPreparing = true;
                            formError = null;
                          });
                          try {
                            final value = await _customerService.createLedgerDraft(
                              widget.customerId,
                              entryType: entryType,
                              amount: amount,
                              note: noteController.text,
                            );
                            if (dialogContext.mounted) Navigator.of(dialogContext).pop(value);
                          } catch (error) {
                            if (dialogContext.mounted) {
                              setDialogState(() {
                                isPreparing = false;
                                formError = 'Could not prepare change: $error';
                              });
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(backgroundColor: isUdhaar ? const Color(0xFFB54708) : AppColors.primaryGreen),
                  child: isPreparing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Review', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      amountController.dispose();
      noteController.dispose();
    }
    if (draft != null && mounted) await _confirmLedgerDraft(draft);
  }

  Future<void> _confirmLedgerDraft(Map<String, dynamic> draft) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LedgerConfirmationDialog(
        draft: draft,
        onConfirm: () async {
          try {
            await _customerService.confirmLedgerDraft(
              widget.customerId,
              draft['id'].toString(),
              (draft['version'] as num).toInt(),
            );
            return null;
          } catch (error) {
            return 'Ledger was not updated: $error';
          }
        },
      ),
    );
    if (confirmed != true || !mounted) return;
    await _loadCustomerData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ledger updated.'),
        backgroundColor: AppColors.primaryGreen,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFA),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: const Color(0xFFFAFBFA),
        foregroundColor: AppColors.textBlack,
        title: Text(widget.customerName, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
          : RefreshIndicator(
              color: AppColors.primaryGreen,
              onRefresh: _loadCustomerData,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _customerHero(),
                  const SizedBox(height: 18),
                  _ledgerCard(),
                  const SizedBox(height: 22),
                  _sectionTitle('Ledger activity', _ledger?.entries.length ?? 0),
                  const SizedBox(height: 10),
                  _ledgerTimeline(),
                  const SizedBox(height: 24),
                  _sectionTitle('Purchase history', _bills.length),
                  const SizedBox(height: 10),
                  if (_bills.isEmpty) _emptyPanel('No linked bills yet', Icons.receipt_long_outlined) else ..._bills.map(_billCard),
                ],
              ),
            ),
    );
  }

  Widget _customerHero() {
    final phone = _customerData?['phone_number']?.toString();
    final bills = (_customerData?['total_bills'] as num?)?.toInt() ?? 0;
    final spent = (_customerData?['total_spent'] as num?)?.toDouble() ?? 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.grey.shade200)),
      child: Row(children: [
        CircleAvatar(radius: 30, backgroundColor: AppColors.lightGreenBg, child: Text(widget.customerName.isEmpty ? 'C' : widget.customerName[0].toUpperCase(), style: const TextStyle(color: AppColors.primaryGreen, fontSize: 22, fontWeight: FontWeight.w800))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.customerName, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(phone?.isNotEmpty == true ? phone! : 'Verified customer', style: const TextStyle(color: AppColors.textGrey, fontSize: 13)),
          const SizedBox(height: 12),
          Row(children: [
            _metric('$bills', 'bills'),
            const SizedBox(width: 22),
            _metric(_money(spent), 'spent'),
          ]),
        ])),
      ]),
    );
  }

  Widget _metric(String value, String label) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)), Text(label, style: const TextStyle(color: AppColors.textGrey, fontSize: 11))]);

  Widget _ledgerCard() {
    final balance = _ledger?.currentBalance ?? ((_customerData?['ledger_balance'] as num?)?.toDouble() ?? 0);
    final hasDue = balance > 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: hasDue ? const [Color(0xFFB64D09), Color(0xFF7A2E08)] : const [Color(0xFF0A5B45), Color(0xFF123B32)]),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: (hasDue ? const Color(0xFFB64D09) : const Color(0xFF0A5B45)).withOpacity(.17), blurRadius: 20, offset: const Offset(0, 9))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFFFFE5C7), size: 20),
          const SizedBox(width: 8),
          Text(hasDue ? 'OUTSTANDING UDHAAR' : 'LEDGER SETTLED', style: const TextStyle(color: Color(0xFFFFE5C7), fontSize: 11, letterSpacing: .6, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 9),
        Text(_money(balance), style: const TextStyle(color: Colors.white, fontSize: 31, fontWeight: FontWeight.w800)),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: _ledgerAction('Add udhaar', Icons.add_rounded, () => _showAdjustmentForm('udhaar'))),
          const SizedBox(width: 10),
          Expanded(child: _ledgerAction('Record payment', Icons.south_west_rounded, balance <= 0 ? null : () => _showAdjustmentForm('payment'))),
        ]),
      ]),
    );
  }

  Widget _ledgerAction(String label, IconData icon, VoidCallback? onPressed) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      label: Text(label, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white54,
        side: BorderSide(color: Colors.white.withOpacity(.44)),
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 7),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _sectionTitle(String text, int count) => Row(
        children: [
          Text(
            text,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F3F2),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textGrey,
              ),
            ),
          ),
        ],
      );

  Widget _ledgerTimeline() {
    final entries = _ledger?.entries ?? const [];
    if (entries.isEmpty) return _emptyPanel('No udhaar or payment entries yet', Icons.account_balance_wallet_outlined);
    return Column(children: entries.map(_ledgerEntry).toList());
  }

  Widget _ledgerEntry(CustomerLedgerEntry entry) {
    final increase = entry.increasesBalance;
    final accent = increase ? const Color(0xFFB54708) : AppColors.primaryGreen;
    final label = increase ? 'Udhaar added' : 'Payment received';
    final source = entry.billId != null
        ? 'Bill #${entry.billId}'
        : switch (entry.source) {
            'voice' => 'Voice entry',
            'token_saver' => 'Token Saver entry',
            'gst_invoice' => 'GST invoice',
            _ => 'Manual entry',
          };
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17), border: Border.all(color: Colors.grey.shade200)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 38, height: 38, decoration: BoxDecoration(color: accent.withOpacity(.11), borderRadius: BorderRadius.circular(12)), child: Icon(increase ? Icons.north_east_rounded : Icons.south_west_rounded, color: accent, size: 20)),
        const SizedBox(width: 11),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 2),
          Text(entry.note?.isNotEmpty == true ? '${entry.note} • $source' : source, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textGrey, fontSize: 12)),
          const SizedBox(height: 4),
          Text(_date(entry.occurredAt), style: const TextStyle(color: AppColors.textGrey, fontSize: 11)),
        ])),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${increase ? '+' : '−'}${_money(entry.amount)}', style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 4),
          Text('Due ${_money(entry.balanceAfter)}', style: const TextStyle(color: AppColors.textGrey, fontSize: 10)),
        ]),
      ]),
    );
  }

  Widget _billCard(CustomerBillItem bill) {
    final isUdhaar = bill.paymentMethod == 'udhaar';
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17), border: Border.all(color: Colors.grey.shade200)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 15),
        leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: isUdhaar ? const Color(0xFFFFF1E8) : AppColors.lightGreenBg, borderRadius: BorderRadius.circular(12)), child: Icon(isUdhaar ? Icons.account_balance_wallet_rounded : Icons.receipt_long_rounded, color: isUdhaar ? const Color(0xFFB54708) : AppColors.primaryGreen, size: 20)),
        title: Row(children: [Text('Bill #${bill.id}', style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(width: 6), BillTypeBadge(billType: bill.billType)]),
        subtitle: Text('${_date(bill.billDate)} • ${bill.totalItems} items', style: const TextStyle(color: AppColors.textGrey, fontSize: 12)),
        trailing: Text(_money(bill.totalAmount), style: const TextStyle(fontWeight: FontWeight.w800)),
        children: [
          ...bill.items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(children: [Expanded(child: Text('${item['name']} • ${item['quantity']} ${item['unit']}', style: const TextStyle(fontSize: 13))), Text('₹${item['total']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))]),
          )),
          const Divider(height: 16),
          Row(children: [Text('Payment: ${isUdhaar ? 'Udhaar' : bill.paymentMethod.toUpperCase()}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isUdhaar ? const Color(0xFFB54708) : AppColors.textGrey)), const Spacer(), Text('Total ${_money(bill.totalAmount)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800))]),
        ],
      ),
    );
  }

  Widget _emptyPanel(String text, IconData icon) => Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17), border: Border.all(color: Colors.grey.shade200)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: Colors.grey.shade500, size: 20), const SizedBox(width: 9), Text(text, style: const TextStyle(color: AppColors.textGrey, fontSize: 13))]));
}
