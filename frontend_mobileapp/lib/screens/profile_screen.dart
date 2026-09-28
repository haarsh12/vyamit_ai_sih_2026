import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../core/shop_categories.dart';
import '../models/shop_details.dart';
import '../providers/auth_provider.dart';
import '../providers/bill_provider.dart';
import '../widgets/bill_receipt_widget.dart';
import '../features/gst/providers/gst_provider.dart';
import '../features/gst/widgets/gst_configuration_panel.dart';
import 'auth_selection_screen.dart';

class ProfileScreen extends StatefulWidget {
  // We remove the passed variable to rely on Provider for the source of truth
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  // Controllers for Shop Details
  late TextEditingController _shopNameCtrl;
  late TextEditingController _ownerNameCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _phone1Ctrl;
  late TextEditingController _phone2Ctrl;
  late TextEditingController _medicalRegistrationCtrl;
  late TextEditingController _qualificationsCtrl;
  late String _selectedShopCategory;

  // Edit State Triggers
  final Map<String, bool> _isEditing = {
    'shop': false,
    'owner': false,
    'address': false,
    'ph1': false,
    'ph2': false,
    'category': false,
    'medicalRegistration': false,
    'qualifications': false,
  };

  // Settings State
  String _selectedTemplate = 'en';
  String _appLanguage = 'en';
  bool _isQrEnabled = false;
  String? _uploadedQrPath;
  final ImagePicker _picker = ImagePicker();

  // Save loading state
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Load initial data from Provider
    final details =
        Provider.of<AuthProvider>(context, listen: false).shopDetails ??
            ShopDetails(
                shopName: "My Shop",
                ownerName: "Owner",
                address: "Address",
                phone1: "",
                phone2: "",
                shopCategory: "General");

    _shopNameCtrl = TextEditingController(text: details.shopName);
    _ownerNameCtrl = TextEditingController(text: details.ownerName);
    _addressCtrl = TextEditingController(text: details.address);
    _phone1Ctrl = TextEditingController(text: details.phone1);
    _phone2Ctrl = TextEditingController(text: details.phone2);
    _medicalRegistrationCtrl =
        TextEditingController(text: details.medicalRegistrationNumber);
    _qualificationsCtrl = TextEditingController(text: details.qualifications);
    _selectedShopCategory = canonicalShopCategory(details.shopCategory);

