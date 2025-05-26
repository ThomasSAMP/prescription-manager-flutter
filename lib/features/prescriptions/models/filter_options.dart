import 'package:flutter/material.dart';

enum FilterOption { all, expired, critical, warning, ok }

extension FilterOptionExtension on FilterOption {
  String get label {
    switch (this) {
      case FilterOption.all:
        return 'Tous';
      case FilterOption.expired:
        return 'Expirés';
      case FilterOption.critical:
        return 'Critiques';
      case FilterOption.warning:
        return 'Attention';
      case FilterOption.ok:
        return 'OK';
    }
  }

  IconData get icon {
    switch (this) {
      case FilterOption.all:
        return Icons.all_inclusive;
      case FilterOption.expired:
        return Icons.dangerous;
      case FilterOption.critical:
        return Icons.error;
      case FilterOption.warning:
        return Icons.warning;
      case FilterOption.ok:
        return Icons.check_circle;
    }
  }

  Color get color {
    switch (this) {
      case FilterOption.all:
        return Colors.blue;
      case FilterOption.expired:
        return Colors.red.shade900;
      case FilterOption.critical:
        return Colors.red;
      case FilterOption.warning:
        return Colors.orange;
      case FilterOption.ok:
        return Colors.green;
    }
  }
}
