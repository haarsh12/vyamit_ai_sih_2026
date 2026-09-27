import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/shop_details.dart';
import '../../providers/bill_provider.dart';
import '../../services/printer_service.dart';
import '../../widgets/udhaar_bill_confirmation_dialog.dart';
import 'models/gst_invoice_draft.dart';
import 'providers/gst_provider.dart';
import 'services/gst_service.dart';

class GstInvoicePreviewScreen extends StatefulWidget {
  final GstInvoiceDraft initialDraft;
  final ShopDetails shopDetails;
  final bool isPrinterConnected;
  final VoidCallback togglePrinter;

  const GstInvoicePreviewScreen({
    super.key,
    required this.initialDraft,
    required this.shopDetails,
    required this.isPrinterConnected,
    required this.togglePrinter,
  });

  @override
  State<GstInvoicePreviewScreen> createState() =>
      _GstInvoicePreviewScreenState();
}

class _GstInvoicePreviewScreenState extends State<GstInvoicePreviewScreen> {
  final GstService _service = GstService();
  late Map<String, dynamic> _customer;
  late List<Map<String, dynamic>> _items;
  Map<String, dynamic> _sellerOverride = {};
  Map<String, dynamic> _bankDetails = {};
  late DateTime _issueDate;
  late DateTime _dueDate;
  late String _referenceNumber;
  String _paymentStatus = 'PAID';
  String _paymentMethod = 'UPI';
  Map<String, dynamic>? _preview;
  int? _finalizedInvoiceId;
  Map<String, dynamic>? _finalizedInvoice;
  bool _isLoading = true;
  bool _isFinalizing = false;
  bool _udhaarApproved = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _customer = Map<String, dynamic>.from(widget.initialDraft.customer);
    _items = widget.initialDraft.items.map(Map<String, dynamic>.from).toList();
    _sellerOverride = Map<String, dynamic>.from(
        widget.initialDraft.sellerOverride ?? const {});
    _issueDate = DateTime.tryParse(widget.initialDraft.issueDate ?? '') ??
        DateTime.now();
    _dueDate = DateTime.tryParse(widget.initialDraft.dueDate ?? '') ??
        _issueDate.add(const Duration(days: 30));
    
    // Normalize payment method to uppercase for dropdown compatibility
    _paymentMethod = widget.initialDraft.paymentMethod.toUpperCase();
    _paymentStatus = widget.initialDraft.paymentStatus.toUpperCase();
    
    _referenceNumber = widget.initialDraft.referenceNumber ?? '';
    _bankDetails =
        Map<String, dynamic>.from(widget.initialDraft.bankDetails ?? const {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshPreview());
  }

  GstInvoiceDraft get _draft => GstInvoiceDraft(
        customer: _customer,
        items: _items,
        sellerOverride: _sellerOverride.isEmpty ? null : _sellerOverride,
        issueDate: _issueDate.toIso8601String(),
        dueDate: _dueDate.toIso8601String(),
        paymentMethod: _paymentMethod.toLowerCase(),  // Convert back to lowercase for API
        verifiedCustomerId: widget.initialDraft.verifiedCustomerId,
        paymentStatus: _paymentStatus,  // Keep uppercase for API
        referenceNumber: _referenceNumber,
        bankDetails: _bankDetails,
      );

  String _parseErrorMessage(dynamic error) {
    final errorStr = error.toString();
    
    // Check for validation errors in the error message
    if (errorStr.contains('state_code must be a valid Indian GST state')) {
      return 'Invalid State Code\n\nPlease select a valid Indian state code (01-37) instead of "00" or other invalid codes.\n\nCommon codes:\n• Maharashtra: 27\n• Delhi: 07\n• Karnataka: 29\n• Tamil Nadu: 33';
    }
    
    if (errorStr.contains('Datetimes provided to dates should have zero time')) {
      return 'Date Format Error\n\nThere was an issue with the date format. Please try selecting the dates again from the date picker.';
    }
    
    if (errorStr.contains('GSTIN checksum is invalid')) {
      return 'Invalid GSTIN Number\n\nThe GSTIN number you entered has an invalid checksum. Please verify and correct your GSTIN.';
    }
    
    if (errorStr.contains('Connection Error') || errorStr.contains('Backend')) {
      return 'Connection Error\n\nUnable to connect to the server. Please check if:\n• Your internet connection is active\n• The backend server is running\n• The server URL is correctly configured';
    }
    
    if (errorStr.contains('Server Error 422')) {
      return 'Validation Error\n\nSome required fields are missing or invalid. Please check:\n• State code is valid (not "00")\n• All required customer details are filled\n• Item quantities and prices are valid';
    }
    
    // Return a cleaned version of the error
    return 'Error Loading Preview\n\n${errorStr.replaceAll('Exception:', '').replaceAll('Error:', '').trim()}';
  }

