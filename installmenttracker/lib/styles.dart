import 'package:flutter/material.dart';

/// Centralized styles used across the app for amounts and percentages.
class AppStyles {
  // Bold style for monetary amounts
  static const TextStyle amount = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: Colors.black87,
  );

  // Bold style for percentage values
  static const TextStyle percent = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: Colors.black87,
  );
}
