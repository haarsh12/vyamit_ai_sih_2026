class DashboardData {
  final DashboardSummary summary;
  final List<TopSellingItem> topSellingItems;
  final List<CategoryBreakdown> categoryBreakdown;
  final List<PeakHour> peakHours;
  final PeakDay? peakDay;

  DashboardData({
    required this.summary,
    required this.topSellingItems,
    required this.categoryBreakdown,
    required this.peakHours,
    this.peakDay,
  });

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    return DashboardData(
      summary: DashboardSummary.fromJson(json['summary']),
      topSellingItems: (json['top_selling_items'] as List)
          .map((item) => TopSellingItem.fromJson(item))
          .toList(),
      categoryBreakdown: (json['category_breakdown'] as List)
          .map((cat) => CategoryBreakdown.fromJson(cat))
          .toList(),
      peakHours: (json['peak_hours'] as List)
          .map((hour) => PeakHour.fromJson(hour))
          .toList(),
      peakDay: json['peak_day'] != null 
          ? PeakDay.fromJson(json['peak_day']) 
          : null,
    );
  }
}

class DashboardSummary {
  final double totalRevenue;
  final int totalBills;
  final double averageBillValue;
  final int totalInventoryItems;

  DashboardSummary({
    required this.totalRevenue,
    required this.totalBills,
    required this.averageBillValue,
    required this.totalInventoryItems,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    return DashboardSummary(
      totalRevenue: (json['total_revenue'] ?? 0).toDouble(),
      totalBills: json['total_bills'] ?? 0,
      averageBillValue: (json['average_bill_value'] ?? 0).toDouble(),
      totalInventoryItems: json['total_inventory_items'] ?? 0,
    );
  }
}

class TopSellingItem {
  final String name;
  final String unit;
  final double quantity;
  final int timesSold;

  TopSellingItem({
    required this.name,
    required this.unit,
    required this.quantity,
    required this.timesSold,
  });

  factory TopSellingItem.fromJson(Map<String, dynamic> json) {
    return TopSellingItem(
      name: json['name'] ?? '',
      unit: json['unit'] ?? '',
      quantity: (json['quantity'] ?? 0).toDouble(),
      timesSold: json['times_sold'] ?? 0,
    );
  }
}

class CategoryBreakdown {
  final String category;
  final double totalSales;
  final double quantity;
  final double percentage;

  CategoryBreakdown({
    required this.category,
    required this.totalSales,
    required this.quantity,
    required this.percentage,
  });

  factory CategoryBreakdown.fromJson(Map<String, dynamic> json) {
    return CategoryBreakdown(
      category: json['category'] ?? 'Other',
      totalSales: (json['total_sales'] ?? 0).toDouble(),
      quantity: (json['quantity'] ?? 0).toDouble(),
      percentage: (json['percentage'] ?? 0).toDouble(),
    );
  }
}

class PeakHour {
  final int hour;
  final int salesCount;
  final double totalSales;

  PeakHour({
    required this.hour,
    required this.salesCount,
    required this.totalSales,
  });

  factory PeakHour.fromJson(Map<String, dynamic> json) {
    return PeakHour(
      hour: json['hour'] ?? 0,
      salesCount: json['sales_count'] ?? 0,
      totalSales: (json['total_sales'] ?? 0).toDouble(),
    );
  }
}

class PeakDay {
  final String day;
  final int billCount;
  final double totalSales;

  PeakDay({
    required this.day,
    required this.billCount,
    required this.totalSales,
  });

  factory PeakDay.fromJson(Map<String, dynamic> json) {
    return PeakDay(
      day: json['day'] ?? 'N/A',
      billCount: json['bill_count'] ?? 0,
      totalSales: (json['total_sales'] ?? 0).toDouble(),
    );
  }
}

class BillHistory {
  final int id;
  final double totalAmount;
  final int totalItems;
  final List<Map<String, dynamic>> items;
  final String? customerPhone;
  final String? customerName;
  final String paymentMethod;
  final DateTime billDate;

  BillHistory({
    required this.id,
    required this.totalAmount,
    required this.totalItems,
    required this.items,
    this.customerPhone,
    this.customerName,
    required this.paymentMethod,
    required this.billDate,
  });

  factory BillHistory.fromJson(Map<String, dynamic> json) {
    return BillHistory(
      id: json['id'],
      totalAmount: (json['total_amount'] ?? 0).toDouble(),
      totalItems: json['total_items'] ?? 0,
      items: List<Map<String, dynamic>>.from(json['items'] ?? []),
      customerPhone: json['customer_phone'],
      customerName: json['customer_name'],
      paymentMethod: json['payment_method'] ?? 'cash',
      billDate: DateTime.parse(json['bill_date']),
    );
  }
}
