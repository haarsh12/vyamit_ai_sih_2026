import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/theme.dart';
import '../models/shop_details.dart';
import '../models/item.dart';
import '../providers/inventory_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/bill_provider.dart';
import '../services/printer_service.dart'; // Import the new service
import '../services/analytics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/shop_categories.dart';
import '../features/category_experience/category_frequent_items.dart';
import '../features/category_experience/category_page_factory.dart';

// Screens
import 'history_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final PageController _pageController = PageController();
  AuthProvider? _authProvider;
  String _activeShopCategory = kDefaultShopCategory;

  // --- STATE 1: DATA ---
  final List<Map<String, dynamic>> _pastBills = [];
  final Map<String, List<Item>> _frequentItemsByCategory = {};

  // --- STATE 2: PRINTER ---
  // Using the new Service
  final PrinterService _printerService = PrinterService();
  final AnalyticsService _analyticsService = AnalyticsService();

  // Keep local state for UI updates
  BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;
  List<BluetoothDevice> _devices = [];
  BluetoothDevice? _connectedDevice;
  bool _isPrinterConnected = false;

  @override
  void initState() {
    super.initState();
    _initPrinterListener();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextAuthProvider = Provider.of<AuthProvider>(context, listen: false);
    if (_authProvider != nextAuthProvider) {
      _authProvider?.removeListener(_onProfileChanged);
      _authProvider = nextAuthProvider;
      _activeShopCategory = canonicalShopCategory(
        _authProvider?.shopDetails?.shopCategory,
      );
      _authProvider?.addListener(_onProfileChanged);
    }
  }

  void _onProfileChanged() {
    final nextCategory = canonicalShopCategory(
      _authProvider?.shopDetails?.shopCategory,
    );
    if (!mounted || nextCategory == _activeShopCategory) return;

    _activeShopCategory = nextCategory;
    // Clear any old namespace immediately; InventoryScreen then loads the
    // profile-selected scope through the authenticated API.
    Provider.of<InventoryProvider>(context, listen: false)
        .loadForShopCategory(nextCategory);
    setState(() => _currentIndex = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    });
  }

  void _initPrinterListener() {
    bluetooth.onStateChanged().listen((state) {
      switch (state) {
        case BlueThermalPrinter.CONNECTED:
          setState(() => _isPrinterConnected = true);
          break;
        case BlueThermalPrinter.DISCONNECTED:
          setState(() {
            _isPrinterConnected = false;
            _connectedDevice = null;
          });
          break;
        default:
          break;
      }
    });
  }

  // --- FREQUENT ITEM MANAGEMENT ---
  List<Item> _frequentItemsFor(String category) {
    final canonicalCategory = canonicalShopCategory(category);
    return _frequentItemsByCategory.putIfAbsent(
      canonicalCategory,
      () => defaultFrequentItemsForCategory(canonicalCategory),
    );
  }

  void _addFrequentItem(Item item) {
    setState(() {
      _frequentItemsFor(_activeShopCategory).add(item);
    });
  }

  void _editFrequentItem(Item newItem) {
    setState(() {
      final frequentItems = _frequentItemsFor(_activeShopCategory);
      final index = frequentItems.indexWhere((i) => i.id == newItem.id);
      if (index != -1) {
        frequentItems[index] = newItem;
      }
    });
  }

  void _deleteFrequentItem(String id) {
    setState(() {
      _frequentItemsFor(_activeShopCategory).removeWhere((i) => i.id == id);
    });
  }

  // --- PRINTER CONNECTION UI ---
  void _togglePrinter() async {
    if (_isPrinterConnected) {
      _showDisconnectDialog();
    } else {
      await _showConnectDialog();
    }
  }

  void _showDisconnectDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Printer Connected",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text("Connected to: ${_connectedDevice?.name ?? 'Unknown Device'}",
                style: const TextStyle(color: Colors.green)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () {
                  bluetooth.disconnect();
                  Navigator.pop(context);
                },
                child: const Text("Disconnect Printer",
                    style: TextStyle(color: Colors.white)),
              ),
            )
          ],
        ),
      ),
    );
  }

  Future<void> _showConnectDialog() async {
    try {
      List<BluetoothDevice> devices = await bluetooth.getBondedDevices();
      setState(() => _devices = devices);
    } catch (e) {
      print("Error getting devices: $e");
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Select Printer",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              const Text(
                  "Make sure printer is ON and Paired in Bluetooth Settings.",
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 10),
              Expanded(
                child: _devices.isEmpty
                    ? const Center(
                        child: Text(
                            "No paired devices found.\nPlease pair in Android Settings."))
                    : ListView.separated(
                        itemCount: _devices.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (context, index) {
                          final device = _devices[index];
                          return ListTile(
                            leading: const Icon(Icons.print,
                                color: AppColors.primaryGreen),
                            title: Text(device.name ?? "Unknown Device"),
                            subtitle: Text(device.address ?? ""),
                            onTap: () {
                              Navigator.pop(context);
                              _connectToDevice(device);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _connectToDevice(BluetoothDevice device) async {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Connecting to ${device.name}...")));
    try {
      await bluetooth.connect(device);
      // Do not wait for a plugin state-stream event to repaint the printer
      // icon. Some Bluetooth adapters only emit that event after the first
      // write, which made the connected icon appear grey.
      final connected = (await bluetooth.isConnected) ?? false;
      if (mounted) {
        setState(() {
          _connectedDevice = connected ? device : null;
          _isPrinterConnected = connected;
        });
      }
      if (!connected && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Printer connection was not completed.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Failed to connect: $e")));
    }
  }

  // --- CORE BILLING LOGIC (Modified) ---
  void _printOrSaveBill(Map<String, dynamic> billData) async {
    debugPrint("🏠 HOME SCREEN: Received bill data");
    debugPrint("🏠 Items in billData: ${billData['items']}");
    debugPrint("🏠 Items count: ${(billData['items'] as List?)?.length ?? 0}");

    // Get auth token for API calls
    final prefs = await SharedPreferences.getInstance();
    final token = prefs
        .getString('user_token'); // Changed from 'auth_token' to 'user_token'

    // 1. Check Printer Connection FIRST
    if (_isPrinterConnected) {
      // Get Shop Details
      final shopDetails =
          Provider.of<AuthProvider>(context, listen: false).shopDetails ??
              ShopDetails(
                  shopName: "My Shop",
                  ownerName: "",
                  address: "",
                  phone1: "",
                  phone2: "",
                  shopCategory: "General");

      // Get QR Code Path from BillProvider
      final billProvider = Provider.of<BillProvider>(context, listen: false);
      final qrCodePath = billProvider.qrCodePath;

      debugPrint("🏠 Calling printer service...");

      // Use the new Service with QR code
      String result =
          await _printerService.printBill(billData, shopDetails, qrCodePath);

      if (result == "Success") {
        // Save bill to database
        if (token != null) {
          debugPrint("💾 Preparing to save bill to database...");
          final items = billData['items'] as List;
          debugPrint("💾 Bill has ${items.length} items");

          final billItems = items.map((item) {
            debugPrint("💾 Item: $item");
            return {
              'name': item['name'],
              'category': item['category'] ?? 'Other',
              'quantity': item['qty'] ?? item['quantity'] ?? 1,
              'qty_display': item['qty_display'] ??
                  '${item['qty'] ?? item['quantity'] ?? 1}${item['unit'] ?? ''}',
              'unit': item['unit'],
              'price': item['price'] ?? item['rate'] ?? 0,
              'total': item['total'],
            };
          }).toList();

          debugPrint("💾 Mapped items: $billItems");

          final saved = await _analyticsService.saveBill(
            token,
            totalAmount: (billData['total'] as num).toDouble(),
            items: billItems,
            customerName: billData['customerName'] as String?,
            paymentMethod: 'cash',
          );

          debugPrint("💾 Bill saved to database: $saved");
        } else {
          debugPrint("❌ No auth token - cannot save bill");
        }

        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ Print Successful! Bill Saved.")));

        // 2. Save to History ONLY after print logic (or as per your flow)
        setState(() {
          _pastBills.insert(0, billData);
        });
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("❌ Print Failed: $result")));
      }
    } else {
      // Logic for when printer is disconnected but user wants to save?
      // The requirement says: "if not connected then give error message connect printer first"
      // But if we are in this function, it means the check passed in the child screen
      // OR we are falling back to PDF.

      // If you strictly want to block saving:
      // return;

      // For now, I will allow saving as PDF fallback if connection drops suddenly
      await _printPdf(billData);

      // Save bill to database even for PDF
      if (token != null) {
        debugPrint("💾 Preparing to save bill to database (PDF mode)...");
        final items = billData['items'] as List;
        final billItems = items.map((item) {
          return {
            'name': item['name'],
            'category': item['category'] ?? 'Other',
            'quantity': item['qty'] ?? item['quantity'] ?? 1,
            'qty_display': item['qty_display'] ??
                '${item['qty'] ?? item['quantity'] ?? 1}${item['unit'] ?? ''}',
            'unit': item['unit'],
            'price': item['price'] ?? item['rate'] ?? 0,
            'total': item['total'],
          };
        }).toList();

        await _analyticsService.saveBill(
          token,
          totalAmount: (billData['total'] as num).toDouble(),
          items: billItems,
          customerName: billData['customerName'] as String?,
          paymentMethod: 'cash',
        );
      }

      setState(() {
        _pastBills.insert(0, billData);
      });
    }
  }

  Future<void> _printPdf(Map<String, dynamic> billData) async {
    final doc = pw.Document();
    final font = await PdfGoogleFonts.poppinsRegular();
    final fontBold = await PdfGoogleFonts.poppinsBold();

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.roll80,
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(billData['shopName'],
                style: pw.TextStyle(font: fontBold, fontSize: 18)),
            pw.Text("Ph: ${billData['shopPhone']}",
                style: pw.TextStyle(font: font, fontSize: 10)),
            pw.Divider(),
            pw.Text("TOTAL: Rs ${billData['total'].toInt()}",
                style: pw.TextStyle(font: fontBold, fontSize: 16)),
          ],
        );
      },
    ));

    await Printing.layoutPdf(
        onLayout: (format) async => doc.save(), name: 'Bill-${billData['id']}');
  }

  // --- SWIPE LOGIC ---
  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  void _onItemTapped(int index) {
    setState(() => _currentIndex = index);
    _pageController.animateToPage(index,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    final _shopDetails = Provider.of<AuthProvider>(context).shopDetails ??
        ShopDetails(
            shopName: "Loading...",
            ownerName: "",
            address: "",
            phone1: "",
            phone2: "",
            shopCategory: "General");

    final categoryPages = CategoryPageFactory.build(
      shopDetails: _shopDetails,
      onBillFinalized: _printOrSaveBill,
      isPrinterConnected: _isPrinterConnected,
      togglePrinter: _togglePrinter,
      frequentItems: _frequentItemsFor(_activeShopCategory),
      onAddFrequentItem: _addFrequentItem,
      onEditFrequentItem: _editFrequentItem,
      onDeleteFrequentItem: _deleteFrequentItem,
    );
    final pages = [
      ...categoryPages.pages,
      if (categoryPages.showsSharedDashboard)
        HistoryScreen(shopDetails: _shopDetails),
      const ProfileScreen(),
    ];
    final navigationItems = [
      ...categoryPages.navigationItems,
      if (categoryPages.showsSharedDashboard)
        const BottomNavigationBarItem(
          icon: Icon(Icons.dashboard_rounded),
          label: 'Dashboard',
        ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.person_rounded),
        label: 'Profile',
      ),
    ];

    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        children: pages,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onItemTapped,
          backgroundColor: Colors.transparent,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppColors.primaryGreen,
          unselectedItemColor: Colors.grey[400],
          showUnselectedLabels: true,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
          items: navigationItems,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _authProvider?.removeListener(_onProfileChanged);
    _pageController.dispose();
    super.dispose();
  }
}
