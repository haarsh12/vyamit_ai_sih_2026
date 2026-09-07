import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../models/item.dart';
import '../models/shop_details.dart';
import '../providers/bill_provider.dart';
import '../services/printer_service.dart';
import 'bill_share_modal.dart';

// Helper model for the bill calculation
class BillItem {
  final String name;
  final String qtyDisplay;
  final double rate;
  final double total;
  final String unit;

  BillItem({
    required this.name,
    required this.qtyDisplay,
    required this.rate,
    required this.total,
    required this.unit,
  });
}

class FrequentBillingScreen extends StatefulWidget {
  final List<Item> frequentItems;
  final ShopDetails shopDetails;
  final Function(Map<String, dynamic>) onBillFinalized;
  final Function(Item) onAdd;
  final Function(Item) onEdit;
  final Function(String) onDelete;
  final bool isPrinterConnected;
  final VoidCallback togglePrinter;

  const FrequentBillingScreen({
    super.key,
    required this.frequentItems,
    required this.shopDetails,
    required this.onBillFinalized,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.isPrinterConnected,
    required this.togglePrinter,
  });

  @override
  State<FrequentBillingScreen> createState() => _FrequentBillingScreenState();
}

class _FrequentBillingScreenState extends State<FrequentBillingScreen> {
  final List<BillItem> _currentBill = [];
  final Map<String, int> _itemCounts = {};
  
  // Edit Mode State
  bool _isEditMode = false;
  
  // View toggle - true = show bill, false = show items
  bool _showBillView = false;

  // Standard units for the dropdown
  final List<String> _unitOptions = ['kg', 'pics', 'dozen', 'plate', 'other'];
  
  // Category Management. The shortcuts passed by HomeScreen are already
  // isolated by shop category, so derive tabs from those shortcuts instead of
  // showing the previous business type's hard-coded groups.
  late List<String> _categories;
  late String _selectedCategory;

  @override
  void initState() {
    super.initState();
    _categories = _shortcutCategories(widget.frequentItems);
    _selectedCategory = _categories.first;
  }

  static List<String> _shortcutCategories(List<Item> items) {
    final categories = <String>[];
    for (final item in items) {
      final category = item.category.trim();
      if (category.isNotEmpty && !categories.contains(category)) {
        categories.add(category);
      }
    }
    return categories.isEmpty ? ['Items'] : categories;
  }

  void _handleItemTap(Item item) {
    setState(() {
      int currentCount = _itemCounts[item.id] ?? 0;
      int newCount = currentCount + 1;
      _itemCounts[item.id] = newCount;

      int billIndex = _currentBill.indexWhere((b) => b.name == item.names[0]);
      if (billIndex != -1) {
        // Update existing item
        BillItem oldBillItem = _currentBill[billIndex];
        _currentBill[billIndex] = BillItem(
          name: oldBillItem.name,
          qtyDisplay: "$newCount${_getShortUnit(item.unit)}",
          rate: item.price,
          total: item.price * newCount,
          unit: item.unit,
        );
      } else {
        // Add new item
        _currentBill.add(BillItem(
          name: item.names[0],
          qtyDisplay: "1${_getShortUnit(item.unit)}",
          rate: item.price,
          total: item.price,
          unit: item.unit,
        ));
      }
    });
  }

  void _reduceItem(BillItem billItem) {
    setState(() {
      Item? item = widget.frequentItems.firstWhere(
        (i) => i.names[0] == billItem.name,
        orElse: () => Item(id: '', names: [], price: 0, unit: '', category: ''),
      );
      if (item.id.isEmpty) return;

      int currentCount = _itemCounts[item.id] ?? 0;
      if (currentCount > 0) {
        int newCount = currentCount - 1;
        _itemCounts[item.id] = newCount;
        int billIndex = _currentBill.indexOf(billItem);

        if (newCount == 0) {
          _currentBill.removeAt(billIndex);
          _itemCounts.remove(item.id);
        } else {
          _currentBill[billIndex] = BillItem(
            name: billItem.name,
            qtyDisplay: "$newCount${_getShortUnit(item.unit)}",
            rate: item.price,
            total: item.price * newCount,
            unit: item.unit,
          );
        }
      }
    });
  }

