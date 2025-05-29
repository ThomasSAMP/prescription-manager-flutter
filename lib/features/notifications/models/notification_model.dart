import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

enum NotificationType { expirationCritical, expirationWarning, system }

class NotificationModel {
  final String id;
  final String title;
  final String body;
  final NotificationType type;
  final String? medicamentId;
  final String? ordonnanceId;
  final String? patientName;
  final String? medicamentName;
  final DateTime? expirationDate;
  final DateTime createdAt;

  NotificationModel({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    this.medicamentId,
    this.ordonnanceId,
    this.patientName,
    this.medicamentName,
    this.expirationDate,
    required this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json, String id) {
    NotificationType getType(String typeStr) {
      switch (typeStr) {
        case 'expiration_critical':
          return NotificationType.expirationCritical;
        case 'expiration_warning':
          return NotificationType.expirationWarning;
        default:
          return NotificationType.system;
      }
    }

    // ✅ Parser spécifique pour le format français
    DateTime parseFrenchDate(String dateStr) {
      // Format: "29 mai 2025 à 18:17:47 UTC+2"
      final months = {
        'janvier': '01',
        'février': '02',
        'mars': '03',
        'avril': '04',
        'mai': '05',
        'juin': '06',
        'juillet': '07',
        'août': '08',
        'septembre': '09',
        'octobre': '10',
        'novembre': '11',
        'décembre': '12',
      };

      try {
        // Extraire les parties de la date
        final parts = dateStr.split(' ');
        if (parts.length >= 5) {
          final day = parts[0];
          final monthName = parts[1];
          final year = parts[2];
          final time = parts[4]; // "18:17:47"

          final monthNum = months[monthName] ?? '01';

          // Construire la date ISO
          final isoDate = '$year-$monthNum-${day.padLeft(2, '0')}T$time';
          return DateTime.parse(isoDate);
        }
      } catch (e) {
        print('Error parsing French date: $dateStr, error: $e');
      }

      return DateTime.now();
    }

    // ✅ Fonction helper pour gérer différents types de dates
    DateTime parseDateTime(dynamic dateValue) {
      if (dateValue == null) return DateTime.now();

      if (dateValue is Timestamp) {
        return dateValue.toDate();
      } else if (dateValue is String) {
        try {
          // Essayer de parser la chaîne de caractères
          return DateTime.parse(dateValue);
        } catch (e) {
          // Si le parsing échoue, essayer d'autres formats
          try {
            // Format français : "29 mai 2025 à 18:17:47 UTC+2"
            return parseFrenchDate(dateValue);
          } catch (e2) {
            print('Error parsing date string: $dateValue, error: $e2');
            return DateTime.now();
          }
        }
      } else if (dateValue is int) {
        // Timestamp en millisecondes
        return DateTime.fromMillisecondsSinceEpoch(dateValue);
      } else if (dateValue is Map<String, dynamic>) {
        // Timestamp Firestore sérialisé
        if (dateValue.containsKey('_seconds')) {
          return DateTime.fromMillisecondsSinceEpoch(
            (dateValue['_seconds'] as int) * 1000 +
                ((dateValue['_nanoseconds'] as int?) ?? 0) ~/ 1000000,
          );
        }
      }

      print('Unknown date format: $dateValue (${dateValue.runtimeType})');
      return DateTime.now();
    }

    return NotificationModel(
      id: id,
      title: json['title'] ?? '',
      body: json['body'] ?? '',
      type: getType(json['type'] ?? ''),
      medicamentId: json['medicamentId'],
      ordonnanceId: json['ordonnanceId'],
      patientName: json['patientName'],
      medicamentName: json['medicamentName'],
      expirationDate: json['expirationDate'] != null ? parseDateTime(json['expirationDate']) : null,
      createdAt: parseDateTime(json['createdAt']), // ✅ Utiliser la fonction helper
    );
  }

  Map<String, dynamic> toJson() {
    String getTypeString(NotificationType type) {
      switch (type) {
        case NotificationType.expirationCritical:
          return 'expiration_critical';
        case NotificationType.expirationWarning:
          return 'expiration_warning';
        case NotificationType.system:
          return 'system';
      }
    }

    return {
      'title': title,
      'body': body,
      'type': getTypeString(type),
      'medicamentId': medicamentId,
      'ordonnanceId': ordonnanceId,
      'patientName': patientName,
      'medicamentName': medicamentName,
      'expirationDate': expirationDate != null ? Timestamp.fromDate(expirationDate!) : null,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  NotificationModel copyWith({
    String? id,
    String? title,
    String? body,
    NotificationType? type,
    String? medicamentId,
    String? ordonnanceId,
    String? patientName,
    String? medicamentName,
    DateTime? expirationDate,
    DateTime? createdAt,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      type: type ?? this.type,
      medicamentId: medicamentId ?? this.medicamentId,
      ordonnanceId: ordonnanceId ?? this.ordonnanceId,
      patientName: patientName ?? this.patientName,
      medicamentName: medicamentName ?? this.medicamentName,
      expirationDate: expirationDate ?? this.expirationDate,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // Méthode pour grouper les notifications par date
  String getDateGroup() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final lastWeek = today.subtract(const Duration(days: 7));
    final lastMonth = today.subtract(const Duration(days: 30));
    final lastYear = today.subtract(const Duration(days: 365));

    final notifDate = DateTime(createdAt.year, createdAt.month, createdAt.day);

    if (notifDate.isAtSameMomentAs(today)) {
      return 'Aujourd\'hui';
    } else if (notifDate.isAtSameMomentAs(yesterday)) {
      return 'Hier';
    } else if (notifDate.isAfter(lastWeek)) {
      return 'Cette semaine';
    } else if (notifDate.isAfter(lastMonth)) {
      return 'Ce mois-ci';
    } else if (notifDate.isAfter(lastYear)) {
      return 'Cette année';
    } else {
      return 'Plus ancien';
    }
  }

  // Méthode pour obtenir l'icône appropriée
  IconData getIcon() {
    switch (type) {
      case NotificationType.expirationCritical:
        return Icons.error_outline;
      case NotificationType.expirationWarning:
        return Icons.warning_amber_outlined;
      case NotificationType.system:
        return Icons.notifications_outlined;
    }
  }

  // Méthode pour obtenir la couleur appropriée
  Color getColor() {
    switch (type) {
      case NotificationType.expirationCritical:
        return Colors.red;
      case NotificationType.expirationWarning:
        return Colors.orange;
      case NotificationType.system:
        return Colors.blue;
    }
  }
}
