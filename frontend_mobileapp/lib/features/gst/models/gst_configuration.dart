class GstConfiguration {
  final bool isEnabled;
  final bool canIssueTaxInvoice;
  final String verificationStatus;
  final String businessName;
  final String legalName;
  final String gstin;
  final String addressLine;
  final String city;
  final String state;
  final String stateCode;
  final String country;
  final String pincode;
  final String contactNumber;
  final String email;
  final String registrationType;
  final String invoicePrefix;
  final String invoiceTerms;
  final List<String> allowedGstRates;
  final String bankName;
  final String accountName;
  final String accountNumber;
  final String ifsc;

  const GstConfiguration({
    required this.isEnabled,
    this.canIssueTaxInvoice = false,
    this.verificationStatus = 'not_configured',
    this.businessName = '',
    this.legalName = '',
    this.gstin = '',
    this.addressLine = '',
    this.city = '',
    this.state = '',
    this.stateCode = '',
    this.country = 'India',
    this.pincode = '',
    this.contactNumber = '',
    this.email = '',
    this.registrationType = 'regular',
    this.invoicePrefix = 'GST',
    this.invoiceTerms = '',
    this.allowedGstRates = const ['0', '5', '12', '18', '28'],
    this.bankName = '',
    this.accountName = '',
    this.accountNumber = '',
    this.ifsc = '',
  });

  factory GstConfiguration.fromJson(Map<String, dynamic> json) {
    return GstConfiguration(
      isEnabled: json['is_enabled'] == true,
      canIssueTaxInvoice: json['can_issue_tax_invoice'] == true,
      verificationStatus: json['verification_status']?.toString() ?? 'not_configured',
      businessName: json['business_name']?.toString() ?? '',
      legalName: json['legal_name']?.toString() ?? '',
      gstin: json['gstin']?.toString() ?? '',
      addressLine: json['address_line']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      stateCode: json['state_code']?.toString() ?? '',
      country: json['country']?.toString() ?? 'India',
      pincode: json['pincode']?.toString() ?? '',
      contactNumber: json['contact_number']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      registrationType: json['registration_type']?.toString() ?? 'regular',
      invoicePrefix: json['invoice_prefix']?.toString() ?? 'GST',
      invoiceTerms: json['invoice_terms']?.toString() ?? '',
      allowedGstRates: (json['allowed_gst_rates'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(),
      bankName: json['bank_name']?.toString() ?? '',
      accountName: json['account_name']?.toString() ?? '',
      accountNumber: json['account_number']?.toString() ?? '',
      ifsc: json['ifsc']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'business_name': businessName,
        'legal_name': legalName.isEmpty ? null : legalName,
        'gstin': gstin,
        'address_line': addressLine,
        'city': city,
        'state': state,
        'state_code': stateCode,
        'country': country,
        'pincode': pincode,
        'contact_number': contactNumber.isEmpty ? null : contactNumber,
        'email': email.isEmpty ? null : email,
        'registration_type': registrationType,
        'invoice_prefix': invoicePrefix,
        'invoice_terms': invoiceTerms.isEmpty ? null : invoiceTerms,
        'allowed_gst_rates': allowedGstRates,
        'bank_name': bankName.isEmpty ? null : bankName,
        'account_name': accountName.isEmpty ? null : accountName,
        'account_number': accountNumber.isEmpty ? null : accountNumber,
        'ifsc': ifsc.isEmpty ? null : ifsc,
      };
}
