import 'package:intl/intl.dart';

/// Format bytes to human-readable string
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Format number with commas
String formatNumber(int number) {
  return NumberFormat('#,###').format(number);
}

/// Format date
String formatDate(DateTime date) {
  return DateFormat('MMM d, yyyy').format(date);
}

/// Format date short
String formatDateShort(DateTime date) {
  return DateFormat('MMM d').format(date);
}

/// Format percentage
String formatPercentage(double value) {
  return '${value.toStringAsFixed(1)}%';
}
