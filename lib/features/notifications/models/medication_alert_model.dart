import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/models/syncable_model.dart';

enum AlertLevel { warning, critical, expired }

class MedicationAlertModel implements SyncableModel {
  @override
  final String id;
  final String medicamentId;
  final String ordonnanceId;
  final String patientName;
  final String medicamentName;
  final DateTime expirationDate;
  final AlertLevel alertLevel;
  final String alertDate;
  final Map<String, UserAlertState> userStates;
  @override
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  @override
  final bool isSynced;
  @override
  final int version;

  MedicationAlertModel({
    required this.id,
    required this.medicamentId,
    required this.ordonnanceId,
    required this.patientName,
    required this.medicamentName,
    required this.expirationDate,
    required this.alertLevel,
    required this.alertDate,
    required this.userStates,
    required this.createdAt,
    DateTime? updatedAt,
    this.isSynced = true,
    this.version = 1,
  }) : updatedAt = updatedAt ?? createdAt;

  factory MedicationAlertModel.fromJson(Map<String, dynamic> json, String id) {
    AlertLevel parseAlertLevel(String level) {
      switch (level) {
        case 'warning':
          return AlertLevel.warning;
        case 'critical':
          return AlertLevel.critical;
        case 'expired':
          return AlertLevel.expired;
        default:
          return AlertLevel.warning;
      }
    }

    DateTime parseDateTime(dynamic dateValue) {
      if (dateValue == null) return DateTime.now();

      if (dateValue is Timestamp) {
        return dateValue.toDate();
      } else if (dateValue is String) {
        try {
          return DateTime.parse(dateValue);
        } catch (e) {
          return DateTime.now();
        }
      } else if (dateValue is int) {
        return DateTime.fromMillisecondsSinceEpoch(dateValue);
      } else if (dateValue is Map<String, dynamic>) {
        if (dateValue.containsKey('_seconds')) {
          return DateTime.fromMillisecondsSinceEpoch(
            (dateValue['_seconds'] as int) * 1000 +
                ((dateValue['_nanoseconds'] as int?) ?? 0) ~/ 1000000,
          );
        }
      }

      return DateTime.now();
    }

    final userStates = <String, UserAlertState>{};
    final userStatesJson = json['userStates'] as Map<String, dynamic>? ?? {};

    for (final entry in userStatesJson.entries) {
      final stateData = entry.value as Map<String, dynamic>;
      userStates[entry.key] = UserAlertState.fromJson(stateData);
    }

    final createdAt = parseDateTime(json['createdAt']);
    final updatedAt = parseDateTime(json['updatedAt']);

    return MedicationAlertModel(
      id: id,
      medicamentId: json['medicamentId'] ?? '',
      ordonnanceId: json['ordonnanceId'] ?? '',
      patientName: json['patientName'] ?? '',
      medicamentName: json['medicamentName'] ?? '',
      expirationDate: parseDateTime(json['expirationDate']),
      alertLevel: parseAlertLevel(json['alertLevel'] ?? 'warning'),
      alertDate: json['alertDate'] ?? '',
      userStates: userStates,
      createdAt: createdAt,
      updatedAt: updatedAt,
      isSynced: json['isSynced'] ?? true,
      version: json['version'] ?? 1,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    String alertLevelToString(AlertLevel level) {
      switch (level) {
        case AlertLevel.warning:
          return 'warning';
        case AlertLevel.critical:
          return 'critical';
        case AlertLevel.expired:
          return 'expired';
      }
    }

    final userStatesJson = <String, dynamic>{};
    for (final entry in userStates.entries) {
      userStatesJson[entry.key] = entry.value.toJson();
    }

    return {
      'id': id,
      'medicamentId': medicamentId,
      'ordonnanceId': ordonnanceId,
      'patientName': patientName,
      'medicamentName': medicamentName,
      'expirationDate': Timestamp.fromDate(expirationDate),
      'alertLevel': alertLevelToString(alertLevel),
      'alertDate': alertDate,
      'userStates': userStatesJson,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'isSynced': isSynced,
      'version': version,
    };
  }

  @override
  MedicationAlertModel copyWith({
    String? id,
    String? medicamentId,
    String? ordonnanceId,
    String? patientName,
    String? medicamentName,
    DateTime? expirationDate,
    AlertLevel? alertLevel,
    String? alertDate,
    Map<String, UserAlertState>? userStates,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isSynced,
    int? version,
  }) {
    return MedicationAlertModel(
      id: id ?? this.id,
      medicamentId: medicamentId ?? this.medicamentId,
      ordonnanceId: ordonnanceId ?? this.ordonnanceId,
      patientName: patientName ?? this.patientName,
      medicamentName: medicamentName ?? this.medicamentName,
      expirationDate: expirationDate ?? this.expirationDate,
      alertLevel: alertLevel ?? this.alertLevel,
      alertDate: alertDate ?? this.alertDate,
      userStates: userStates ?? this.userStates,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
      version: version ?? this.version,
    );
  }

  // Méthodes utilitaires
  String getDateGroup() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final lastWeek = today.subtract(const Duration(days: 7));
    final lastMonth = today.subtract(const Duration(days: 30));
    final lastYear = today.subtract(const Duration(days: 365));

    final alertDateTime = DateTime.parse('${alertDate}T00:00:00');
    final alertDateOnly = DateTime(alertDateTime.year, alertDateTime.month, alertDateTime.day);

    if (alertDateOnly.isAtSameMomentAs(today)) {
      return 'Aujourd\'hui';
    } else if (alertDateOnly.isAtSameMomentAs(yesterday)) {
      return 'Hier';
    } else if (alertDateOnly.isAfter(lastWeek)) {
      return 'Cette semaine';
    } else if (alertDateOnly.isAfter(lastMonth)) {
      return 'Ce mois-ci';
    } else if (alertDateOnly.isAfter(lastYear)) {
      return 'Cette année';
    } else {
      return 'Plus ancien';
    }
  }

