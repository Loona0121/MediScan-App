enum ExpiryStatus { expired, urgent, safe }

class InventoryItem {
  final String id;
  final String productName;
  final String category;
  final String expiryDate; // YYYY-MM
  final DateTime addedAt;

  const InventoryItem({
    required this.id,
    required this.productName,
    required this.category,
    required this.expiryDate,
    required this.addedAt,
  });

  DateTime get expiryMonth {
    final parts = expiryDate.split('-');
    if (parts.length != 2) return DateTime.now();
    return DateTime(int.parse(parts[0]), int.parse(parts[1]));
  }

  ExpiryStatus get status {
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    final expiry = expiryMonth;

    if (expiry.isBefore(currentMonth)) return ExpiryStatus.expired;

    final monthsUntil =
        (expiry.year - currentMonth.year) * 12 +
        (expiry.month - currentMonth.month);
    if (monthsUntil <= 3) return ExpiryStatus.urgent;

    return ExpiryStatus.safe;
  }

  String get formattedExpiry {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[expiryMonth.month - 1]} ${expiryMonth.year}';
  }

  String get statusLabel {
    switch (status) {
      case ExpiryStatus.expired:
        return 'Expired';
      case ExpiryStatus.urgent:
        return 'Urgent';
      case ExpiryStatus.safe:
        return 'Safe';
    }
  }
}
