import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:image/image.dart' as img; // v4 Library

import '../models/shop_details.dart';

class PrinterService {
  final BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;

  // Helper: Format quantity display with smart kg/gm conversion
  String _formatQuantityForPrint(String qtyDisplay, String unit) {
    // First apply short unit names
    String result = _shortenQtyDisplay(qtyDisplay);

    // Smart kg/gm conversion
    // Extract number from string like "0.4" or "1.2"
    final numMatch = RegExp(r'(\d+\.?\d*)').firstMatch(qtyDisplay);

    if (numMatch != null && unit.toLowerCase() == 'kg') {
      double value = double.tryParse(numMatch.group(1) ?? '0') ?? 0;

      // If < 1kg, convert to grams
      if (value > 0 && value < 1) {
        int grams = (value * 1000).round();
        return '${grams}gm';
      }
      // If > 1kg but has decimal, convert fully to grams
      else if (value > 1 && value != value.toInt()) {
        int grams = (value * 1000).round();
        return '${grams}gm';
      }
      // If whole kg, keep as is
      else if (value == value.toInt()) {
        return '${value.toInt()}kg';
      }
    }

    // Convert large grams to kg (e.g., 2000gm -> 2kg)
    if (unit.toLowerCase() == 'gm' || unit.toLowerCase() == 'gram') {
      final numMatch2 = RegExp(r'(\d+)').firstMatch(qtyDisplay);
      if (numMatch2 != null) {
        int gmValue = int.tryParse(numMatch2.group(1) ?? '0') ?? 0;
        if (gmValue >= 1000 && gmValue % 1000 == 0) {
          int kgValue = gmValue ~/ 1000;
          return '${kgValue}kg';
        }
      }
    }

    return result;
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

  // Helper: Shorten quantity display that already contains units
  String _shortenQtyDisplay(String qtyDisplay) {
    String result = qtyDisplay;
    result = result.replaceAll('dozen', 'doz');
    result = result.replaceAll('plate', 'plt');
    result = result.replaceAll('pieces', 'pic');
    result = result.replaceAll('pics', 'pic');
    result = result.replaceAll('litre', 'lit');
    result = result.replaceAll('liter', 'lit');
    return result;
  }

  Future<bool> isConnected() async {
    return (await bluetooth.isConnected) ?? false;
  }

  Future<String> printBill(Map<String, dynamic> billData,
      ShopDetails shopDetails, String? qrCodePath) async {
    if (!await isConnected()) {
      return "Printer not connected";
    }

    // DEBUG: Log received data
    if (kDebugMode) {
      print("🖨️ PRINTER SERVICE: Received bill data");
      print("🖨️ Bill ID: ${billData['id']}");
      print("🖨️ Items count: ${billData['items']?.length ?? 0}");
      print("🖨️ Items data: ${billData['items']}");
    }

    try {
      // 1. Setup PDF Document
      final doc = pw.Document();
      // 80mm width creates a high-res master that we scale down to 58mm later
      // This ensures text is crisp and not pixelated
      const pageFormat = PdfPageFormat(80 * PdfPageFormat.mm, double.infinity,
          marginAll: 2 * PdfPageFormat.mm);

      doc.addPage(pw.Page(
        pageFormat: pageFormat,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              // --- 1. BRANDING & HEADER ---
              pw.Center(
                  child: pw.Text("VYAMIT AI",
                      style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey700))),
              pw.SizedBox(height: 2),

              pw.Center(
                  child: pw.Text(
                      (shopDetails.shopName.isNotEmpty
                              ? shopDetails.shopName
                              : "MY SHOP")
                          .toUpperCase(),
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 22))),

              // Address & Phone
              pw.Center(
                  child: pw.Text(
                      shopDetails.address.isNotEmpty
                          ? shopDetails.address
                          : "Shop Address Here",
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(fontSize: 12))),
              pw.Center(
                  child: pw.Text(
                      "Mob: ${shopDetails.phone1.isNotEmpty ? shopDetails.phone1 : '-'}",
                      style: const pw.TextStyle(fontSize: 12))),
              // Second phone number (only if exists)
              if (shopDetails.phone2.isNotEmpty)
                pw.Center(
                    child: pw.Text("Mob: ${shopDetails.phone2}",
                        style: const pw.TextStyle(fontSize: 12))),
              pw.Divider(thickness: 1),

              // --- 2. BILL META DATA ---
              pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("Bill No: ${billData['id']?.toString() ?? '001'}",
                        style: const pw.TextStyle(fontSize: 12)),
                    pw.Text("Date: ${billData['date'] ?? '-'}",
                        style: const pw.TextStyle(fontSize: 12)),
                  ]),
              pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("Cst: ${billData['customerName'] ?? 'Walk-in'}",
                        style: const pw.TextStyle(fontSize: 12)),
                    pw.Text("Time: ${billData['time'] ?? '-'}",
                        style: const pw.TextStyle(fontSize: 12)),
                  ]),
              if (billData['payment_method']?.toString().toLowerCase() == 'udhaar')
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 2),
                  child: pw.Center(
                    child: pw.Text(
                      'PAYMENT: UDHAAR',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.orange,
                      ),
                    ),
                  ),
                ),
              pw.Divider(thickness: 1),

              // --- 3. TABLE HEADERS (4 Columns) ---
              pw.Row(children: [
                pw.Expanded(
                    flex: 3,
                    child: pw.Text("Item",
                        style: const pw.TextStyle(fontSize: 12))),
                pw.Expanded(
                    flex: 2,
                    child: pw.Text("Qty",
                        textAlign: pw.TextAlign.center,
                        style: const pw.TextStyle(fontSize: 12))),
                pw.Expanded(
                    flex: 2,
                    child: pw.Text("Rate",
                        textAlign: pw.TextAlign.right,
                        style: const pw.TextStyle(fontSize: 12))),
                pw.Expanded(
                    flex: 2,
                    child: pw.Text("Price",
                        textAlign: pw.TextAlign.right,
                        style: const pw.TextStyle(fontSize: 12))),
              ]),
              pw.Divider(),

              // --- 4. ITEMS LIST (Smart Name Logic) ---
              ...billData['items'].map<pw.Widget>((item) {
                if (kDebugMode) {
                  print("🖨️ Processing item for print: $item");
                }

                // SMART NAME RESOLVER: Checks all possible keys so it never prints "Item"
                String itemName = "Item";
                if (item['name'] != null) {
                  itemName = item['name'];
                } else if (item['en'] != null) {
                  itemName = item['en'];
                } else if (item['names'] != null &&
                    item['names'] is List &&
                    (item['names'] as List).isNotEmpty) {
                  itemName = item['names'][0];
                }

                if (kDebugMode) {
                  print("🖨️ Item name resolved: $itemName");
                }

                // Extract quantity display - PRIORITIZE qty_display over qty
                String qtyDisplay = item['qty_display']?.toString() ??
                    item['qty']?.toString() ??
                    "1kg";
                String unit = item['unit']?.toString() ?? 'kg';

                if (kDebugMode) {
                  print("🖨️ Raw qty_display: ${item['qty_display']}");
                  print("🖨️ Raw qty: ${item['qty']}");
                  print("🖨️ Using qtyDisplay: $qtyDisplay, Unit: $unit");
                }

                // Short unit names for printing
                String shortUnit = _getShortUnit(unit);

                // Format quantity with smart kg/gm conversion
                String formattedQty = _formatQuantityForPrint(qtyDisplay, unit);

                // Get rate and remove decimals if whole number
                double rateValue =
                    (item['rate'] ?? item['price'] ?? 0).toDouble();
                String rateStr = _formatNumber(rateValue);
                String rateWithUnit = "$rateStr/$shortUnit";

                // Get total and remove decimals if whole number
                double totalValue = (item['total'] ?? 0).toDouble();
                String totalStr = "Rs${_formatNumber(totalValue)}";

                if (kDebugMode) {
                  print(
                      "🖨️ Printing: $itemName | $formattedQty | $rateWithUnit | $totalStr");
                }

                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 3),
                  child: pw.Row(children: [
                    // Item Name
                    pw.Expanded(
                        flex: 3,
                        child: pw.Text(itemName,
                            style: const pw.TextStyle(fontSize: 13))),
                    // Qty
                    pw.Expanded(
                        flex: 2,
                        child: pw.Text(formattedQty,
                            textAlign: pw.TextAlign.center,
                            style: const pw.TextStyle(fontSize: 13))),
                    // Rate (without Rs)
                    pw.Expanded(
                        flex: 2,
                        child: pw.Text(rateWithUnit,
                            textAlign: pw.TextAlign.right,
                            style: const pw.TextStyle(fontSize: 13))),
                    // Price (with Rs)
                    pw.Expanded(
                        flex: 2,
                        child: pw.Text(totalStr,
                            textAlign: pw.TextAlign.right,
                            style: const pw.TextStyle(fontSize: 13))),
                  ]),
                );
              }).toList(),

              pw.Divider(thickness: 1),

              // --- 5. TOTAL SECTION ---
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text("Total Amount:  ",
                      style: const pw.TextStyle(fontSize: 14)),
                  pw.Text(
                      "Rs${_formatNumber((billData['total'] ?? 0).toDouble())}",
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 18)),
                ],
              ),
              pw.SizedBox(height: 10),

              // --- 6. FOOTER ---
              pw.Center(
                  child: pw.Text("Thank You! Visit Again",
                      style: const pw.TextStyle(fontSize: 14))),
              pw.SizedBox(height: 5),

              // QR Code (if exists)
              if (qrCodePath != null && qrCodePath.isNotEmpty)
                pw.Column(children: [
                  pw.SizedBox(height: 10),
                  pw.Center(
                    child: pw.Container(
                      width: 150,
                      height: 150,
                      child: pw.Image(
                        pw.MemoryImage(
                          File(qrCodePath).readAsBytesSync(),
                        ),
                        fit: pw.BoxFit.contain,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 5),
                  pw.Center(
                    child: pw.Text("Scan to Pay",
                        style: const pw.TextStyle(fontSize: 10)),
                  ),
                  pw.SizedBox(height: 10),
                ]),

              pw.Center(
                  child: pw.Text("Powered by Vyamit AI",
                      style: const pw.TextStyle(
                          fontSize: 10, color: PdfColors.grey600))),
              pw.SizedBox(height: 20),
            ],
          );
        },
      ));

      // 3. Rasterize (Convert PDF to Image)
      await for (final page
          in Printing.raster(await doc.save(), pages: [0], dpi: 203)) {
        final Uint8List imageBytes = await page.toPng();
        final img.Image? originalImage = img.decodeImage(imageBytes);

        if (originalImage != null) {
          // A. Resize to 384px (Standard Thermal Width)
          final img.Image resizedImage =
              img.copyResize(originalImage, width: 384);

          // B. Initialize Printer
          await bluetooth.writeBytes(Uint8List.fromList([0x1b, 0x40]));
          await Future.delayed(const Duration(milliseconds: 100));

          // C. Send Image (Using the Fixed Transparent/Black Logic)
          final List<int> printBytes = _generateRasterData(resizedImage);
          await bluetooth.writeBytes(Uint8List.fromList(printBytes));

          // D. Feed & Cut
          await Future.delayed(const Duration(milliseconds: 100));
          await bluetooth.writeBytes(Uint8List.fromList([0x0a, 0x0a, 0x0a]));
        }
        break;
      }
      return "Success";
    } catch (e) {
      return "Print Error: $e";
    }
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

  /// Prints a finalized server-calculated GST invoice using the same Bluetooth
  /// connection and raster flow as normal billing.
  Future<String> printGstInvoice(
    Map<String, dynamic> invoice,
    ShopDetails shopDetails,
    String? qrCodePath,
  ) async {
    if (!await isConnected()) {
      return "Printer not connected";
    }

    try {
      // Add validation with better error messages
      if (invoice.isEmpty) {
        return "Print Error: Invoice data is empty";
      }
      
      final seller =
          Map<String, dynamic>.from(invoice['seller'] as Map? ?? const {});
      final customer =
          Map<String, dynamic>.from(invoice['customer'] as Map? ?? const {});
      final totals =
          Map<String, dynamic>.from(invoice['totals'] as Map? ?? const {});
      final placeOfSupply = Map<String, dynamic>.from(
          invoice['place_of_supply'] as Map? ?? const {});
      final bankDetails = Map<String, dynamic>.from(
          invoice['bank_details'] as Map? ?? const {});
      final hasBankDetails = [
        bankDetails['bank_name'] ?? seller['bank_name'],
        bankDetails['account_name'] ?? seller['account_name'],
        bankDetails['account_number'] ?? seller['account_number'],
        bankDetails['ifsc'] ?? seller['ifsc'],
      ].any((value) => value?.toString().trim().isNotEmpty == true);
      final items = (invoice['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      // Validate required fields
      if (items.isEmpty) {
        return "Print Error: No items in invoice";
      }
      if (seller.isEmpty) {
        return "Print Error: Seller information missing";
      }

      final doc = pw.Document();
      const pageFormat = PdfPageFormat(
        80 * PdfPageFormat.mm,
        double.infinity,
        marginAll: 2 * PdfPageFormat.mm,
      );

      final grandTotalPaise = totals['grand_total_paise'] is num
          ? (totals['grand_total_paise'] as num).toDouble()
          : 0.0;
      final grandTotalRupees = grandTotalPaise / 100.0;
      final amountInWordsStr = _numberToWords(grandTotalRupees);

      // Group GST breakdown by rate
      final Map<String, int> gstBreakdownByRatePaise = {};
      for (var item in items) {
        final rate = item['gst_rate']?.toString() ?? '0';
        final taxAmount = (item['cgst_amount_paise'] as num? ?? 0).toInt() +
            (item['sgst_amount_paise'] as num? ?? 0).toInt() +
            (item['igst_amount_paise'] as num? ?? 0).toInt();
        gstBreakdownByRatePaise[rate] =
            (gstBreakdownByRatePaise[rate] ?? 0) + taxAmount;
      }

      doc.addPage(pw.Page(
        pageFormat: pageFormat,
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            // --- HEADER ---
            pw.Center(
              child: pw.Text(
                'TAX INVOICE',
                style:
                    pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                _stringOr(seller['business_name'], shopDetails.shopName,
                        'MY SHOP')
                    .toUpperCase(),
                textAlign: pw.TextAlign.center,
                style:
                    pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
              ),
            ),
            if (_stringOr(seller['legal_name'], '', '').isNotEmpty)
              pw.Center(
                  child: pw.Text(_stringOr(seller['legal_name'], '', ''),
                      style: const pw.TextStyle(fontSize: 9))),
            pw.Center(
              child: pw.Text(
                _stringOr(seller['address_line'], shopDetails.address, '-'),
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
            pw.Center(
              child: pw.Text(
                '${_stringOr(seller['city'], '', '-')}, ${_stringOr(seller['state'], '', '-')} - ${_stringOr(seller['pincode'], '', '-')}',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
            pw.Center(
              child: pw.Text(
                'GSTIN: ${_stringOr(seller['gstin'], '', '-')}',
                style:
                    pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              ),
            ),
            if (_stringOr(seller['contact_number'], shopDetails.phone1, '')
                .isNotEmpty)
              pw.Center(
                  child: pw.Text(
                      'Phone: ${_stringOr(seller['contact_number'], shopDetails.phone1, '')}',
                      style: const pw.TextStyle(fontSize: 9))),
            if (_stringOr(seller['email'], '', '').isNotEmpty)
              pw.Center(
                  child: pw.Text('Email: ${_stringOr(seller['email'], '', '')}',
                      style: const pw.TextStyle(fontSize: 9))),

            pw.Divider(thickness: 1),

            // --- INVOICE META ---
            _gstPrintRow('Invoice No.',
                _stringOr(invoice['invoice_number'], '', 'Pending')),
            _gstPrintRow('Invoice Date', _formatGstDate(invoice['issue_date'])),
            if (_stringOr(invoice['due_date'], '', '').isNotEmpty)
              _gstPrintRow('Due Date', _formatGstDate(invoice['due_date'])),
            _gstPrintRow(
                'Place of Supply',
                _stringOr(placeOfSupply['state'],
                    seller['state'] ?? 'Maharashtra', 'Maharashtra')),

            pw.Divider(thickness: 1),

            // --- BILL TO ---
            pw.Text('BILL TO',
                style:
                    pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.SizedBox(height: 2),
            pw.Text(_stringOr(customer['name'], '', 'Walk-in customer'),
                style:
                    pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            if (_stringOr(customer['gstin'], '', '').isNotEmpty)
              pw.Text('GSTIN: ${_stringOr(customer['gstin'], '', '')}',
                  style: const pw.TextStyle(fontSize: 9)),
            if (_stringOr(customer['address_line'], '', '').isNotEmpty)
              pw.Text(_stringOr(customer['address_line'], '', ''),
                  style: const pw.TextStyle(fontSize: 9)),
            if (_stringOr(customer['city'], '', '').isNotEmpty ||
                _stringOr(customer['state'], '', '').isNotEmpty)
              pw.Text(
                  '${_stringOr(customer['city'], '', '')}, ${_stringOr(customer['state'], '', '')} ${_stringOr(customer['pincode'], '', '')}'
                      .trim(),
                  style: const pw.TextStyle(fontSize: 9)),
            if (_stringOr(customer['phone'], '', '').isNotEmpty)
              pw.Text('Phone: ${_stringOr(customer['phone'], '', '')}',
                  style: const pw.TextStyle(fontSize: 9)),

            pw.Divider(thickness: 1),

            // --- ITEMS TABLE ---
            pw.Text('ITEMS',
                style:
                    pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.SizedBox(height: 4),
            pw.Row(children: [
              pw.Expanded(
                  flex: 4,
                  child: pw.Text('ITEM',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 9))),
              pw.Expanded(
                  flex: 2,
                  child: pw.Text('QTY',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 9))),
              pw.Expanded(
                  flex: 2,
                  child: pw.Text('RATE',
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 9))),
              pw.Expanded(
                  flex: 2,
                  child: pw.Text('GST',
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 9))),
              pw.Expanded(
                  flex: 3,
                  child: pw.Text('TOTAL',
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 9))),
            ]),
            pw.Divider(),

            ...items.map((item) {
              final hsnOrSac = item['hsn_code']?.toString() ??
                  item['sac_code']?.toString() ??
                  '';
              final codePrefix = (item['tax_category']
                              ?.toString()
                              .toLowerCase()
                              .startsWith('service') ==
                          true ||
                      item['sac_code'] != null)
                  ? 'SAC'
                  : 'HSN';
              final lineTaxPaise =
                  (item['cgst_amount_paise'] as num? ?? 0).toInt() +
                      (item['sgst_amount_paise'] as num? ?? 0).toInt() +
                      (item['igst_amount_paise'] as num? ?? 0).toInt();

              // Safe string extraction with null handling
              final itemName = _stringOr(item['name'], '', 'Item');
              final itemQty = _stringOr(item['quantity'], '', '1');
              final itemUnit = _stringOr(item['unit'], '', 'PCS');
              final itemGstRate = _stringOr(item['gst_rate'], '', '0');

              return pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 3),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(children: [
                      pw.Expanded(
                          flex: 4,
                          child: pw.Text(itemName,
                              style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 9))),
                      pw.Expanded(
                          flex: 2,
                          child: pw.Text(
                              '$itemQty $itemUnit',
                              textAlign: pw.TextAlign.center,
                              style: const pw.TextStyle(fontSize: 9))),
                      pw.Expanded(
                          flex: 2,
                          child: pw.Text(_gstMoney(item['rate_paise']),
                              textAlign: pw.TextAlign.right,
                              style: const pw.TextStyle(fontSize: 9))),
                      pw.Expanded(
                          flex: 2,
                          child: pw.Text(
                              '$itemGstRate%',
                              textAlign: pw.TextAlign.right,
                              style: const pw.TextStyle(fontSize: 9))),
                      pw.Expanded(
                          flex: 3,
                          child: pw.Text(_gstMoney(item['total_amount_paise']),
                              textAlign: pw.TextAlign.right,
                              style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 9))),
                    ]),
                    pw.Row(children: [
                      pw.Expanded(
                        flex: 4,
                        child: pw.Text(
                          hsnOrSac.isNotEmpty ? '$codePrefix: $hsnOrSac' : '',
                          style: const pw.TextStyle(
                              fontSize: 8, color: PdfColors.grey700),
                        ),
                      ),
                      pw.Expanded(
                        flex: 5,
                        child: pw.Text(
                          'Tax: ${_gstMoney(lineTaxPaise)}',
                          textAlign: pw.TextAlign.right,
                          style: const pw.TextStyle(
                              fontSize: 8, color: PdfColors.grey700),
                        ),
                      ),
                    ]),
                  ],
                ),
              );
            }),

            pw.Divider(thickness: 1),

            // --- SUMMARY & GST BREAKDOWN ---
            pw.Text('SUMMARY',
                style:
                    pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.SizedBox(height: 4),
            _gstPrintRow('Subtotal', _gstMoney(totals['taxable_value_paise'])),
            pw.SizedBox(height: 4),
            pw.Text('GST BREAKDOWN',
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 8,
                    color: PdfColors.grey800)),
            ...gstBreakdownByRatePaise.entries.map(
                (e) => _gstPrintRow('GST @ ${e.key}%', _gstMoney(e.value))),
            if ((totals['cgst_amount_paise'] as num? ?? 0) > 0)
              _gstPrintRow('CGST', _gstMoney(totals['cgst_amount_paise'])),
            if ((totals['sgst_amount_paise'] as num? ?? 0) > 0)
              _gstPrintRow('SGST', _gstMoney(totals['sgst_amount_paise'])),
            if ((totals['igst_amount_paise'] as num? ?? 0) > 0)
              _gstPrintRow('IGST', _gstMoney(totals['igst_amount_paise'])),
            pw.Divider(),
            _gstPrintRow('Total GST', _gstMoney(totals['total_tax_paise']),
                strong: true),
            pw.Divider(thickness: 1),

            // --- GRAND TOTAL ---
            _gstPrintRow('GRAND TOTAL', _gstMoney(totals['grand_total_paise']),
                strong: true),
            pw.SizedBox(height: 6),
            pw.Text('Amount in Words:',
                style:
                    pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
            pw.Text(amountInWordsStr, style: const pw.TextStyle(fontSize: 9)),

            pw.SizedBox(height: 6),
            _gstPrintRow('Payment Status',
                _stringOr(invoice['payment_status'], 'PAID', 'PAID').toUpperCase(),
                strong: true),
            _gstPrintRow('Payment Method',
                _stringOr(invoice['payment_method'], 'UPI', 'UPI').toUpperCase()),

            // --- BANK DETAILS ---
            if (hasBankDetails) ...[
              pw.Divider(thickness: 1),
              pw.Text('BANK DETAILS',
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 10)),
              pw.SizedBox(height: 2),
              _gstPrintRow(
                  'Bank Name',
                  _stringOr(
                      bankDetails['bank_name'], seller['bank_name'], '-')),
              _gstPrintRow(
                  'Account Name',
                  _stringOr(bankDetails['account_name'], seller['account_name'],
                      '-')),
              _gstPrintRow(
                  'Account No.',
                  _stringOr(bankDetails['account_number'],
                      seller['account_number'], '-')),
              _gstPrintRow('IFSC Code',
                  _stringOr(bankDetails['ifsc'], seller['ifsc'], '-')),
            ],

            // --- TERMS & CONDITIONS ---
            pw.Divider(thickness: 1),
            pw.Text('TERMS & CONDITIONS',
                style:
                    pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
            pw.SizedBox(height: 2),
            pw.Text(
              _stringOr(seller['invoice_terms'], '',
                  'Payment due within 30 days for credit sales.\nGoods are subject to applicable return policy.'),
              style: const pw.TextStyle(fontSize: 8),
            ),

            pw.SizedBox(height: 16),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Authorized Signatory',
                      style: const pw.TextStyle(fontSize: 9)),
                  pw.Text(
                      _stringOr(seller['business_name'], shopDetails.shopName,
                              'MY SHOP')
                          .toUpperCase(),
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 9)),
                ],
              ),
            ),

            if (qrCodePath != null &&
                qrCodePath.isNotEmpty &&
                File(qrCodePath).existsSync()) ...[
              pw.SizedBox(height: 10),
              pw.Center(
                  child: pw.Container(
                      width: 110,
                      height: 110,
                      child: pw.Image(
                          pw.MemoryImage(File(qrCodePath).readAsBytesSync()),
                          fit: pw.BoxFit.contain))),
              pw.Center(
                  child: pw.Text('Scan to Pay',
                      style: const pw.TextStyle(fontSize: 8))),
            ],

            pw.SizedBox(height: 14),
            pw.Divider(thickness: 1),
            pw.Center(
              child: pw.Text(
                'THANK YOU!',
                style:
                    pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
              ),
            ),
            pw.SizedBox(height: 16),
          ],
        ),
      ));

      await for (final page
          in Printing.raster(await doc.save(), pages: [0], dpi: 203)) {
        final imageBytes = await page.toPng();
        final originalImage = img.decodeImage(imageBytes);
        if (originalImage == null) continue;
        final resizedImage = img.copyResize(originalImage, width: 384);
        await bluetooth.writeBytes(Uint8List.fromList([0x1b, 0x40]));
        await Future.delayed(const Duration(milliseconds: 100));
        await bluetooth
            .writeBytes(Uint8List.fromList(_generateRasterData(resizedImage)));
        await Future.delayed(const Duration(milliseconds: 100));
        await bluetooth.writeBytes(Uint8List.fromList([0x0a, 0x0a, 0x0a]));
        break;
      }
      return 'Success';
    } catch (e) {
      return 'Print Error: $e';
    }
  }

  String _stringOr(dynamic value, String fallback, String emptyFallback) {
    final result = value?.toString().trim() ?? '';
    return result.isNotEmpty
        ? result
        : (fallback.isNotEmpty ? fallback : emptyFallback);
  }

  String _gstMoney(dynamic paise) {
    final value = paise is num ? paise.toInt() : int.tryParse('$paise') ?? 0;
    final sign = value < 0 ? '-' : '';
    final absolute = value.abs();
    return '${sign}Rs ${absolute ~/ 100}.${(absolute % 100).toString().padLeft(2, '0')}';
  }

  String _formatGstDate(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return '-';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return '${parsed.day.toString().padLeft(2, '0')}/'
        '${parsed.month.toString().padLeft(2, '0')}/'
        '${parsed.year}';
  }

  pw.Widget _gstPrintRow(String label, String value, {bool strong = false}) {
    final style = pw.TextStyle(
        fontSize: strong ? 12 : 10,
        fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal);
    return pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: style),
          pw.Text(value, style: style),
        ]);
  }

  // --- BIT PACKING (Fixed Black Background & Transparency) ---
  List<int> _generateRasterData(img.Image src) {
    List<int> data = [];
    int width = src.width;
    int height = src.height;

    // Header: GS v 0 0
    data.addAll([0x1d, 0x76, 0x30, 0x00]);

    int widthBytes = (width + 7) ~/ 8;
    data.add(widthBytes % 256);
    data.add(widthBytes ~/ 256);
    data.add(height % 256);
    data.add(height ~/ 256);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < widthBytes; x++) {
        int byte = 0;
        for (int k = 0; k < 8; k++) {
          int pixelX = x * 8 + k;
          if (pixelX < width) {
            final pixel = src.getPixel(pixelX, y);

            // 1. Check Transparency (Ignore background)
            if (pixel.a == 0) continue;

            // 2. Check Brightness (Dark pixels = 1, Light pixels = 0)
            double brightness = img.getLuminance(pixel).toDouble();
            if (brightness <= 1.0) brightness *= 255;

            if (brightness < 128) {
              byte |= (1 << (7 - k));
            }
          }
        }
        data.add(byte);
      }
    }
    return data;
  }
}
