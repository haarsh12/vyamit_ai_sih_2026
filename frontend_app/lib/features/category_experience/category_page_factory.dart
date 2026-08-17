import 'package:flutter/material.dart';

import '../../models/item.dart';
import '../../models/shop_details.dart';
import '../../screens/frequent_billing_screen.dart';
import '../../screens/inventory_screen.dart';
import '../../screens/voice_assistant_screen.dart';
import '../doctor_prescription/doctor_patient_list_screen.dart';
import '../doctor_prescription/doctor_prescription_history_screen.dart';
import '../doctor_prescription/doctor_voice_screen.dart';
import 'category_experience.dart';

class CategoryPageBundle {
  final List<Widget> pages;
  final List<BottomNavigationBarItem> navigationItems;
  final bool showsSharedDashboard;

  const CategoryPageBundle({
    required this.pages,
    required this.navigationItems,
    required this.showsSharedDashboard,
  });
}

/// Builds the business-specific part of the application shell from the
/// category policy. Shared Dashboard and Profile pages remain owned by
/// HomeScreen, so they cannot diverge between retail categories.
class CategoryPageFactory {
  static CategoryPageBundle build({
    required ShopDetails shopDetails,
    required void Function(Map<String, dynamic>) onBillFinalized,
    required bool isPrinterConnected,
    required VoidCallback togglePrinter,
    required List<Item> frequentItems,
    required void Function(Item) onAddFrequentItem,
    required void Function(Item) onEditFrequentItem,
    required void Function(String) onDeleteFrequentItem,
  }) {
    final experience = CategoryExperience.forCategory(shopDetails.shopCategory);
    final pages = <Widget>[];
    final navigationItems = <BottomNavigationBarItem>[];

    for (final definition in experience.pages) {
      pages.add(
        _buildPage(
          definition: definition,
          experience: experience,
          shopDetails: shopDetails,
          onBillFinalized: onBillFinalized,
          isPrinterConnected: isPrinterConnected,
          togglePrinter: togglePrinter,
          frequentItems: frequentItems,
          onAddFrequentItem: onAddFrequentItem,
          onEditFrequentItem: onEditFrequentItem,
          onDeleteFrequentItem: onDeleteFrequentItem,
        ),
      );
      navigationItems.add(
        BottomNavigationBarItem(
            icon: Icon(definition.icon), label: definition.label),
      );
    }

    return CategoryPageBundle(
      pages: pages,
      navigationItems: navigationItems,
      showsSharedDashboard: experience.showsSharedDashboard,
    );
  }

  static Widget _buildPage({
    required CategoryPageDefinition definition,
    required CategoryExperience experience,
    required ShopDetails shopDetails,
    required void Function(Map<String, dynamic>) onBillFinalized,
    required bool isPrinterConnected,
    required VoidCallback togglePrinter,
    required List<Item> frequentItems,
    required void Function(Item) onAddFrequentItem,
    required void Function(Item) onEditFrequentItem,
    required void Function(String) onDeleteFrequentItem,
  }) {
    switch (definition.type) {
      case CategoryPageType.voice:
        if (experience.category == 'Doctor Prescription') {
          return DoctorVoiceScreen(
            key: const ValueKey('doctor-prescription-voice'),
            shopDetails: shopDetails,
            isPrinterConnected: isPrinterConnected,
            togglePrinter: togglePrinter,
          );
        }
        // Retail categories keep the shared inventory-aware billing surface.
        return VoiceAssistantScreen(
          key: ValueKey('voice-${experience.category}'),
          shopDetails: shopDetails,
          onBillFinalized: onBillFinalized,
          isPrinterConnected: isPrinterConnected,
          togglePrinter: togglePrinter,
        );
      case CategoryPageType.inventory:
        return InventoryScreen(
          key: ValueKey('inventory-${experience.category}'),
          shopCategory: experience.category,
        );
      case CategoryPageType.frequentBilling:
        return FrequentBillingScreen(
          // A category key discards the previous category's in-progress bill,
          // selected shortcuts, and edit state on a profile switch.
          key: ValueKey('frequent-${experience.category}'),
          shopDetails: shopDetails,
          frequentItems: frequentItems,
          onBillFinalized: onBillFinalized,
          isPrinterConnected: isPrinterConnected,
          togglePrinter: togglePrinter,
          onAdd: onAddFrequentItem,
          onEdit: onEditFrequentItem,
          onDelete: onDeleteFrequentItem,
        );
      case CategoryPageType.patientHistory:
        return const DoctorPatientListScreen();
      case CategoryPageType.pastRecords:
        return const DoctorPrescriptionHistoryScreen();
    }
  }
}
