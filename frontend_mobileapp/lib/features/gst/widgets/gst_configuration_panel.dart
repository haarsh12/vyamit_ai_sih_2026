import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../models/gst_configuration.dart';
import '../providers/gst_provider.dart';

const Map<String, String> kIndianStatesWithCodes = {
  'Maharashtra': '27',
  'Delhi': '07',
  'Gujarat': '24',
  'Karnataka': '29',
  'Uttar Pradesh': '09',
  'Madhya Pradesh': '23',
  'Tamil Nadu': '33',
  'West Bengal': '19',
  'Rajasthan': '08',
  'Telangana': '36',
  'Andhra Pradesh': '37',
  'Bihar': '10',
  'Punjab': '03',
  'Haryana': '06',
  'Kerala': '32',
  'Assam': '18',
  'Jharkhand': '20',
  'Odisha': '21',
  'Chhattisgarh': '22',
  'Uttarakhand': '05',
  'Himachal Pradesh': '02',
  'Jammu and Kashmir': '01',
  'Goa': '30',
  'Chandigarh': '04',
  'Puducherry': '34',
  'Arunachal Pradesh': '12',
  'Dadra and Nagar Haveli and Daman and Diu': '26',
  'Ladakh': '38',
  'Lakshadweep': '31',
  'Manipur': '14',
  'Meghalaya': '17',
  'Mizoram': '15',
  'Nagaland': '13',
  'Sikkim': '11',
  'Tripura': '16',
  'Andaman and Nicobar Islands': '35',
};

const Map<String, List<String>> kCitiesByState = {
  'Maharashtra': [
    'Mumbai',
    'Nagpur',
    'Pune',
    'Nashik',
    'Thane',
    'Navi Mumbai',
    'Aurangabad',
    'Solapur',
    'Other'
  ],
  'Delhi': ['New Delhi', 'Delhi', 'Dwarka', 'Rohini', 'Other'],
  'Gujarat': ['Ahmedabad', 'Surat', 'Vadodara', 'Rajkot', 'Other'],
  'Karnataka': ['Bengaluru', 'Mysuru', 'Hubballi', 'Mangaluru', 'Other'],
  'Tamil Nadu': [
    'Chennai',
    'Coimbatore',
    'Madurai',
    'Tiruchirappalli',
    'Other'
  ],
  'Telangana': ['Hyderabad', 'Warangal', 'Nizamabad', 'Other'],
  'Andhra Pradesh': ['Visakhapatnam', 'Vijayawada', 'Guntur', 'Other'],
  'Madhya Pradesh': ['Indore', 'Bhopal', 'Jabalpur', 'Gwalior', 'Other'],
  'Rajasthan': ['Jaipur', 'Jodhpur', 'Kota', 'Udaipur', 'Other'],
  'West Bengal': ['Kolkata', 'Howrah', 'Siliguri', 'Other'],
  'Uttar Pradesh': ['Lucknow', 'Kanpur', 'Agra', 'Varanasi', 'Meerut', 'Other'],
  'Bihar': ['Patna', 'Gaya', 'Bhagalpur', 'Other'],
  'Punjab': ['Ludhiana', 'Amritsar', 'Jalandhar', 'Other'],
  'Haryana': ['Gurugram', 'Faridabad', 'Panipat', 'Other'],
  'Kerala': ['Kochi', 'Thiruvananthapuram', 'Kozhikode', 'Other'],
  'Goa': ['Panaji', 'Margao', 'Vasco da Gama', 'Other'],
  'Chandigarh': ['Chandigarh', 'Other'],
};

class GstConfigurationPanel extends StatefulWidget {
  final GstConfiguration configuration;

  const GstConfigurationPanel({super.key, required this.configuration});

  @override
  State<GstConfigurationPanel> createState() => _GstConfigurationPanelState();
}

