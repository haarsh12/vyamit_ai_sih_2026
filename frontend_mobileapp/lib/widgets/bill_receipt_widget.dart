import 'dart:io';
import 'package:flutter/material.dart';
import '../models/shop_details.dart';
import '../core/theme.dart';

class BillReceiptWidget extends StatelessWidget {
  final ShopDetails shopDetails;
  final String billId;
  final String date;
  final String time;
  final List<dynamic> items;
  final double total;
  final bool isHindi;
  final bool showQr;
  final String? qrImagePath;
  final String? snapshotShopName;
  final String? snapshotAddress;
  final String? snapshotPhone;

  const BillReceiptWidget(
      {super.key,
      required this.shopDetails,
      this.snapshotShopName,
      this.snapshotAddress,
      this.snapshotPhone,
      required this.billId,
      required this.date,
      required this.time,
      required this.items,
      required this.total,
      required this.isHindi,
      this.showQr = false,
      this.qrImagePath});

  String _toDevanagari(String text) {
    if (text.toLowerCase().contains("gupta")) return "गुप्ता जनरल स्टोर";
    if (text.toLowerCase().contains("nagpur"))
      return "123, मेन मार्केट, नागपुर, महाराष्ट्र";
    return text;
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

  @override
  Widget build(BuildContext context) {
    String rawShopName = snapshotShopName ?? shopDetails.shopName;
    String rawAddress = snapshotAddress ?? shopDetails.address;
    String displayShopName = isHindi ? _toDevanagari(rawShopName) : rawShopName;
    String displayAddress = isHindi ? _toDevanagari(rawAddress) : rawAddress;
    String displayPhone1 = snapshotPhone ?? shopDetails.phone1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            const BoxShadow(
                color: Colors.black12, blurRadius: 15, offset: Offset(0, 5))
          ]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(displayShopName,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B)),
            textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text("Ph: $displayPhone1",
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            textAlign: TextAlign.center),
        // Second phone number (only if exists)
        if (shopDetails.phone2.isNotEmpty)
          Text("Ph: ${shopDetails.phone2}",
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              textAlign: TextAlign.center),
        const Divider(thickness: 1.5, height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Bill ID: $billId",
                style: TextStyle(fontSize: 11, color: Colors.grey[700])),
            Text("Time: $time",
                style: TextStyle(fontSize: 11, color: Colors.grey[700]))
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(date, style: TextStyle(fontSize: 11, color: Colors.grey[700])),
            Text("Cust ID: 001",
                style: TextStyle(fontSize: 11, color: Colors.grey[700]))
          ]),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
              flex: 4,
              child: Text(isHindi ? "सामग्री" : "ITEM",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12))),
          Expanded(
              flex: 1,
              child: Text(isHindi ? "मात्रा" : "QTY",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12))),
          Expanded(
              flex: 2,
              child: Text(isHindi ? "दर" : "RATE",
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12))),
          Expanded(
              flex: 2,
              child: Text(isHindi ? "मूल्य" : "PRICE",
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12))),
        ]),
        const Divider(height: 16),
        ...items.map((item) {
          String name = isHindi
              ? (item['hi'] ?? item['en'])
              : (item['en'] ?? item['name']);
          String unit = _getShortUnit(item['unit'] ?? 'kg');
          double rateValue = (item['rate'] as num).toDouble();
          double totalValue = (item['total'] as num).toDouble();
          return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(children: [
                Expanded(
                    flex: 4,
                    child: Text(name,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
                Expanded(
                    flex: 1,
                    child: Text(item['qty'].toString(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13))),
                Expanded(
                    flex: 2,
                    child: Text("₹${_formatNumber(rateValue)}/$unit",
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12))),
                Expanded(
                    flex: 2,
                    child: Text("₹${_formatNumber(totalValue)}",
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold))),
              ]));
        }),
        const Divider(thickness: 1.5, height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(isHindi ? "कुल योग:" : "TOTAL:",
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          Text("₹${_formatNumber(total)}",
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                  color: AppColors.primaryGreen)),
        ]),
        if (showQr) ...[
          const SizedBox(height: 20),
          Center(
              child: Column(children: [
            Container(
                width: double.infinity,
                height: 250,
                color: Colors.grey[200],
                child: qrImagePath != null
                    ? (qrImagePath!.startsWith('assets/')
                        ? Image.asset(qrImagePath!, fit: BoxFit.contain)
                        : Image.file(File(qrImagePath!), fit: BoxFit.contain))
                    : const Icon(Icons.qr_code_2,
                        size: 200, color: Colors.black54)),
            const SizedBox(height: 5),
            const Text("Scan to Pay",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ])),
        ],
        const SizedBox(height: 12),
        Text(isHindi ? "धन्यवाद, फिर आयें" : "THANK YOU, VISIT AGAIN",
            style: const TextStyle(
                fontSize: 10, color: Colors.grey, letterSpacing: 1)),
        const SizedBox(height: 2),
        Text(displayAddress,
            style: const TextStyle(fontSize: 9, color: Colors.grey),
            textAlign: TextAlign.center),
        const SizedBox(height: 2),
        const Text("App: My Kirana",
            style: TextStyle(fontSize: 8, color: Colors.grey)),
      ]),
    );
  }
}