  IconData getIcon() {
    switch (alertLevel) {
      case AlertLevel.expired:
        return Icons.dangerous;
      case AlertLevel.critical:
        return Icons.error_outline;
      case AlertLevel.warning:
        return Icons.warning_amber_outlined;
    }
  }

  Color getColor() {
    switch (alertLevel) {
      case AlertLevel.expired:
        return Colors.red.shade900;
      case AlertLevel.critical:
        return Colors.red;
      case AlertLevel.warning:
        return Colors.orange;
    }
  }

  UserAlertState getUserState(String userId) {
    return userStates[userId] ?? UserAlertState.initial();
  }
}

class UserAlertState {
  final bool isRead;
  final bool isHidden;
  final DateTime? readAt;

  UserAlertState({required this.isRead, required this.isHidden, this.readAt});

  factory UserAlertState.initial() {
    return UserAlertState(isRead: false, isHidden: false);
  }

  factory UserAlertState.fromJson(Map<String, dynamic> json) {
    DateTime? parseReadAt(dynamic value) {
      if (value == null) return null;
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    return UserAlertState(
      isRead: json['isRead'] ?? false,
      isHidden: json['isHidden'] ?? false,
      readAt: parseReadAt(json['readAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isRead': isRead,
      'isHidden': isHidden,
      'readAt': readAt != null ? Timestamp.fromDate(readAt!) : null,
    };
  }

  UserAlertState copyWith({
    bool? isRead,
    bool? isHidden,
    DateTime? readAt,
    bool clearReadAt = false,
  }) {
    return UserAlertState(
      isRead: isRead ?? this.isRead,
      isHidden: isHidden ?? this.isHidden,
      readAt: clearReadAt ? null : (readAt ?? this.readAt),
    );
  }
}
