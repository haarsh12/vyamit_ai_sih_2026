import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../models/item.dart';
import '../providers/inventory_provider.dart';
import '../features/gst/providers/gst_provider.dart';
import 'voice_inventory_screen.dart';

class InventoryScreen extends StatefulWidget {
  final String shopCategory;

  const InventoryScreen({
    super.key,
    required this.shopCategory,
  });

  @override
  State<InventoryScreen> createState() =>  _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  
  // Delete mode state
  bool _isDeleteMode = false;
  Set<String> _selectedItemIds = {};
  bool _selectAll = false;

  // List of standard units
  final List<String> _standardUnits = [
    'kg',
    'plate',
    'pis',
    'dozen',
    'litre',
    'pkt',
    'Other'
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() => Provider.of<InventoryProvider>(context, listen: false)
        .loadForShopCategory(widget.shopCategory));
    Future.microtask(() async {
      try {
        await Provider.of<GstProvider>(context, listen: false).loadConfiguration();
      } catch (_) {
        // Inventory remains usable when the configuration endpoint is offline.
      }
    });
  }

  @override
  void didUpdateWidget(covariant InventoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shopCategory != widget.shopCategory) {
      Provider.of<InventoryProvider>(context, listen: false)
          .loadForShopCategory(widget.shopCategory);
    }
  }

  void _showNotification(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textBlack,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(20),
        duration: const Duration(seconds: 2)));
  }
  
  void _toggleDeleteMode() {
    setState(() {
      _isDeleteMode = !_isDeleteMode;
      if (!_isDeleteMode) {
        _selectedItemIds.clear();
        _selectAll = false;
      }

    });
  }
  
  void _toggleSelectAll(List<Item> items) {
    setState(() {
      _selectAll = !_selectAll;
      if (_selectAll) {
        _selectedItemIds = items.map((item) => item.id).toSet();
      } else {
        _selectedItemIds.clear();
      }
    });
  }
  
  void _toggleItemSelection(String itemId) {
    setState(() {
      if (_selectedItemIds.contains(itemId)) {
        _selectedItemIds.remove(itemId);
      } else {
        _selectedItemIds.add(itemId);
      }
    });
  }
  
  void _deleteSelectedItems() {
    if (_selectedItemIds.isEmpty) {
      _showNotification("No items selected");
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Items"),
        content: Text("Are you sure you want to delete ${_selectedItemIds.length} item(s)?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final provider = Provider.of<InventoryProvider>(context, listen: false);
              for (String itemId in _selectedItemIds) {
                await provider.deleteItem(itemId);
              }
              await provider.fetchItems();
              
              if (mounted) {
                Navigator.pop(context);
                _showNotification("${_selectedItemIds.length} item(s) deleted");
                setState(() {
                  _selectedItemIds.clear();
                  _isDeleteMode = false;
                  _selectAll = false;
                });
              }
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
  
  void _showAddCategoryDialog() {
    final categoryNameCtrl = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Add New Category"),
        content: TextField(
          controller: categoryNameCtrl,
          decoration: const InputDecoration(
            labelText: "Category Name *",

            hintText: "e.g., Snacks, Beverages",
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
                final provider = Provider.of<InventoryProvider>(context, listen: false);
                provider.addCategory(categoryNameCtrl.text.trim());
                provider.setCategory(categoryNameCtrl.text.trim());
                Navigator.pop(context);
                _showNotification("Category '${categoryNameCtrl.text.trim()}' added");
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
    final provider = Provider.of<InventoryProvider>(context, listen: false);
    final itemCount = provider.items.where((i) => i.category == categoryName).length;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Category"),
        content: Text(
          itemCount > 0
              ? "Are you sure you want to delete '$categoryName' and all its $itemCount item(s)?"
              : "Are you sure you want to delete '$categoryName'?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await provider.deleteCategory(categoryName);
                if (mounted) {
                  Navigator.pop(context);
                  _showNotification("Category '$categoryName' deleted");
                }
              } catch (e) {
                if (mounted) {
                  Navigator.pop(context);
                  _showNotification("Error deleting category");
                }
              }
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
  void _showItemDialog({Item? item}) {
    final bool isEdit = item != null;
    final gstProvider = Provider.of<GstProvider>(context, listen: false);
    final bool isGstEnabled = gstProvider.isShopGstEnabled;

    // 4 NAME FIELDS
    final name1Ctrl = TextEditingController(

        text: isEdit && item.names.isNotEmpty ? item.names[0] : '');
    final name2Ctrl = TextEditingController(
        text: isEdit && item.names.length > 1 ? item.names[1] : '');
    final name3Ctrl = TextEditingController(
        text: isEdit && item.names.length > 2 ? item.names[2] : '');
    final name4Ctrl = TextEditingController(
        text: isEdit && item.names.length > 3 ? item.names[3] : '');

    final priceCtrl =
        TextEditingController(text: isEdit ? item.price.toString() : '');
    final customUnitCtrl = TextEditingController(text: isEdit ? item.unit : '');
    final customCategoryCtrl = TextEditingController();
    final hsnCodeCtrl = TextEditingController(text: isEdit ? item.hsnCode ?? '' : '');
    final taxCategoryCtrl = TextEditingController(text: isEdit ? item.taxCategory ?? '' : '');
    
    final existingGstRate = isEdit ? item.gstRate : 0.0;
    final existingRateStr = existingGstRate == existingGstRate.toInt() 
        ? existingGstRate.toInt().toString() 
        : existingGstRate.toString();
        
    const standardGstChips = ['0', '5', '12', '18', '28'];
    bool isCustomGst = !standardGstChips.contains(existingRateStr);
    String selectedGstChip = isCustomGst ? 'Other' : existingRateStr;
    final customGstRateCtrl = TextEditingController(text: isCustomGst ? existingRateStr : '');

    String selectedCategory = isEdit
        ? item.category
        : Provider.of<InventoryProvider>(context, listen: false)
            .selectedCategory;
    
    // Get categories from provider
    final providerCategories = Provider.of<InventoryProvider>(context, listen: false).categories;

    // Initial Unit Selection Logic
    String selectedUnit = 'kg';
    bool isCustomUnit = false;
    bool isCustomCategory = false;
    
    // Validation error states
    bool showName1Error = false;
    bool showPriceError = false;
    bool showUnitError = false;
    bool showCategoryError = false;
    
    if (isEdit) {
      if (_standardUnits.contains(item.unit) && item.unit != 'Other') {
        selectedUnit = item.unit;
      } else {
        selectedUnit = 'Other';
        isCustomUnit = true;
        customUnitCtrl.text = item.unit;
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(isEdit ? "Edit Item" : "Add New Item"),
            scrollable: true,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      value: providerCategories.contains(selectedCategory)
                          ? selectedCategory
                          : providerCategories[0],
                      decoration: InputDecoration(
                        labelText: "Category *",
                        errorText: showCategoryError ? "Category required" : null,
                        errorStyle: const TextStyle(color: Colors.red),
                      ),
                      items: [
                        ...providerCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                        const DropdownMenuItem(value: '__NEW_CATEGORY__', child: Text('+ New Category')),
                      ],

                      onChanged: (val) {
                        setDialogState(() {
                          selectedCategory = val!;
                          isCustomCategory = (val == '__NEW_CATEGORY__');
                          showCategoryError = false;
                        });
                      },
                    ),
                    // Show text field ONLY if "Other" is selected
                    if (isCustomCategory)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: TextField(
                          controller: customCategoryCtrl,
                          decoration: InputDecoration(
                            labelText: "New Category Name *",
                            hintText: "e.g., Snacks, Beverages",
                            isDense: true,
                            errorText: showCategoryError ? "Category name required" : null,
                            errorStyle: const TextStyle(color: Colors.red),
                          ),
                          onChanged: (val) {
                            setDialogState(() {
                              showCategoryError = false;
                            });
                          },
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),

                // NAME FIELD 1
                TextField(
                  controller: name1Ctrl,
                  decoration: InputDecoration(
                    labelText: "Name 1 (Primary) *",
                    errorText: showName1Error ? "Name is required" : null,
                    errorStyle: const TextStyle(color: Colors.red),
                  ),
                  onChanged: (val) {
                    setDialogState(() {
                      showName1Error = false;
                    });
                  },
                ),
                const SizedBox(height: 10),

                // PRICE & UNIT PANEL
                Row(children: [
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: priceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: "Price * (must be > 0)",
                        errorText: showPriceError ? "Price must be > 0" : null,
                        errorStyle: const TextStyle(color: Colors.red),
                      ),
                      onChanged: (val) {
                        setDialogState(() {
                          showPriceError = false;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<String>(
                          value: selectedUnit,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: "Unit *",
                            errorText: showUnitError ? "Unit required" : null,
                            errorStyle: const TextStyle(color: Colors.red),

                          ),
                          items: _standardUnits
                              .map((u) =>
                                  DropdownMenuItem(value: u, child: Text(u)))
                              .toList(),
                          onChanged: (val) {
                            setDialogState(() {
                              selectedUnit = val!;
                              isCustomUnit = (val == 'Other');
                              showUnitError = false;
                            });
                          },
                        ),
                        // Show text field ONLY if "Other" is selected
                        if (isCustomUnit)
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: TextField(
                              controller: customUnitCtrl,
                              decoration: InputDecoration(
                                labelText: "Type Unit *",
                                isDense: true,
                                errorText: showUnitError ? "Unit name required" : null,
                                errorStyle: const TextStyle(color: Colors.red),
                              ),
                              onChanged: (val) {
                                setDialogState(() {
                                  showUnitError = false;
                                });
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 15),

                // GST ITEM DETAILS PANEL (With circular GST % selector chips)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isGstEnabled ? AppColors.lightGreenBg : Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isGstEnabled ? AppColors.primaryGreen.withOpacity(0.3) : Colors.grey[300]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isGstEnabled ? 'GST Item Details' : 'Enable GST Billing in Profile to edit tax details',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isGstEnabled ? AppColors.primaryGreen : Colors.grey[700]),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Select GST Percentage (GST %)',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 8),
                      // Circular selection chips
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ...standardGstChips.map((rate) {
                            final isSelected = selectedGstChip == rate;
                            return GestureDetector(
                              onTap: isGstEnabled
                                  ? () => setDialogState(() {
                                        selectedGstChip = rate;
                                        isCustomGst = false;
                                      })
                                  : null,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected ? AppColors.primaryGreen : Colors.white,

                                  border: Border.all(
                                    color: isSelected ? AppColors.primaryGreen : Colors.grey[400]!,
                                    width: isSelected ? 2 : 1,
                                  ),
                                  boxShadow: isSelected
                                      ? [BoxShadow(color: AppColors.primaryGreen.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))]
                                      : null,
                                ),
                                child: Center(
                                  child: Text(
                                    '$rate%',
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : Colors.black87,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                          // 'Other' Circular chip
                          GestureDetector(
                            onTap: isGstEnabled
                                ? () => setDialogState(() {
                                      selectedGstChip = 'Other';
                                      isCustomGst = true;
                                    })
                                : null,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(22),
                                color: selectedGstChip == 'Other' ? AppColors.primaryGreen : Colors.white,
                                border: Border.all(
                                  color: selectedGstChip == 'Other' ? AppColors.primaryGreen : Colors.grey[400]!,
                                  width: selectedGstChip == 'Other' ? 2 : 1,
                                ),
                              ),
                              child: Text(
                                'Other',
                                style: TextStyle(
                                  color: selectedGstChip == 'Other' ? Colors.white : Colors.black87,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      
                      // Custom GST Rate Input field if 'Other' selected
                      if (selectedGstChip == 'Other' && isGstEnabled)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: TextField(
                            controller: customGstRateCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Custom GST Rate (%) *',
                              hintText: 'e.g. 3, 0.25, 9, 14',
                              isDense: true,
                            ),
                          ),
                        ),

                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: hsnCodeCtrl,
                            enabled: isGstEnabled,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'HSN / SAC Code',
                              hintText: 'e.g. 4820 (HSN) / 998314 (SAC)',
                              isDense: true,
                            ),

                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      TextField(
                        controller: taxCategoryCtrl,
                        enabled: isGstEnabled,
                        decoration: const InputDecoration(
                          labelText: 'Tax Category (Optional)',
                          hintText: 'e.g. Goods / Services',
                          isDense: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),

                // EXTRA NAME FIELDS (2, 3, 4) - Optional
                const Text("Other Names / Aliases (Optional)",
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                TextField(
                    controller: name2Ctrl,
                    decoration: const InputDecoration(
                        labelText: "Name 2", isDense: true)),
                const SizedBox(height: 5),
                TextField(
                    controller: name3Ctrl,
                    decoration: const InputDecoration(
                        labelText: "Name 3", isDense: true)),
                const SizedBox(height: 5),
                TextField(
                    controller: name4Ctrl,
                    decoration: const InputDecoration(
                        labelText: "Name 4", isDense: true)),

                // DELETE BUTTON
                if (isEdit) ...[
                  const SizedBox(height: 20),
                  SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                          onPressed: () {
                            Provider.of<InventoryProvider>(context,
                                    listen: false)
                                .deleteItem(item.id);
                            Navigator.pop(context);
                            _showNotification("${name1Ctrl.text} deleted");
                          },
                          icon: const Icon(Icons.delete, color: Colors.red),
                          label: const Text("DELETE ITEM",
                              style: TextStyle(color: Colors.red)),
                          style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.red)))),
                ],
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel")),
              ElevatedButton(
                onPressed: () async {
                  // Validation
                  bool hasError = false;
                  
                  if (name1Ctrl.text.trim().isEmpty) {
                    setDialogState(() => showName1Error = true);
                    hasError = true;
                  }
                  
                  final priceValue = double.tryParse(priceCtrl.text);
                  if (priceCtrl.text.trim().isEmpty || priceValue == null || priceValue <= 0) {
                    setDialogState(() => showPriceError = true);
                    hasError = true;
                    if (priceValue != null && priceValue <= 0) {
                      _showNotification("Price must be greater than 0");
                    }
                  }

                  
                  if (isCustomUnit && customUnitCtrl.text.trim().isEmpty) {
                    setDialogState(() => showUnitError = true);
                    hasError = true;
                  }
                  
                  if (isCustomCategory && customCategoryCtrl.text.trim().isEmpty) {
                    setDialogState(() => showCategoryError = true);
                    hasError = true;
                  }
                  
                  if (hasError) return;

                  // Collect all names
                  List<String> names = [name1Ctrl.text.trim()];
                  if (name2Ctrl.text.trim().isNotEmpty) names.add(name2Ctrl.text.trim());
                  if (name3Ctrl.text.trim().isNotEmpty) names.add(name3Ctrl.text.trim());
                  if (name4Ctrl.text.trim().isNotEmpty) names.add(name4Ctrl.text.trim());

// Determine Unit
                  String finalUnit =
                      isCustomUnit ? customUnitCtrl.text.trim() : selectedUnit;
                  if (finalUnit.isEmpty) finalUnit = 'kg';
                  
                  // Determine Category
                  String finalCategory = selectedCategory;
                  if (isCustomCategory && customCategoryCtrl.text.trim().isNotEmpty) {
                    finalCategory = customCategoryCtrl.text.trim();
                  } else if (isCustomCategory) {
                    // If custom category selected but no name provided, use first available
                    finalCategory = providerCategories.isNotEmpty ? providerCategories[0] : 'Other';
                  }

                  // Determine GST rate from chip selection
                  String gstRateStr;
                  if (selectedGstChip == 'Other') {
                    gstRateStr = customGstRateCtrl.text.trim();
                  } else {
                    gstRateStr = selectedGstChip;
                  }
                  final double gstRate = double.tryParse(gstRateStr) ?? 0.0;

                  final newItem = Item(
                    id: isEdit ? item.id : 'custom_${DateTime.now().millisecondsSinceEpoch}_${names[0].toLowerCase().replaceAll(' ', '_')}',
                    names: names,
                    price: double.tryParse(priceCtrl.text) ?? 0,
                    unit: finalUnit,
                    category: finalCategory,
                    gstRate: isGstEnabled ? gstRate : 0,
                    hsnCode: isGstEnabled && hsnCodeCtrl.text.trim().isNotEmpty
                        ? hsnCodeCtrl.text.trim().toUpperCase()
                        : null,
                    taxCategory: isGstEnabled && taxCategoryCtrl.text.trim().isNotEmpty
                        ? taxCategoryCtrl.text.trim()
                        : null,
                  );

                  // Save the item
                  await Provider.of<InventoryProvider>(context, listen: false)
                      .addItem(newItem);

                  // CRITICAL: Force refresh from backend to ensure UI shows latest data
                  await Provider.of<InventoryProvider>(context, listen: false)
                      .fetchItems();
                  
                  // Switch to the new category if it was just created
                  if (isCustomCategory && customCategoryCtrl.text.trim().isNotEmpty) {
                    Provider.of<InventoryProvider>(context, listen: false)
                        .setCategory(finalCategory);
                  }

                  if (mounted) {
                    Navigator.pop(context);
                    _showNotification("${names[0]} saved");
                  }
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white),
                child: const Text("Save"),

              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<InventoryProvider>(
      builder: (context, provider, child) {
        final filteredItems = provider.getFilteredItems(_searchController.text);
        
        // Use categories from provider
        final displayCategories = provider.categories;
        
        // Ensure selected category exists
        if (!displayCategories.contains(provider.selectedCategory) && displayCategories.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            provider.setCategory(displayCategories.first);
          });
        }

        return Scaffold(
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Inventory",
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryGreen)),
                      Row(
                        children: [
                          if (_isDeleteMode && _selectedItemIds.isNotEmpty)
                            TextButton.icon(
                              onPressed: () => _toggleSelectAll(filteredItems),
                              icon: Icon(
                                _selectAll ? Icons.check_box : Icons.check_box_outline_blank,
                                size: 20,
                              ),
                              label: const Text("Select All"),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.primaryGreen,
                              ),
                            ),
                          IconButton(
                            onPressed: _isDeleteMode && _selectedItemIds.isNotEmpty
                                ? _deleteSelectedItems
                                : _toggleDeleteMode,
                            icon: Icon(
                              _isDeleteMode ? Icons.delete : Icons.delete_outline,
                              color: Colors.red,
                            ),
                            tooltip: _isDeleteMode ? "Delete Selected" : "Delete Mode",
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: "Search items...",
                      prefixIcon: const Icon(Icons.search),
                      fillColor: Colors.white,

                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none),
                      filled: true,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 50,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: displayCategories.length + 1, // +1 for Add button
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      // Add Category button at the end
                      if (index == displayCategories.length) {
                        return ActionChip(
                          label: const Icon(Icons.add, size: 20),
                          onPressed: _showAddCategoryDialog,
                          backgroundColor: Colors.white,
                          side: BorderSide(color: AppColors.primaryGreen.withOpacity(0.5)),
                        );
                      }
                      
                      final cat = displayCategories[index];
                      final isSelected = provider.selectedCategory == cat;
                      return GestureDetector(
                        onLongPress: () => _showDeleteCategoryDialog(cat),
                        child: ChoiceChip(
                          label: Text(cat),
                          selected: isSelected,
                          onSelected: (val) {
                            provider.setCategory(cat);
                            // Reset delete mode when changing category
                            setState(() {
                              _isDeleteMode = false;
                              _selectedItemIds.clear();
                              _selectAll = false;
                            });
                          },
                          selectedColor: AppColors.primaryGreen,
                          labelStyle: TextStyle(
                              color: isSelected ? Colors.white : Colors.black),
                          backgroundColor: Colors.white,
                          showCheckmark: false,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: provider.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : filteredItems.isEmpty
                          ? Center(
                              child: Text(
                                  "No items found in ${provider.selectedCategory}",
                                  style: const TextStyle(color: Colors.grey)))
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: filteredItems.length,
                              itemBuilder: (context, index) {
                                final item = filteredItems[index];
                                final isSelected = _selectedItemIds.contains(item.id);
                                
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  color: isSelected ? AppColors.primaryGreen.withOpacity(0.1) : null,
                                  child: ListTile(
                                    onTap: _isDeleteMode
                                        ? () => _toggleItemSelection(item.id)
                                        : () => _showItemDialog(item: item),
                                    onLongPress: () => _showItemDialog(item: item),
                                    leading: _isDeleteMode
                                        ? Checkbox(
                                            value: isSelected,

                                            onChanged: (val) => _toggleItemSelection(item.id),
                                            activeColor: AppColors.primaryGreen,
                                          )
                                        : CircleAvatar(
                                            backgroundColor: AppColors.lightGreenBg,
                                            child: Text(item.names[0][0],
                                                style: const TextStyle(
                                                    color: AppColors.primaryGreen,
                                                    fontWeight: FontWeight.bold)),
                                          ),
                                    title: Text(item.names[0],
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    // SHOW MULTIPLE NAMES IN SUBTITLE
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (item.names.length > 1)
                                          Text(item.names.sublist(1).join(", "),
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600])),
                                        Text("₹${item.price} / ${item.unit}",
                                            style: const TextStyle(
                                                color: AppColors.primaryGreen,
                                                fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                    trailing: _isDeleteMode
                                        ? null
                                        : IconButton(
                                            icon: const Icon(Icons.edit,
                                                color: Colors.grey),
                                            onPressed: () =>
                                                _showItemDialog(item: item),
                                          ),
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
          floatingActionButton: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Voice Inventory Button
              FloatingActionButton(
                heroTag: 'voice_inventory',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const VoiceInventoryScreen(),
                      fullscreenDialog: true,
                    ),
                  );
                },
                backgroundColor: Colors.blue,
                child: const Icon(Icons.mic, color: Colors.white),
              ),
              const SizedBox(height: 10),
              // Add Item Button
              FloatingActionButton(
                heroTag: 'add_item',
                onPressed: () => _showItemDialog(),
                backgroundColor: AppColors.primaryGreen,
                child: const Icon(Icons.add, color: Colors.white),
              ),
            ],
          ),
        );
      },
    );
  }
}