    // Load QR code from BillProvider
    final billProvider = Provider.of<BillProvider>(context, listen: false);
    _uploadedQrPath = billProvider.qrCodePath;
    _isQrEnabled = _uploadedQrPath != null && _uploadedQrPath!.isNotEmpty;
    Future.microtask(() async {
      try {
        await context.read<GstProvider>().loadConfiguration();
      } catch (_) {
        // Profile remains usable if the connection is unavailable; saving the
        // GST form will surface the authoritative backend error.
      }
    });
  }

  // --- LOGIC: UPDATE DETAILS & SYNC ---
  void _toggleEdit(String key) {
    // Special handling for phone1 (READ-ONLY)
    if (key == 'ph1') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "⚠️ Default phone number cannot be changed. It's your account identifier.",
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return; // Block editing
    }

    setState(() {
      _isEditing[key] = !_isEditing[key]!;

      // If we just finished editing (saved), trigger local update
      if (!_isEditing[key]!) {
        // Update happens in memory immediately for UI responsiveness
        final provider = Provider.of<AuthProvider>(context, listen: false);
        final current = provider.shopDetails!;

        // Update specific field based on key
        if (key == 'shop') current.shopName = _shopNameCtrl.text;
        if (key == 'owner') current.ownerName = _ownerNameCtrl.text;
        if (key == 'address') current.address = _addressCtrl.text;
        if (key == 'ph2') current.phone2 = _phone2Ctrl.text;
        if (key == 'category') current.shopCategory = _selectedShopCategory;
        if (key == 'medicalRegistration') {
          current.medicalRegistrationNumber = _medicalRegistrationCtrl.text;
        }
        if (key == 'qualifications') {
          current.qualifications = _qualificationsCtrl.text;
        }

        // Force UI rebuild to reflect changes in Preview
        setState(() {});
      }
    });
  }

  // NEW: Save all changes to database
  Future<void> _saveProfileToDatabase() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final provider = Provider.of<AuthProvider>(context, listen: false);

      // Call the update profile API
      await provider.updateProfile(
        shopName: _shopNameCtrl.text.trim(),
        ownerName: _ownerNameCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        phone2: _phone2Ctrl.text.trim(),
        shopCategory: _selectedShopCategory,
        medicalRegistrationNumber:
            _selectedShopCategory == 'Doctor Prescription'
                ? _medicalRegistrationCtrl.text.trim()
                : null,
        qualifications: _selectedShopCategory == 'Doctor Prescription'
            ? _qualificationsCtrl.text.trim()
            : null,
      );

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✓ Profile updated successfully!"),
            backgroundColor: AppColors.primaryGreen,
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Close any open edit modes
      setState(() {
        _isEditing['shop'] = false;
        _isEditing['owner'] = false;
        _isEditing['address'] = false;
        _isEditing['ph2'] = false;
        _isEditing['category'] = false;
        _isEditing['medicalRegistration'] = false;
        _isEditing['qualifications'] = false;
      });
    } catch (e) {
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ Failed to update profile: $e"),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _uploadQr() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        // Save to BillProvider for persistence
        final billProvider = Provider.of<BillProvider>(context, listen: false);
        await billProvider.saveQrCode(image.path);

        setState(() => _uploadedQrPath = image.path);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("QR Code Uploaded & Saved!")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error uploading QR: $e")));
    }
  }

  void _confirmLogout() {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text("Confirm Logout"),
                content: const Text("Are you sure you want to log out?"),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Cancel")),
                  ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        await Provider.of<AuthProvider>(context, listen: false)
                            .logout();
                        if (mounted) {
                          Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                  builder: (context) =>
                                      const AuthSelectionScreen()),
                              (route) => false);
                        }
                      },
                      style:
                          ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text("Logout",
                          style: TextStyle(color: Colors.white))),
                ]));
  }

  @override
  void dispose() {
    _shopNameCtrl.dispose();
    _ownerNameCtrl.dispose();
    _addressCtrl.dispose();
    _phone1Ctrl.dispose();
    _phone2Ctrl.dispose();
    _medicalRegistrationCtrl.dispose();
    _qualificationsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final details = Provider.of<AuthProvider>(context).shopDetails ??
        ShopDetails(
            shopName: "My Shop",
            ownerName: "Owner",
            address: "Address",
            phone1: "",
            phone2: "",
            shopCategory: "General");

    final isDoctor = _selectedShopCategory == 'Doctor Prescription';

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(title: const Text("Profile"), actions: [
        IconButton(
            icon: const Icon(Icons.logout, color: Colors.red),
            onPressed: _confirmLogout)
      ]),
      body: SingleChildScrollView(
        child: Column(children: [
          // 1. HEADER IMAGE - Dynamically updates on category change
          Container(
              width: double.infinity,
              height: 250,
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(30)),
                  border: const Border(
                      bottom:
                          BorderSide(color: AppColors.primaryGreen, width: 4)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 15,
                        offset: const Offset(0, 8))
                  ]),
              child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(26)),
                  child: Image.asset(
                      getShopCategoryImage(_selectedShopCategory),
                      key: ValueKey(_selectedShopCategory),
                      fit: BoxFit.cover,
                      errorBuilder: (c, e, s) => const Center(
                          child: Icon(Icons.store,
                              size: 100, color: AppColors.primaryGreen))))),

          Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 2. SHOP DETAILS SECTION (Editable)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(isDoctor ? "Doctor Profile" : "Shop Details",
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        // Save Button
                        ElevatedButton.icon(
                          onPressed: _isSaving ? null : _saveProfileToDatabase,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : const Icon(Icons.save, size: 18),
                          label: Text(_isSaving ? "Saving..." : "Save Changes"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),

                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(children: [
                              _buildEditableField(
                                  isDoctor
                                      ? "Clinic / Practice Name"
                                      : "Shop Name",
                                  _shopNameCtrl,
                                  'shop'),
                              _buildEditableField(
                                  isDoctor ? "Doctor Name" : "Owner Name",
                                  _ownerNameCtrl,
                                  'owner'),
                              _buildEditableField(
                                  "Address", _addressCtrl, 'address'),
                              _buildEditableField(
                                  "Phone 1 (Primary)", _phone1Ctrl, 'ph1',
                                  isPhone: true, isReadOnly: true),
                              _buildEditableField(
                                  "Phone 2 (Optional)", _phone2Ctrl, 'ph2',
                                  isPhone: true),
                              _buildShopCategoryRow(),
                              if (isDoctor) ...[
                                const Divider(height: 28),
                                const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Professional credentials',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                _buildEditableField(
                                  'Medical Registration Number',
                                  _medicalRegistrationCtrl,
                                  'medicalRegistration',
                                ),
                                _buildEditableField(
                                  'Qualifications',
                                  _qualificationsCtrl,
                                  'qualifications',
                                ),
                                const Padding(
                                  padding: EdgeInsets.only(top: 4),
                                  child: Text(
                                    'A medical registration number is required before a prescription can be printed.',
                                    style: TextStyle(
                                      color: Colors.deepOrange,
                                      fontSize: 12,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ]))),
                    const SizedBox(height: 16),
                    GstConfigurationPanel(
                      key: ValueKey(
                        context.watch<GstProvider>().configuration.gstin,
                      ),
                      configuration: context.watch<GstProvider>().configuration,
                    ),
                    const SizedBox(height: 30),

                    // 3. LANGUAGE SETTINGS
                    const Text("App Language",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(children: [
                              Row(children: [
                                Expanded(
                                    child: _buildOptionButton(
                                        "English",
                                        'en',
                                        _appLanguage,
                                        (val) => setState(
                                            () => _appLanguage = val))),
                                const SizedBox(width: 15),
                                Expanded(
                                    child: _buildOptionButton(
                                        "हिंदी (Hindi)",
                                        'hi',
                                        _appLanguage,
                                        (val) => setState(
                                            () => _appLanguage = val))),
                              ])
                            ]))),
                    const SizedBox(height: 30),

                    // 4. BILL SETTINGS
                    const Text("Bill Settings",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Select Template",
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 10),

                                  Row(children: [
                                    Expanded(
                                        child: _buildOptionButton(
                                            "Template 1\n(English)",
                                            'en',
                                            _selectedTemplate,
                                            (val) => setState(() =>
                                                _selectedTemplate = val))),
                                    const SizedBox(width: 15),
                                    Expanded(
                                        child: _buildOptionButton(
                                            "Template 2\n(Hindi)",
                                            'hi',
                                            _selectedTemplate,
                                            (val) => setState(() =>
                                                _selectedTemplate = val))),
                                  ]),
                                  const SizedBox(height: 20),

                                  Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text("Add UPI QR Code to Bill",
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold)),
                                        Switch(
                                            value: _isQrEnabled,
                                            activeColor: AppColors.primaryGreen,
                                            onChanged: (val) => setState(
                                                () => _isQrEnabled = val))
                                      ]),

                                  if (_isQrEnabled)
                                    Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 15),
                                        child: OutlinedButton.icon(
                                            onPressed: _uploadQr,
                                            icon: const Icon(Icons.upload),
                                            label:
                                                const Text("Upload QR Image"),
                                            style: OutlinedButton.styleFrom(
                                                foregroundColor:
                                                    AppColors.primaryGreen))),

                                  const SizedBox(height: 10),
                                  const Text("Live Preview:",
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12)),
                                  const SizedBox(height: 10),

                                  // PREVIEW WIDGET (Updates real-time with shop details)
                                  BillReceiptWidget(
                                      shopDetails: details,
                                      billId: "INV-PREVIEW",
                                      date: "24-1-2026",
                                      time: "19:45",
                                      items: const [
                                        {
                                          'en': 'Rice',
                                          'qty': '1 kg',
                                          'rate': 100.0,
                                          'total': 100.0,
                                          'unit': 'kg'
                                        },
                                        {
                                          'en': 'Sugar',
                                          'qty': '2 kg',
                                          'rate': 40.0,
                                          'total': 80.0,
                                          'unit': 'kg'
                                        },
                                        {
                                          'en': 'Milk',
                                          'qty': '2 L',
                                          'rate': 60.0,
                                          'total': 120.0,
                                          'unit': 'L'
                                        },
                                      ],
                                      total: 300.0,
                                      isHindi: _selectedTemplate == 'hi',
                                      showQr: _isQrEnabled,
                                      qrImagePath: _uploadedQrPath)
                                ]))),
                    const SizedBox(height: 30),

                    // 5. CONNECTED DEVICES BLOCK (New Requirement)
                    const Text("Connected Devices",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Card(
                      child: Column(children: [
                        _buildDeviceTile(Icons.smartphone_rounded,
                            "Current Device (Android)", true),
                        const Divider(height: 1),
                        _buildDeviceTile(Icons.laptop_mac_rounded,
                            "Owner's Laptop (Windows)", true),
                        const Divider(height: 1),
                        _buildDeviceTile(
                            Icons.tablet_android_rounded, "Shop Tablet", false),
                      ]),
                    ),
                    const SizedBox(height: 50),
                  ])),
        ]),
      ),
    );
  }

  // --- WIDGET HELPERS ---

  Widget _buildShopCategoryRow() {
    final isEditing = _isEditing['category']!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Shop type (category)",
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedShopCategory,
                    isExpanded: true,
                    items: kShopCategories
                        .map((c) =>
                            DropdownMenuItem<String>(value: c, child: Text(c)))
                        .toList(),
                    onChanged: isEditing
                        ? (v) {
                            if (v != null) {
                              setState(() => _selectedShopCategory = v);
                            }
                          }
                        : null,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _toggleEdit('category'),
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isEditing ? Icons.check : Icons.edit,
                    size: 18,
                    color: isEditing ? AppColors.primaryGreen : Colors.grey,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEditableField(
      String label, TextEditingController controller, String key,
      {bool isPhone = false, bool isReadOnly = false}) {
    bool isEditing = _isEditing[key]!;
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              Text(label,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              if (isReadOnly)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: const Text(
                    "READ ONLY",
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: controller,
                    enabled: isEditing && !isReadOnly,
                    keyboardType:
                        isPhone ? TextInputType.phone : TextInputType.text,
                    style: TextStyle(
                        color: (isEditing && !isReadOnly)
                            ? Colors.black
                            : Colors.grey[800],
                        fontWeight: FontWeight.w600,
                        fontSize: 15),
                    decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 0, vertical: 8),
                        border: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        enabledBorder: const UnderlineInputBorder(
                            borderSide:
                                BorderSide(color: AppColors.primaryGreen))))),
            IconButton(
                onPressed: isReadOnly ? null : () => _toggleEdit(key),
                icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: isReadOnly ? Colors.grey[200] : Colors.grey[100],
                        shape: BoxShape.circle),
                    child: Icon(
                        isReadOnly
                            ? Icons.lock
                            : (isEditing ? Icons.check : Icons.edit),
                        size: 18,
                        color: isReadOnly
                            ? Colors.grey
                            : (isEditing
                                ? AppColors.primaryGreen
                                : Colors.grey)))),
          ]),
        ]));
  }

  Widget _buildOptionButton(
      String label, String value, String currentValue, Function(String) onTap) {
    bool isSelected = currentValue == value;
    return GestureDetector(
        onTap: () => onTap(value),
        child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
                color: isSelected ? AppColors.primaryGreen : Colors.white,
                border: Border.all(
                    color: isSelected
                        ? AppColors.primaryGreen
                        : Colors.grey.shade300),
                borderRadius: BorderRadius.circular(10)),
            child: Center(
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: isSelected ? Colors.white : Colors.black,
                        fontWeight: FontWeight.bold)))));
  }

  Widget _buildDeviceTile(IconData icon, String name, bool isActive) {
    return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: isActive ? Colors.green.withOpacity(0.05) : Colors.white,
            border: Border(
                left: BorderSide(
                    color:
                        isActive ? AppColors.primaryGreen : Colors.transparent,
                    width: 4))),
        child: Row(children: [
          Icon(icon,
              color: isActive ? AppColors.primaryGreen : Colors.grey, size: 28),
          const SizedBox(width: 15),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                Text(isActive ? "Active Now" : "Last active: 2 hours ago",
                    style: TextStyle(
                        fontSize: 12,
                        color: isActive ? AppColors.primaryGreen : Colors.grey))
              ])),
          if (isActive)
            const Icon(Icons.check_circle,
                color: AppColors.primaryGreen, size: 22)
          else
            TextButton(
                onPressed: () {},
                child: const Text("Remove",
                    style: TextStyle(
                        color: Colors.red, fontWeight: FontWeight.bold))),
        ]));
  }
}