  Future<void> _refreshPreview() async {
    if (_finalizedInvoiceId != null) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final preview = await _service.previewInvoice(_draft.toJson());
      if (!mounted) return;

      final serverBankDetails = preview['bank_details'];
      setState(() {
        if (_bankDetails.isEmpty && serverBankDetails is Map) {
          _bankDetails = Map<String, dynamic>.from(serverBankDetails);
        }
        _preview = preview;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _parseErrorMessage(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _money(dynamic paise) {
    final value = paise is num ? paise.toInt() : int.tryParse('$paise') ?? 0;
    final sign = value < 0 ? '-' : '';
    final absolute = value.abs();
    return '$sign₹${absolute ~/ 100}.${(absolute % 100).toString().padLeft(2, '0')}';
  }

  String _numberToWords(double number) {
    int intVal = number.round();
    if (intVal == 0) return "Zero Rupees Only";

    final units = [
      "",
      "One",
      "Two",
      "Three",
      "Four",
      "Five",
      "Six",
      "Seven",
      "Eight",
      "Nine",
      "Ten",
      "Eleven",
      "Twelve",
      "Thirteen",
      "Fourteen",
      "Fifteen",
      "Sixteen",
      "Seventeen",
      "Eighteen",
      "Nineteen"
    ];
    final tens = [
      "",
      "",
      "Twenty",
      "Thirty",
      "Forty",
      "Fifty",
      "Sixty",
      "Seventy",
      "Eighty",
      "Ninety"
    ];

    String convertLessThanThousand(int n) {
      if (n == 0) return "";
      if (n < 20) return units[n];
      if (n < 100) return "${tens[n ~/ 10]} ${units[n % 10]}".trim();
      return "${units[n ~/ 100]} Hundred ${convertLessThanThousand(n % 100)}"
          .trim();
    }

    String result = "";
    if (intVal >= 10000000) {
      result += "${convertLessThanThousand(intVal ~/ 10000000)} Crore ";
      intVal %= 10000000;
    }
    if (intVal >= 100000) {
      result += "${convertLessThanThousand(intVal ~/ 100000)} Lakh ";
      intVal %= 100000;
    }
    if (intVal >= 1000) {
      result += "${convertLessThanThousand(intVal ~/ 1000)} Thousand ";
      intVal %= 1000;
    }
    if (intVal > 0) {
      result += convertLessThanThousand(intVal);
    }

    return "${result.trim()} Rupees Only";
  }

  Widget _sectionTitle(String value, IconData icon) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.primaryGreen),
            const SizedBox(width: 8),
            Text(value,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textBlack)),
          ],
        ),
      );

  Widget _editableField({
    required String label,
    required String initialValue,
    required ValueChanged<String> onChanged,
    TextInputType? keyboardType,
    bool enabled = true,
    int maxLines = 1,
    String? hintText,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        key: ValueKey('$label-$initialValue'),
        initialValue: initialValue,
        enabled: enabled && _finalizedInvoiceId == null,
        keyboardType: keyboardType,
        maxLines: maxLines,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Future<void> _pickDate(bool isIssueDate) async {
    final initial = isIssueDate ? _issueDate : _dueDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        if (isIssueDate) {
          _issueDate = picked;
        } else {
          _dueDate = picked;
        }
      });
      _refreshPreview();
    }
  }

  Widget _sellerSection(Map<String, dynamic> seller) {
    final values = {...seller, ..._sellerOverride};
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Seller Details (Editable Invoice Snapshot)',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 12),
          _editableField(
              label: 'Business / Shop Name',
              initialValue: values['business_name']?.toString() ??
                  widget.shopDetails.shopName,
              onChanged: (value) => _sellerOverride['business_name'] = value),
          _editableField(
              label: 'Legal Name (Optional)',
              initialValue: values['legal_name']?.toString() ?? '',
              onChanged: (value) => _sellerOverride['legal_name'] = value),
          _editableField(
              label: 'Seller GSTIN',
              initialValue: values['gstin']?.toString() ?? '',
              onChanged: (_) {},
              enabled: false),
          _editableField(
              label: 'Street Address',
              initialValue: values['address_line']?.toString() ??
                  widget.shopDetails.address,
              onChanged: (value) => _sellerOverride['address_line'] = value),
          Row(children: [
            Expanded(
                child: _editableField(
                    label: 'City',
                    initialValue: values['city']?.toString() ?? 'Nagpur',
                    onChanged: (value) => _sellerOverride['city'] = value)),
            const SizedBox(width: 8),
            Expanded(
                child: _editableField(
                    label: 'State',
                    initialValue: values['state']?.toString() ?? 'Maharashtra',
                    onChanged: (value) => _sellerOverride['state'] = value)),
          ]),
          _editableField(
              label: 'Seller Contact Phone',
              initialValue: values['contact_number']?.toString() ??
                  widget.shopDetails.phone1,
              onChanged: (value) => _sellerOverride['contact_number'] = value),
          _editableField(
              label: 'Seller Email',
              initialValue: values['email']?.toString() ?? '',
              onChanged: (value) => _sellerOverride['email'] = value),
        ]),
      ),
    );
  }

  Widget _customerSection() => Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Buyer / Customer Details',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 12),
            _editableField(
                label: 'Customer / Business Name',
                initialValue:
                    _customer['name']?.toString() ?? 'Walk-in customer',
                onChanged: (value) => _customer['name'] = value),
            _editableField(
                label: 'Customer GSTIN (Optional)',
                initialValue: _customer['gstin']?.toString() ?? '',
                onChanged: (value) => _customer['gstin'] = value),
            _editableField(
                label: 'Customer Address',
                initialValue: _customer['address_line']?.toString() ?? '',
                onChanged: (value) => _customer['address_line'] = value,
                maxLines: 2),
            Row(children: [
              Expanded(
                  child: _editableField(
                      label: 'State',
                      initialValue:
                          _customer['state']?.toString() ?? 'Maharashtra',
                      onChanged: (value) => _customer['state'] = value)),
              const SizedBox(width: 8),
              Expanded(
                  child: _editableField(
                      label: 'State Code',
                      initialValue: _customer['state_code']?.toString() ?? '27',
                      onChanged: (value) => _customer['state_code'] = value,
                      keyboardType: TextInputType.number)),
            ]),
            Row(children: [
              Expanded(
                  child: _editableField(
                      label: 'City',
                      initialValue: _customer['city']?.toString() ?? '',
                      onChanged: (value) => _customer['city'] = value)),
              const SizedBox(width: 8),
              Expanded(
                  child: _editableField(
                      label: 'Pincode',
                      initialValue: _customer['pincode']?.toString() ?? '',
                      onChanged: (value) => _customer['pincode'] = value,
                      keyboardType: TextInputType.number)),
            ]),
            _editableField(
                label: 'Customer Phone',
                initialValue: _customer['phone']?.toString() ?? '',
                onChanged: (value) => _customer['phone'] = value,
                keyboardType: TextInputType.phone),
          ]),
        ),
      );

  Widget _bankDetailsSection() => Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Bank Details (For Direct Payments)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 12),
            _editableField(
                label: 'Bank Name',
                initialValue: _bankDetails['bank_name']?.toString() ?? '',
                hintText: 'e.g. HDFC Bank',
                onChanged: (v) => _bankDetails['bank_name'] = v),
            _editableField(
                label: 'Account Name',
                initialValue: _bankDetails['account_name']?.toString() ?? '',
                hintText: 'e.g. Harsh General Store',
                onChanged: (v) => _bankDetails['account_name'] = v),
            _editableField(
                label: 'Account Number',
                initialValue: _bankDetails['account_number']?.toString() ?? '',
                onChanged: (v) => _bankDetails['account_number'] = v),
            _editableField(
                label: 'IFSC Code',
                initialValue: _bankDetails['ifsc']?.toString() ?? '',
                hintText: 'e.g. HDFC000XXXX',
                onChanged: (v) => _bankDetails['ifsc'] = v),
          ]),
        ),
      );

  Widget _itemCard(int index, Map<String, dynamic> previewItem) {
    final editable = _items[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade300)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            Expanded(
                child: _editableField(
                    label: 'Item Name',
                    initialValue: editable['name']?.toString() ?? '',
                    onChanged: (value) => editable['name'] = value)),
            IconButton(
              onPressed: _items.length == 1
                  ? null
                  : () {
                      setState(() => _items.removeAt(index));
                      _refreshPreview();
                    },
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Remove item',
            ),
          ]),
          Row(children: [
            Expanded(
                child: _editableField(
                    label: 'Quantity',
                    initialValue: editable['quantity']?.toString() ?? '1',
                    onChanged: (value) => editable['quantity'] = value,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true))),
            const SizedBox(width: 8),
            Expanded(
                child: _editableField(
                    label: 'Unit',
                    initialValue: editable['unit']?.toString() ?? 'PCS',
                    onChanged: (value) => editable['unit'] = value)),
            const SizedBox(width: 8),
            Expanded(
                child: _editableField(
                    label: 'Rate (₹)',
                    initialValue: editable['rate']?.toString() ?? '0',
                    onChanged: (value) => editable['rate'] = value,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true))),
          ]),
          Row(children: [
            Expanded(
                child: _editableField(
                    label: 'GST %',
                    initialValue: editable['gst_rate']?.toString() ?? '0',
                    onChanged: (value) => editable['gst_rate'] = value,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true))),
            const SizedBox(width: 8),
            Expanded(
                child: _editableField(
                    label: 'HSN / SAC Code',
                    initialValue: editable['hsn_code']?.toString() ??
                        editable['sac_code']?.toString() ??
                        '',
                    onChanged: (value) => editable['hsn_code'] = value)),
          ]),
          const Divider(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Taxable: ${_money(previewItem['taxable_value_paise'])}',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            Text('GST @ ${previewItem['gst_rate'] ?? '0'}%',
                style: const TextStyle(fontSize: 12)),
            Text('Total: ${_money(previewItem['total_amount_paise'])}',
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryGreen)),
          ]),
        ]),
      ),
    );
  }

  Future<void> _finalizeAndPrint() async {
    // Check printer connection in real-time
    final isConnected = await PrinterService().isConnected();
    
    if (!isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Connect the printer before finalizing a GST invoice.')));
      widget.togglePrinter();
      return;
    }

    if (_paymentMethod == 'UDHAAR' && !_udhaarApproved) {
      if (widget.initialDraft.verifiedCustomerId == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Select a verified customer before setting this invoice as udhaar.'),
          backgroundColor: Colors.red,
        ));
        return;
      }

      final totalPaise =
          (_preview?['totals']?['grand_total_paise'] as num? ?? 0).toDouble();
      final approved = await showDialog<bool>(
        context: context,
        builder: (_) => UdhaarBillConfirmationDialog(
          customerName: _customer['name']?.toString() ?? 'this customer',
          amount: totalPaise / 100,
        ),
      );
      if (approved != true || !mounted) return;
      setState(() => _udhaarApproved = true);
    }

    setState(() => _isFinalizing = true);
    var printedOnDevice = false;
    try {
      Map<String, dynamic> invoice;
      int invoiceId;
      if (_finalizedInvoiceId != null && _finalizedInvoice != null) {
        invoice = _finalizedInvoice!;
        invoiceId = _finalizedInvoiceId!;
      } else {
        final response = await _service.finalizeInvoice(_draft.toJson());
        invoice = Map<String, dynamic>.from(response['invoice'] as Map);
        invoiceId = response['invoice_id'] as int;

        if (!mounted) return;
        setState(() {
          _finalizedInvoice = invoice;
          _finalizedInvoiceId = invoiceId;
        });
      }
      final qrPath = context.read<BillProvider>().qrCodePath;
      final printResult = await PrinterService()
          .printGstInvoice(invoice, widget.shopDetails, qrPath);
      if (printResult != 'Success') {
        throw StateError(printResult);
      }
      printedOnDevice = true;
      await _service.markInvoicePrinted(invoiceId);
      if (!mounted) return;
      context.read<GstProvider>().resetCurrentBill();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✓ GST invoice printed and saved.'),
          backgroundColor: AppColors.primaryGreen));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      if (printedOnDevice) {
        context.read<GstProvider>().resetCurrentBill();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('GST invoice printed. Syncing status...'),
          backgroundColor: AppColors.primaryGreen,
        ));
        Navigator.of(context).pop(true);
        return;
      }
      final retainedInvoice = _finalizedInvoiceId != null;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(retainedInvoice
            ? 'Invoice saved but not printed: $error'
            : 'GST invoice could not be finalized: $error'),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) setState(() => _isFinalizing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final grandTotalPaise = preview != null
        ? (preview['totals']?['grand_total_paise'] as num? ?? 0).toDouble()
        : 0.0;
    final amountInWords = _numberToWords(grandTotalPaise / 100.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review GST Invoice'),
        actions: [
          IconButton(
            tooltip: 'Connect Printer',
            icon: Icon(Icons.print_rounded,
                color: widget.isPrinterConnected
                    ? AppColors.printerConnected
                    : AppColors.printerDisconnected),
            onPressed: widget.togglePrinter,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red.shade400,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 15),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.arrow_back),
                              label: const Text('Go Back'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 12),
                              ),
                            ),
                            const SizedBox(width: 16),
                            ElevatedButton.icon(
                              onPressed: _refreshPreview,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryGreen,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
              : preview == null
                  ? const SizedBox.shrink()
                  : Column(children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            // Status Banner
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.lightGreenBg,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: AppColors.primaryGreen
                                        .withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.verified_rounded,
                                            color: AppColors.primaryGreen,
                                            size: 18),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text('TAX INVOICE DETAILS ARE EDITABLE',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  color: AppColors.primaryGreen)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Review and edit any detail before printing, then recalculate totals to refresh the invoice preview.',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[800]),
                                    ),
                                  ]),
                            ),

                            // INVOICE META & DATES
                            _sectionTitle('Invoice Meta & Options',
                                Icons.edit_calendar_rounded),
                            Card(
                              elevation: 1,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(children: [
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(
                                        Icons.calendar_today_outlined,
                                        color: AppColors.primaryGreen),
                                    title: const Text('Invoice Issue Date'),
                                    subtitle: Text(
                                        '${_issueDate.day.toString().padLeft(2, '0')}/${_issueDate.month.toString().padLeft(2, '0')}/${_issueDate.year}'),
                                    trailing: const Icon(Icons.edit, size: 18),
                                    onTap: _finalizedInvoiceId == null
                                        ? () => _pickDate(true)
                                        : null,
                                  ),
                                  const Divider(height: 1),
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(Icons.event_outlined,
                                        color: AppColors.primaryGreen),
                                    title: const Text('Payment Due Date'),
                                    subtitle: Text(
                                        '${_dueDate.day.toString().padLeft(2, '0')}/${_dueDate.month.toString().padLeft(2, '0')}/${_dueDate.year}'),
                                    trailing: const Icon(Icons.edit, size: 18),
                                    onTap: _finalizedInvoiceId == null
                                        ? () => _pickDate(false)
                                        : null,
                                  ),
                                  const Divider(height: 1),
                                  const SizedBox(height: 10),
                                  _editableField(
                                    label: 'Reference Number (Optional)',
                                    initialValue: _referenceNumber,
                                    hintText:
                                        'Your purchase order or customer reference',
                                    onChanged: (value) =>
                                        _referenceNumber = value,
                                  ),
                                  Row(children: [
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        initialValue: _paymentStatus,
                                        decoration: const InputDecoration(
                                            labelText: 'Payment Status',
                                            isDense: true,
                                            border: OutlineInputBorder()),
                                        items: const [
                                          DropdownMenuItem(
                                              value: 'PAID',
                                              child: Text('PAID')),
                                          DropdownMenuItem(
                                              value: 'UNPAID',
                                              child: Text('UNPAID')),
                                          DropdownMenuItem(
                                              value: 'PARTIAL',
                                              child: Text('PARTIAL')),
                                        ],
                                        onChanged: _finalizedInvoiceId == null
                                            ? (val) => setState(
                                                () => _paymentStatus = val!)
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        initialValue: _paymentMethod,
                                        decoration: const InputDecoration(
                                            labelText: 'Payment Method',
                                            isDense: true,
                                            border: OutlineInputBorder()),
                                        items: const [
                                          DropdownMenuItem(
                                              value: 'UPI', child: Text('UPI')),
                                          DropdownMenuItem(
                                              value: 'CASH',
                                              child: Text('CASH')),
                                          DropdownMenuItem(
                                              value: 'CARD',
                                              child: Text('CARD')),
                                          DropdownMenuItem(
                                              value: 'NET_BANKING',
                                              child: Text('NET BANKING')),
                                          DropdownMenuItem(
                                              value: 'UDHAAR',
                                              child: Text('UDHAAR')),
                                        ],
                                        onChanged: _finalizedInvoiceId == null
                                            ? (val) => setState(() {
                                                _paymentMethod = val!;
                                                _udhaarApproved = false;
                                              })
                                            : null,
                                      ),
                                    ),
                                  ]),
                                ]),
                              ),
                            ),

                            // SELLER DETAILS
                            _sectionTitle(
                                'Seller Information', Icons.storefront_rounded),
                            _sellerSection(Map<String, dynamic>.from(
                                preview['seller'] as Map)),

                            // CUSTOMER DETAILS
                            _sectionTitle('Buyer / Customer Information',
                                Icons.person_outline_rounded),
                            _customerSection(),

                            // LINE ITEMS
                            _sectionTitle('Invoice Line Items',
                                Icons.inventory_2_outlined),
                            ...List.generate(
                              _items.length,
                              (index) => _itemCard(
                                  index,
                                  Map<String, dynamic>.from((preview['items']
                                      as List)[index] as Map)),
                            ),
                            Row(children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _finalizedInvoiceId == null
                                      ? () {
                                          setState(() => _items.add({
                                                'name': 'New item',
                                                'quantity': '1',
                                                'unit': 'PCS',
                                                'rate': '100',
                                                'gst_rate': '18'
                                              }));
                                          _refreshPreview();
                                        }
                                      : null,
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add Item'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _finalizedInvoiceId == null
                                      ? _refreshPreview
                                      : null,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Recalculate Totals'),
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primaryGreen,
                                      foregroundColor: Colors.white),
                                ),
                              ),
                            ]),

                            // BANK DETAILS
                            _sectionTitle('Bank Account Details',
                                Icons.account_balance_outlined),
                            _bankDetailsSection(),

                            // SUMMARY & TOTALS
                            _sectionTitle('Tax Summary & Totals',
                                Icons.receipt_long_outlined),
                            Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _totalRow(
                                        'Subtotal (Taxable Value)',
                                        _money(preview['totals']
                                            ?['taxable_value_paise'])),
                                    _totalRow(
                                        'CGST',
                                        _money(preview['totals']
                                            ?['cgst_amount_paise'])),
                                    _totalRow(
                                        'SGST',
                                        _money(preview['totals']
                                            ?['sgst_amount_paise'])),
                                    _totalRow(
                                        'IGST',
                                        _money(preview['totals']
                                            ?['igst_amount_paise'])),
                                    _totalRow(
                                        'Total GST Tax',
                                        _money(preview['totals']
                                            ?['total_tax_paise'])),
                                    const Divider(height: 20),
                                    _totalRow(
                                        'GRAND TOTAL',
                                        _money(preview['totals']
                                            ?['grand_total_paise']),
                                        strong: true),
                                    const SizedBox(height: 10),
                                    const Text('Amount in Words:',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12)),
                                    Text(amountInWords,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.primaryGreen)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 90),
                          ],
                        ),
                      ),
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed:
                                  _isFinalizing ? null : _finalizeAndPrint,
                              icon: _isFinalizing
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.print_rounded),
                              label: Text(
                                _isFinalizing
                                    ? 'FINALIZING & PRINTING…'
                                    : _finalizedInvoiceId == null
                                        ? 'FINALIZE & PRINT INVOICE'
                                        : 'RETRY PRINT',
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryGreen,
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(54),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ]),
    );
  }

  Widget _totalRow(String label, String value, {bool strong = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style: TextStyle(
                  fontWeight: strong ? FontWeight.w800 : FontWeight.normal,
                  fontSize: strong ? 16 : 14)),
          Text(value,
              style: TextStyle(
                  fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
                  fontSize: strong ? 18 : 14,
                  color: strong ? AppColors.primaryGreen : Colors.black87)),
        ]),
      );
}