class _GstConfigurationPanelState extends State<GstConfigurationPanel>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _businessName;
  late final TextEditingController _legalName;
  late final TextEditingController _gstin;
  late final TextEditingController _address;
  late final TextEditingController _city;
  late final TextEditingController _customCity;
  late final TextEditingController _state;
  late final TextEditingController _stateCode;
  late final TextEditingController _pincode;
  late final TextEditingController _contact;
  late final TextEditingController _email;
  late final TextEditingController _prefix;
  late final TextEditingController _terms;
  late final TextEditingController _rates;
  late final TextEditingController _bankName;
  late final TextEditingController _accountName;
  late final TextEditingController _accountNumber;
  late final TextEditingController _ifsc;
  bool _isExpanded = false;
  bool _isCustomCity = false;

  @override
  void initState() {
    super.initState();
    final config = widget.configuration;
    _businessName = TextEditingController(text: config.businessName);
    _legalName = TextEditingController(text: config.legalName);
    _gstin = TextEditingController(text: config.gstin);
    _address = TextEditingController(text: config.addressLine);
    _state = TextEditingController(
        text: config.state.isEmpty ? 'Maharashtra' : config.state);
    _stateCode = TextEditingController(
        text: config.stateCode.isEmpty ? '27' : config.stateCode);
    final cities = _citiesForState(_state.text);
    _city = TextEditingController(
        text: config.city.isEmpty ? cities.first : config.city);
    _customCity = TextEditingController();

    // Check if initial city is in standard list
    if (config.city.isNotEmpty && !cities.contains(config.city)) {
      _isCustomCity = true;
      _customCity.text = config.city;
      _city.text = 'Other';
    }

    _pincode = TextEditingController(text: config.pincode);
    _contact = TextEditingController(text: config.contactNumber);
    _email = TextEditingController(text: config.email);
    _prefix = TextEditingController(
        text: config.invoicePrefix.isEmpty ? 'GST' : config.invoicePrefix);
    _terms = TextEditingController(text: config.invoiceTerms);
    _rates = TextEditingController(
        text: config.allowedGstRates.isEmpty
            ? '0, 5, 12, 18, 28'
            : config.allowedGstRates.join(', '));
    _bankName = TextEditingController(text: config.bankName);
    _accountName = TextEditingController(text: config.accountName);
    _accountNumber = TextEditingController(text: config.accountNumber);
    _ifsc = TextEditingController(text: config.ifsc);
  }

  List<String> _citiesForState(String state) =>
      kCitiesByState[state] ?? const ['Other'];

  @override
  void dispose() {
    for (final controller in [
      _businessName,
      _legalName,
      _gstin,
      _address,
      _city,
      _customCity,
      _state,
      _stateCode,
      _pincode,
      _contact,
      _email,
      _prefix,
      _terms,
      _rates,
      _bankName,
      _accountName,
      _accountNumber,
      _ifsc,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _required(String? value, String label) =>
      value == null || value.trim().isEmpty ? '$label is required' : null;

  String? _gstinValidator(String? value) {
    final gstin = (value ?? '').replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (gstin.isEmpty) return 'GSTIN is required';
    if (!RegExp(r'^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$')
        .hasMatch(gstin)) {
      return 'Enter a valid 15-character GSTIN';
    }
    const characters = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    var factor = 2;
    var total = 0;
    for (final codeUnit in gstin.substring(0, 14).codeUnits.reversed) {
      final valueAt = characters.indexOf(String.fromCharCode(codeUnit));
      final product = valueAt * factor;
      total += (product ~/ 36) + (product % 36);
      factor = factor == 2 ? 1 : 2;
    }
    final check = characters[(36 - (total % 36)) % 36];
    if (check != gstin[14]) return 'GSTIN checksum is invalid';
    return null;
  }

  List<String>? _parseRates() {
    final values = _rates.text
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (values.isEmpty ||
        values.any((value) {
          final rate = double.tryParse(value);
          return rate == null || rate < 0 || rate > 40;
        })) {
      return null;
    }
    return values.toSet().toList()
      ..sort((a, b) => double.parse(a).compareTo(double.parse(b)));
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final rates = _parseRates();
    if (rates == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Enter comma-separated GST rates between 0 and 40.')),
      );
      return;
    }

    final finalCity =
        _isCustomCity ? _customCity.text.trim() : _city.text.trim();
    if (finalCity.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('City is required')),
      );
      return;
    }

    final configuration = GstConfiguration(
      isEnabled: false,
      businessName: _businessName.text.trim(),
      legalName: _legalName.text.trim(),
      gstin: _gstin.text.replaceAll(RegExp(r'\s+'), '').toUpperCase(),
      addressLine: _address.text.trim(),
      city: finalCity,
      state: _state.text.trim(),
      stateCode: _stateCode.text.trim().padLeft(2, '0'),
      pincode: _pincode.text.trim(),
      contactNumber: _contact.text.trim(),
      email: _email.text.trim(),
      invoicePrefix: _prefix.text.trim().toUpperCase(),
      invoiceTerms: _terms.text.trim(),
      allowedGstRates: rates,
      bankName: _bankName.text.trim(),
      accountName: _accountName.text.trim(),
      accountNumber: _accountNumber.text.trim(),
      ifsc: _ifsc.text.trim().toUpperCase(),
    );
    try {
      await context.read<GstProvider>().saveConfiguration(configuration);
      if (!mounted) return;
      setState(() => _isExpanded = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ GST configuration saved and enabled.'),
          backgroundColor: AppColors.primaryGreen,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('GST configuration could not be saved: $error'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _disable() async {
    try {
      await context.read<GstProvider>().disableConfiguration();
      if (mounted) setState(() => _isExpanded = false);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('GST Billing could not be disabled: $error'),
            backgroundColor: Colors.red),
      );
    }
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? hint,
    bool readOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        maxLines: maxLines,
        readOnly: readOnly,
        textCapitalization: TextCapitalization.words,
        decoration:
            InputDecoration(labelText: label, hintText: hint, isDense: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GstProvider>();
    final enabled = provider.isShopGstEnabled;
    return Card(
      child: Column(
        children: [
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: CircleAvatar(
              backgroundColor: (enabled ? AppColors.primaryGreen : Colors.grey)
                  .withOpacity(0.14),
              child: Icon(Icons.receipt_long_rounded,
                  color: enabled ? AppColors.primaryGreen : Colors.grey[700]),
            ),
            title: const Text('GST Billing',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(enabled
                ? 'GST Enabled • Validated profile'
                : 'Set up seller GST details'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: enabled ? AppColors.primaryGreen : Colors.grey[400],
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    enabled ? 'ENABLED' : 'DISABLED',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(_isExpanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
            onTap: () => setState(() => _isExpanded = !_isExpanded),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: _isExpanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Divider(),
                          const Text('Seller GST configuration',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 12),
                          _field('Business / shop name *', _businessName,
                              validator: (value) =>
                                  _required(value, 'Business name')),
                          _field('Legal business name (optional)', _legalName),
                          _field('GSTIN *', _gstin, validator: _gstinValidator),
                          _field('Address *', _address,
                              validator: (value) => _required(value, 'Address'),
                              maxLines: 2),

                          // STATE & CITY DROPDOWNS
                          Row(children: [
                            // State Dropdown
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: DropdownButtonFormField<String>(
                                  value: kIndianStatesWithCodes
                                          .containsKey(_state.text)
                                      ? _state.text
                                      : 'Maharashtra',
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                      labelText: 'State *', isDense: true),
                                  items: kIndianStatesWithCodes.keys
                                      .map((st) => DropdownMenuItem(
                                          value: st,
                                          child: Text(st,
                                              overflow: TextOverflow.ellipsis)))
                                      .toList(),
                                  onChanged: (selectedState) {
                                    if (selectedState != null) {
                                      setState(() {
                                        _state.text = selectedState;
                                        final code = kIndianStatesWithCodes[
                                                selectedState] ??
                                            '27';
                                        _stateCode.text = code;
                                        _city.text =
                                            _citiesForState(selectedState)
                                                .first;
                                        _customCity.clear();
                                        _isCustomCity = false;
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            // City Dropdown
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: DropdownButtonFormField<String>(
                                  value: _citiesForState(_state.text)
                                          .contains(_city.text)
                                      ? _city.text
                                      : 'Other',
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                      labelText: 'City *', isDense: true),
                                  items: _citiesForState(_state.text)
                                      .map((c) => DropdownMenuItem(
                                          value: c,
                                          child: Text(c,
                                              overflow: TextOverflow.ellipsis)))
                                      .toList(),
                                  onChanged: (selectedCity) {
                                    if (selectedCity != null) {
                                      setState(() {
                                        _city.text = selectedCity;
                                        _isCustomCity =
                                            (selectedCity == 'Other');
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),
                          ]),

                          // Custom City input if 'Other' selected
                          if (_isCustomCity)
                            _field('Enter City Name *', _customCity,
                                validator: (v) => _isCustomCity
                                    ? _required(v, 'City name')
                                    : null),

                          Row(children: [
                            Expanded(
                                child: _field('GST state code', _stateCode,
                                    readOnly: true,
                                    keyboardType: TextInputType.number)),
                            const SizedBox(width: 10),
                            Expanded(
                                child: _field('Pincode *', _pincode,
                                    validator: (value) => RegExp(r'^\d{6}$')
                                            .hasMatch((value ?? '').trim())
                                        ? null
                                        : 'Use 6 digits',
                                    keyboardType: TextInputType.number)),
                          ]),
                          _field('Contact number (optional)', _contact,
                              keyboardType: TextInputType.phone),
                          _field('Email (optional)', _email,
                              keyboardType: TextInputType.emailAddress),

                          Row(children: [
                            Expanded(
                              child: _field(
                                'Invoice prefix *',
                                _prefix,
                                hint: 'GST creates GST-2026-00001',
                                validator: (value) =>
                                    RegExp(r'^[A-Za-z0-9\-\/]{1,10}$')
                                            .hasMatch((value ?? '').trim())
                                        ? null
                                        : '1–10 letters/numbers',
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                                child: _field('GST rates *', _rates,
                                    hint: '0, 5, 12, 18, 28')),
                          ]),
                          _field('Invoice terms (optional)', _terms,
                              maxLines: 2),
                          const Text('Bank details (optional)',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          _field('Bank name', _bankName,
                              hint: 'e.g. HDFC Bank'),
                          _field('Account name', _accountName,
                              hint: 'e.g. Harsh General Store'),
                          Row(children: [
                            Expanded(
                                child: _field('Account number', _accountNumber,
                                    keyboardType: TextInputType.number)),
                            const SizedBox(width: 10),
                            Expanded(
                                child: _field('IFSC code', _ifsc,
                                    hint: 'e.g. HDFC000XXXX')),
                          ]),
                          const Text(
                            'This validates GSTIN structure and state consistency. It does not verify live registration status with the GST portal.',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                                height: 1.35),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (enabled)
                                TextButton(
                                  onPressed:
                                      provider.isSaving ? null : _disable,
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 8),
                                  ),
                                  child: const Text('Disable GST',
                                      style: TextStyle(
                                          color: Colors.red,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ElevatedButton.icon(
                                onPressed: provider.isSaving ? null : _save,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryGreen,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                ),
                                icon: provider.isSaving
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white))
                                    : const Icon(Icons.check_circle_outline,
                                        size: 18),
                                label: Text(provider.isSaving
                                    ? 'Validating...'
                                    : (enabled ? 'Change' : 'Confirm GST')),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