  void _resetBill() {
    setState(() {
      _currentBill.clear();
      _itemCounts.clear();
      _showBillView = false;
      if (_isEditMode) {
        _toggleEditMode();
      }
    });
  }

  void _finalizeBill() async {
    // 1. Check Printer Connection in real-time
    final isConnected = await PrinterService().isConnected();
    if (!isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("⚠️ Connect Printer First!",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    if (_currentBill.isEmpty) return;

    // Get next bill number from BillProvider
    final billProvider = Provider.of<BillProvider>(context, listen: false);
    final billNumber = await billProvider.getNextBillNumber();

    final billData = {
      'id': billNumber,
      'date': DateFormat('dd-MM-yyyy').format(DateTime.now()),
      'time': DateFormat('hh:mm:ss a').format(DateTime.now()),
      'total': _currentBill.fold<double>(0, (sum, item) => sum + item.total),
      'shopName': widget.shopDetails.shopName,
      'shopAddress': widget.shopDetails.address,
      'shopPhone': widget.shopDetails.phone1,
      'billing_source': 'frequent',
      'items': _currentBill
          .map((e) => {
                'en': e.name,
                'hi': e.name,
                'name': e.name,
                'qty': e.qtyDisplay.replaceAll(RegExp(r'[a-zA-Z]'), '').trim(),
                'qty_display': e.qtyDisplay,
                'rate': e.rate,
                'total': e.total,
                'unit': e.unit,
              })
          .toList(),
    };

    widget.onBillFinalized(billData);
    _resetBill();
  }
  
  // Show FAB only when items selected and not in bill view
  bool _shouldShowFAB() {
    return !_showBillView && _currentBill.isNotEmpty;
  }

  void _showFrequentItemDialog({Item? item}) {
    final bool isEdit = item != null;

    final idController = TextEditingController(
        text: isEdit ? item.id : 'FB-${DateTime.now().millisecondsSinceEpoch}');
    final nameController = TextEditingController(
        text: isEdit && item.names.isNotEmpty ? item.names[0] : '');
    final priceController =
        TextEditingController(text: isEdit ? item.price.toString() : '');
    String? currentImageUrl = isEdit ? item.imageUrl : null;

    // Unit Logic
    String currentUnitSelection = 'plate'; // Default
    final customUnitController = TextEditingController();

    if (isEdit) {
      if (_unitOptions.contains(item.unit)) {
        currentUnitSelection = item.unit;
      } else {
        currentUnitSelection = 'other';
        customUnitController.text = item.unit;
      }
    }
    
    // Category Logic
    String selectedCategory = isEdit ? item.category : _selectedCategory;
    final customCategoryController = TextEditingController();
    bool isCustomCategory = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(isEdit ? "Edit Item" : "Add Frequent Item"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category Dropdown
                  DropdownButtonFormField<String>(
                    value: _categories.contains(selectedCategory) ? selectedCategory : _categories[0],
                    decoration: const InputDecoration(labelText: "Category"),
                    isExpanded: true,
                    items: [
                      ..._categories.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                      const DropdownMenuItem(value: '__NEW__', child: Text('+ New Category')),
                    ],
                    onChanged: (val) {
                      setDialogState(() {
                        selectedCategory = val!;
                        isCustomCategory = (val == '__NEW__');
                      });
                    },
                  ),
                  if (isCustomCategory) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: customCategoryController,
                      decoration: const InputDecoration(
                        labelText: "New Category Name",
                        hintText: "e.g., Desserts, Drinks",
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: "Item Name"),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: priceController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: "Price"),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 1,
                        child: DropdownButtonFormField<String>(
                          value: currentUnitSelection,
                          decoration: const InputDecoration(labelText: "Unit"),
                          isExpanded: true,
                          items: _unitOptions.map((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            );
                          }).toList(),
                          onChanged: (newValue) {
                            setDialogState(() {
                              currentUnitSelection = newValue!;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  if (currentUnitSelection == 'other') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: customUnitController,
                      decoration: const InputDecoration(
                        labelText: "Type Unit Name manually",
                        hintText: "e.g. bundle, glass",
                      ),
                    ),
                  ],

                  // Item Image Section (Optional Upload / Preview / Delete)
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        // Image Thumbnail Container (Squircle / Cube shape)
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: currentImageUrl != null && currentImageUrl!.isNotEmpty
                                ? _buildDialogImagePreview(currentImageUrl!)
                                : const Center(
                                    child: Icon(Icons.image_outlined, color: Colors.grey, size: 28),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Item Image (Optional)",
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: AppColors.textBlack,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      _pickItemImage((path) {
                                        setDialogState(() {
                                          currentImageUrl = path;
                                        });
                                      });
                                    },
                                    icon: const Icon(Icons.add_a_photo, size: 13),
                                    label: Text(
                                      currentImageUrl == null ? "Upload Image" : "Change",
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primaryGreen,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                  if (currentImageUrl != null && currentImageUrl!.isNotEmpty)
                                    OutlinedButton.icon(
                                      onPressed: () {
                                        setDialogState(() {
                                          currentImageUrl = null;
                                        });
                                      },
                                      icon: const Icon(Icons.delete_outline, size: 13, color: Colors.red),
                                      label: const Text(
                                        "Delete",
                                        style: TextStyle(fontSize: 11, color: Colors.red),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(color: Colors.red),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Delete Button (Only in Edit Mode)
                  if (isEdit) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          widget.onDelete(item.id);
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.delete, color: Colors.red),
                        label: const Text("DELETE ITEM",
                            style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () {
                  if (nameController.text.isNotEmpty &&
                      priceController.text.isNotEmpty) {
                    // Determine final unit string
                    String finalUnit = currentUnitSelection;
                    if (currentUnitSelection == 'other') {
                      finalUnit = customUnitController.text.trim();
                      if (finalUnit.isEmpty) finalUnit = 'unit'; // Fallback
                    }
                    
                    // Determine final category
                    String finalCategory = selectedCategory;
                    if (isCustomCategory && customCategoryController.text.trim().isNotEmpty) {
                      finalCategory = customCategoryController.text.trim();
                      // Add new category to list
                      if (!_categories.contains(finalCategory)) {
                        setState(() {
                          _categories.add(finalCategory);
                          _selectedCategory = finalCategory;
                        });
                      }
                    }

                    final newItem = Item(
                      id: idController.text,
                      names: [nameController.text],
                      price: double.tryParse(priceController.text) ?? 0,
                      unit: finalUnit,
                      category: finalCategory,
                      imageUrl: currentImageUrl,
                    );

                    isEdit ? widget.onEdit(newItem) : widget.onAdd(newItem);
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                ),
                child: const Text("Save"),
              ),
            ],
          );
        },
      ),
    );
  }

  // Helper: Get short unit names
  String _getShortUnit(String unit) {
    final unitMap = {
      'dozen': 'doz',
      'plate': 'plt',
      'pieces': 'pic',
      'pics': 'pic',
      'litre': 'lit',
      'liter': 'lit',
    };
    return unitMap[unit.toLowerCase()] ?? unit;
  }

  // Helper: Format number without .0 for whole numbers
  String _formatNumber(double value) {
    if (value == value.toInt()) {
      return value.toInt().toString();
    }
    return value.toString();
  }
  
  // Helper: Extract numeric quantity from qtyDisplay (e.g., "2kg" -> "2")
  String _extractQuantityNumber(String qtyDisplay) {
    final numericPart = qtyDisplay.replaceAll(RegExp(r'[^0-9.]'), '');
    return numericPart.isEmpty ? '1' : numericPart;
  }
  
  // Helper: Format rate with unit (e.g., rate=30, unit="plt" -> "₹30/plt")
  String _formatRateWithUnit(double rate, String unit) {
    return '₹${_formatNumber(rate)}/${_getShortUnit(unit)}';
  }

  void _toggleEditMode() {
    setState(() {
      _isEditMode = !_isEditMode;
    });
    if (!_isEditMode) {
      // Close keyboard when exiting edit mode
      FocusScope.of(context).unfocus();
    }
  }

  void _addManualItem() {
    setState(() {
      _currentBill.add(BillItem(
        name: 'New Item',
        qtyDisplay: '1kg',
        rate: 0.0,
        total: 0.0,
        unit: 'kg',
      ));
      
      if (!_isEditMode) {
        _isEditMode = true;
      }
    });
  }

  void _updateBillItem(int index, String field, String value) {
    setState(() {
      BillItem oldItem = _currentBill[index];
      
      if (field == 'name') {
        _currentBill[index] = BillItem(
          name: value,
          qtyDisplay: oldItem.qtyDisplay,
          rate: oldItem.rate,
          total: oldItem.total,
          unit: oldItem.unit,
        );
      } else if (field == 'qtyDisplay') {
        // Extract numeric part
        final numericQty = value.replaceAll(RegExp(r'[^0-9.]'), '');
        final qty = double.tryParse(numericQty) ?? 1.0;
        final newTotal = oldItem.rate * qty;
        
        _currentBill[index] = BillItem(
          name: oldItem.name,
          qtyDisplay: value,
          rate: oldItem.rate,
          total: newTotal,
          unit: oldItem.unit,
        );
      } else if (field == 'rate') {
        final newRate = double.tryParse(value) ?? 0.0;
        final qtyStr = oldItem.qtyDisplay.replaceAll(RegExp(r'[^0-9.]'), '');
        final qty = double.tryParse(qtyStr) ?? 1.0;
        final newTotal = newRate * qty;
        
        _currentBill[index] = BillItem(
          name: oldItem.name,
          qtyDisplay: oldItem.qtyDisplay,
          rate: newRate,
          total: newTotal,
          unit: oldItem.unit,
        );
      }
    });
  }

  void _openShareModal() {
    if (_currentBill.isEmpty) return;

    // Convert BillItem to Map format for modal
    final billItemsData = _currentBill.map((item) {
      return {
        'name': item.name,
        'qty_display': item.qtyDisplay,
        'rate': item.rate,
        'total': item.total,
        'unit': item.unit,
      };
    }).toList();

    final totalAmount = _currentBill.fold<double>(0, (sum, item) => sum + item.total);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => BillShareModal(
          billItems: billItemsData,
          totalAmount: totalAmount,
          shopDetails: widget.shopDetails,
          customerName: 'Walk-in',
          billingSource: 'frequent',
        ),
        fullscreenDialog: true,
      ),
    );
  }
  
  void _showAddCategoryDialog() {
    final categoryNameCtrl = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Add New Category"),
        content: TextField(
          controller: categoryNameCtrl,
          decoration: const InputDecoration(
            labelText: "Category Name",
            hintText: "e.g., Desserts, Drinks",
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              if (categoryNameCtrl.text.trim().isNotEmpty) {
                setState(() {
                  _categories.add(categoryNameCtrl.text.trim());
                  _selectedCategory = categoryNameCtrl.text.trim();
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Category '${categoryNameCtrl.text.trim()}' added"),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
            ),
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }
  
  void _showDeleteCategoryDialog(String categoryName) {
    final itemCount = widget.frequentItems.where((i) => i.category == categoryName).length;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Category"),
        content: Text(
          itemCount > 0
              ? "Are you sure you want to delete '$categoryName'? This will remove $itemCount item(s)."
              : "Are you sure you want to delete '$categoryName'?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              // Delete all items in this category
              final itemsToDelete = widget.frequentItems
                  .where((i) => i.category == categoryName)
                  .toList();
              
              for (var item in itemsToDelete) {
                widget.onDelete(item.id);
              }
              
              setState(() {
                _categories.remove(categoryName);
                if (_selectedCategory == categoryName && _categories.isNotEmpty) {
                  _selectedCategory = _categories.first;
                }
              });
              
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Category '$categoryName' deleted"),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }
  
  List<Item> _getFilteredItems() {
    return widget.frequentItems
        .where((item) => item.category == _selectedCategory)
        .toList();
  }

  void _reduceItemFor(Item item) {
    BillItem? billItem;
    final itemName = item.names.isNotEmpty ? item.names[0] : '';
    for (var b in _currentBill) {
      if (b.name == itemName) {
        billItem = b;
        break;
      }
    }
    if (billItem != null) {
      _reduceItem(billItem);
    }
  }

  Future<void> _pickItemImage(Function(String?) onImagePicked) async {
    final picker = ImagePicker();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: AppColors.primaryGreen),
              title: const Text("Choose from Gallery"),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  final XFile? file = await picker.pickImage(
                    source: ImageSource.gallery,
                    maxWidth: 800,
                    maxHeight: 800,
                    imageQuality: 85,
                  );
                  if (file != null) {
                    onImagePicked(file.path);
                  }
                } catch (e) {
                  debugPrint("Image picker error: $e");
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: AppColors.primaryGreen),
              title: const Text("Take a Photo"),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  final XFile? file = await picker.pickImage(
                    source: ImageSource.camera,
                    maxWidth: 800,
                    maxHeight: 800,
                    imageQuality: 85,
                  );
                  if (file != null) {
                    onImagePicked(file.path);
                  }
                } catch (e) {
                  debugPrint("Camera picker error: $e");
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogImagePreview(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey));
    } else if (url.startsWith('assets/')) {
      return Image.asset(url, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey));
    } else {
      final file = File(url);
      if (file.existsSync()) {
        return Image.file(file, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey));
      }
    }
    return const Icon(Icons.image_not_supported_outlined, color: Colors.grey);
  }

  Widget _buildItemImage(Item item) {
    final url = item.imageUrl;
    if (url != null && url.isNotEmpty) {
      if (url.startsWith('http://') || url.startsWith('https://')) {
        return Image.network(
          url,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (context, error, stackTrace) => _buildDefaultImagePlaceholder(item),
        );
      } else if (url.startsWith('assets/')) {
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset(
            url,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (context, error, stackTrace) => _buildDefaultImagePlaceholder(item),
          ),
        );
      } else {
        final file = File(url);
        if (file.existsSync()) {
          return Image.file(
            file,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (context, error, stackTrace) => _buildDefaultImagePlaceholder(item),
          );
        }
      }
    }
    return _buildDefaultImagePlaceholder(item);
  }

  Widget _buildDefaultImagePlaceholder(Item item) {
    IconData iconData = Icons.fastfood_rounded;
    Color iconColor = const Color(0xFF6366F1);
    Color bgColor = const Color(0xFFEEF2FF);

    final catLower = item.category.toLowerCase();
    final nameLower = item.names.isNotEmpty ? item.names[0].toLowerCase() : '';

    if (catLower.contains('pizza') || nameLower.contains('pizza')) {
      iconData = Icons.local_pizza_rounded;
      iconColor = const Color(0xFFE11D48);
      bgColor = const Color(0xFFFFE4E6);
    } else if (catLower.contains('burger') || nameLower.contains('burger')) {
      iconData = Icons.lunch_dining_rounded;
      iconColor = const Color(0xFFD97706);
      bgColor = const Color(0xFFFEF3C7);
    } else if (catLower.contains('beverage') || nameLower.contains('tea') || nameLower.contains('coffee') || nameLower.contains('drink')) {
      iconData = Icons.local_cafe_rounded;
      iconColor = const Color(0xFF7C3AED);
      bgColor = const Color(0xFFF3E8FF);
    } else if (catLower.contains('ice cream') || nameLower.contains('ice cream') || nameLower.contains('kulfi')) {
      iconData = Icons.icecream_rounded;
      iconColor = const Color(0xFFEC4899);
      bgColor = const Color(0xFFFCE7F3);
    } else if (catLower.contains('cake') || catLower.contains('bakery')) {
      iconData = Icons.cake_rounded;
      iconColor = const Color(0xFFDB2777);
      bgColor = const Color(0xFFFCE7F3);
    } else if (catLower.contains('milk') || catLower.contains('dairy')) {
      iconData = Icons.egg_alt_rounded;
      iconColor = const Color(0xFF0288D1);
      bgColor = const Color(0xFFE1F5FE);
    } else if (catLower.contains('kirana') || catLower.contains('grocery') || catLower.contains('anaaj')) {
      iconData = Icons.shopping_basket_rounded;
      iconColor = const Color(0xFF16A34A);
      bgColor = const Color(0xFFDCFCE7);
    }

    return Container(
      color: bgColor,
      child: Center(
        child: Icon(
          iconData,
          size: 40,
          color: iconColor.withOpacity(0.85),
        ),
      ),
    );
  }
  
  // Build items selection view (full screen, 2 per row)
  Widget _buildItemsView() {
    return Column(
      children: [
        // Category Bar
        Container(
          height: 85,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _categories.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              if (index == _categories.length) {
                return GestureDetector(
                  onTap: _showAddCategoryDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.primaryGreen.withOpacity(0.5)),
                    ),
                    child: const Center(
                      child: Icon(Icons.add, size: 30, color: AppColors.primaryGreen),
                    ),
                  ),
                );
              }
              
              final cat = _categories[index];
              final isSelected = _selectedCategory == cat;
              final itemCount = widget.frequentItems.where((i) => i.category == cat).length;
              
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedCategory = cat;
                  });
                },
                onLongPress: () => _showDeleteCategoryDialog(cat),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primaryGreen : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? AppColors.primaryGreen : Colors.grey.shade300,
                      width: 2,
                    ),
                    boxShadow: isSelected ? [
                      BoxShadow(
                        color: AppColors.primaryGreen.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ] : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        cat,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '$itemCount items',
                        style: TextStyle(
                          color: isSelected ? Colors.white.withOpacity(0.9) : Colors.grey,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        
        const SizedBox(height: 10),
        
        // Items Grid (2 per row, tall rectangular cards with images, vertical scroll)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              padding: const EdgeInsets.only(bottom: 100),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.76, // Taller rectangular card layout
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: _getFilteredItems().length,
              itemBuilder: (context, index) {
                final item = _getFilteredItems()[index];
                final count = _itemCounts[item.id] ?? 0;
                final isSelected = count > 0;

                return GestureDetector(
                  onTap: () => _handleItemTap(item),
                  onLongPress: () => _showFrequentItemDialog(item: item),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFF0FDF4) : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primaryGreen
                            : const Color(0xFFE2E8F0),
                        width: isSelected ? 2 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isSelected
                              ? AppColors.primaryGreen.withOpacity(0.18)
                              : Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Curved Square / Rectangular Image Box (Top Portion)
                        Expanded(
                          flex: 6,
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: const Color(0xFFF8FAFC),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: _buildItemImage(item),
                                  ),
                                  if (isSelected)
                                    Positioned(
                                      top: 6,
                                      right: 6,
                                      child: Container(
                                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.primaryGreen,
                                          borderRadius: BorderRadius.circular(12),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.2),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Center(
                                          child: Text(
                                            '$count',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Item Name Below Image
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                          child: Text(
                            item.names.isNotEmpty ? item.names[0] : '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textBlack,
                            ),
                          ),
                        ),

                        const SizedBox(height: 2),

                        // Price & Action Button (Plus when not selected, Red Minus when selected)
                        Padding(
                          padding: const EdgeInsets.only(left: 12, right: 8, bottom: 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  "₹${_formatNumber(item.price)}",
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textBlack,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),

                              if (!isSelected)
                                GestureDetector(
                                  onTap: () => _handleItemTap(item),
                                  child: Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF6366F1),
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF6366F1).withOpacity(0.3),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        )
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.add,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                )
                              else
                                GestureDetector(
                                  onTap: () => _reduceItemFor(item),
                                  child: Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEF4444), // Red minus button when selected
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFFEF4444).withOpacity(0.3),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        )
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.remove,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
  
  // Build checkout FAB with clear button
  Widget _buildCheckoutFAB() {
    final itemCount = _currentBill.length;
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Clear button above
        FloatingActionButton(
          mini: true,
          onPressed: () {
            setState(() {
              _currentBill.clear();
              _itemCounts.clear();
            });
          },
          backgroundColor: Colors.red,
          child: const Icon(Icons.close, color: Colors.white, size: 20),
        ),
        const SizedBox(height: 12),
        // Review button
        FloatingActionButton.extended(
          onPressed: () {
            setState(() {
              _showBillView = true;
            });
          },
          backgroundColor: AppColors.primaryGreen,
          icon: const Icon(Icons.shopping_cart_checkout, color: Colors.white),
          label: Text(
            'Review ($itemCount)',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          elevation: 6,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text("Frequent Billing"),
        leading: _showBillView 
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                setState(() {
                  _showBillView = false;
                });
              },
            )
          : null,
        actions: [
          if (!_showBillView) ...[
            IconButton(
              icon: Icon(Icons.print,
                  color: widget.isPrinterConnected
                      ? AppColors.printerConnected
                      : AppColors.printerDisconnected),
              onPressed: widget.togglePrinter,
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => _showFrequentItemDialog(),
            ),
          ] else ...[
            IconButton(
              icon: Icon(_isEditMode ? Icons.close : Icons.edit),
              onPressed: () {
                if (_currentBill.isEmpty) {
                  _addManualItem();
                } else {
                  _toggleEditMode();
                }
              },
            ),
          ],
        ],
      ),
      body: _showBillView ? _buildBillView() : _buildItemsView(),
      floatingActionButton: _shouldShowFAB() ? _buildCheckoutFAB() : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
  
  // Build bill review view (full screen)
  Widget _buildBillView() {
    return Column(
      children: [
        // Bill items list
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, -5),
                )
              ],
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 15, 20, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Live Bill",
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      TextButton.icon(
                        onPressed: _currentBill.isEmpty ? null : _resetBill,
                        icon: const Icon(Icons.cancel_outlined,
                            size: 18, color: Colors.red),
                        label: const Text("Cancel Bill",
                            style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
                
                // Column Headers
                const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                    child: Row(children: [
                      Expanded(
                          flex: 4,
                          child: Text("Item",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.grey))),
                      Expanded(
                          flex: 1,
                          child: Text("Qty",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.grey))),
                      Expanded(
                          flex: 3,
                          child: Text("Rate",
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.grey))),
                      Expanded(
                          flex: 2,
                          child: Text("Total",
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.grey))),
                    ])),
                const Divider(height: 1),
                Expanded(
                  child: _currentBill.isEmpty
                      ? const Center(
                          child: Text("Tap + to add items manually\nor go back to select items",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey)))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          itemCount: _currentBill.length + (_isEditMode ? 1 : 0),
                          separatorBuilder: (_, __) =>
                              const Divider(height: 16),
                          itemBuilder: (context, index) {
                            if (_isEditMode && index == _currentBill.length) {
                              return GestureDetector(
                                onTap: _addManualItem,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryGreen.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: AppColors.primaryGreen.withOpacity(0.3),
                                      style: BorderStyle.solid,
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.add, color: AppColors.primaryGreen, size: 20),
                                      SizedBox(width: 8),
                                      Text(
                                        "Add Item",
                                        style: TextStyle(
                                          color: AppColors.primaryGreen,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }
                            
                            final item = _currentBill[index];
                            
                            if (_isEditMode) {
                              // Editable bill item
                              return Row(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _currentBill.removeAt(index);
                                      });
                                    },
                                    child: Container(
                                      margin: const EdgeInsets.only(right: 8),
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                          color: Colors.red[50],
                                          shape: BoxShape.circle),
                                      child: const Icon(Icons.remove,
                                          size: 16, color: Colors.red),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 4,
                                    child: TextFormField(
                                      initialValue: item.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (value) => _updateBillItem(index, 'name', value),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    flex: 1,
                                    child: TextFormField(
                                      initialValue: _extractQuantityNumber(item.qtyDisplay),
                                      textAlign: TextAlign.center,
                                      keyboardType: TextInputType.number,
                                      style: const TextStyle(fontSize: 13),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (value) {
                                        final newQtyDisplay = '$value${_getShortUnit(item.unit)}';
                                        _updateBillItem(index, 'qtyDisplay', newQtyDisplay);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    flex: 3,
                                    child: TextFormField(
                                      initialValue: _formatNumber(item.rate),
                                      textAlign: TextAlign.right,
                                      keyboardType: TextInputType.number,
                                      style: const TextStyle(fontSize: 11),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                        border: const OutlineInputBorder(),
                                        prefixText: '₹',
                                        suffixText: '/${_getShortUnit(item.unit)}',
                                      ),
                                      onChanged: (value) => _updateBillItem(index, 'rate', value),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    flex: 2,
                                    child: Text("₹${_formatNumber(item.total)}",
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14)),
                                  ),
                                ],
                              );
                            } else {
                              // Display-only bill item
                              return Row(
                                children: [
                                  GestureDetector(
                                    onTap: () => _reduceItem(item),
                                    child: Container(
                                      margin: const EdgeInsets.only(right: 8),
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                          color: Colors.red[50],
                                          shape: BoxShape.circle),
                                      child: const Icon(Icons.remove,
                                          size: 16, color: Colors.red),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 4,
                                    child: Text(item.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14)),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Text(_extractQuantityNumber(item.qtyDisplay),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 13)),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text(_formatRateWithUnit(item.rate, item.unit),
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(fontSize: 12)),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text("₹${_formatNumber(item.total)}",
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14)),
                                  ),
                                ],
                              );
                            }
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        
        // Add more items button
        if (!_isEditMode && _currentBill.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _showBillView = false;
                });
              },
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text("Add More Items"),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                side: BorderSide(color: AppColors.primaryGreen),
                foregroundColor: AppColors.primaryGreen,
              ),
            ),
          ),
        
        // Bill Footer
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, -5),
              )
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "TOTAL",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  Text(
                    "₹${_formatNumber(_currentBill.fold<double>(0, (sum, item) => sum + item.total))}",
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textBlack,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Transform.rotate(
                    angle: -0.5,
                    child: IconButton(
                      onPressed: _currentBill.isEmpty ? null : _openShareModal,
                      icon: Icon(
                        Icons.send,
                        color: _currentBill.isEmpty ? Colors.grey : AppColors.primaryGreen,
                        size: 28,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: _currentBill.isEmpty 
                            ? Colors.grey[200] 
                            : AppColors.primaryGreen.withOpacity(0.1),
                        padding: const EdgeInsets.all(12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _finalizeBill,
                      icon: const Icon(Icons.print, color: Colors.white, size: 20),
                      label: const Text(
                        "PRINT & SAVE",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.textBlack,
                        minimumSize: const Size(0, 56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
