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
  final bool read;

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
    required this.read,
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

    return NotificationModel(
      id: id,
      title: json['title'] ?? '',
      body: json['body'] ?? '',
      type: getType(json['type'] ?? ''),
      medicamentId: json['medicamentId'],
      ordonnanceId: json['ordonnanceId'],
      patientName: json['patientName'],
      medicamentName: json['medicamentName'],
      expirationDate:
          json['expirationDate'] != null ? (json['expirationDate'] as Timestamp).toDate() : null,
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      read: json['read'] ?? false,
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
      'read': read,
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
    bool? read,
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
      read: read ?? this.read,
    );
  }

  // Méthode pour grouper les notifications par date
  String getDateGroup() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final lastWeek = today.subtract(const Duration(days: 7));

    final notifDate = DateTime(createdAt.year, createdAt.month, createdAt.day);

    if (notifDate.isAtSameMomentAs(today)) {
      return 'Aujourd\'hui';
    } else if (notifDate.isAtSameMomentAs(yesterday)) {
      return 'Hier';
    } else if (notifDate.isAfter(lastWeek)) {
      return 'Cette semaine';
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
