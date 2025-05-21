import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/models/syncable_model.dart';

class MedicamentModel implements SyncableModel {
  @override
  final String id;
  final String ordonnanceId;
  final String name;
  final DateTime expirationDate;
  final String? dosage;
  final String? instructions;
  @override
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  @override
  final bool isSynced;

  MedicamentModel({
    required this.id,
    required this.ordonnanceId,
    required this.name,
    required this.expirationDate,
    this.dosage,
    this.instructions,
    required this.createdAt,
    required this.updatedAt,
    this.isSynced = false,
  });

  factory MedicamentModel.fromJson(Map<String, dynamic> json) {
    return MedicamentModel(
      id: json['id'],
      ordonnanceId: json['ordonnanceId'],
      name: json['name'],
      expirationDate:
          (json['expirationDate'] is Timestamp)
              ? (json['expirationDate'] as Timestamp).toDate()
              : DateTime.parse(json['expirationDate']),
      dosage: json['dosage'],
      instructions: json['instructions'],
      createdAt:
          (json['createdAt'] is Timestamp)
              ? (json['createdAt'] as Timestamp).toDate()
              : DateTime.parse(json['createdAt']),
      updatedAt:
          (json['updatedAt'] is Timestamp)
              ? (json['updatedAt'] as Timestamp).toDate()
              : DateTime.parse(json['updatedAt']),
      isSynced: json['isSynced'] ?? false,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ordonnanceId': ordonnanceId,
      'name': name,
      'expirationDate': expirationDate.toIso8601String(),
      'dosage': dosage,
      'instructions': instructions,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isSynced': isSynced,
    };
  }

  @override
  MedicamentModel copyWith({
    String? id,
    String? ordonnanceId,
    String? name,
    DateTime? expirationDate,
    String? dosage,
    String? instructions,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isSynced,
  }) {
    return MedicamentModel(
      id: id ?? this.id,
      ordonnanceId: ordonnanceId ?? this.ordonnanceId,
      name: name ?? this.name,
      expirationDate: expirationDate ?? this.expirationDate,
      dosage: dosage ?? this.dosage,
      instructions: instructions ?? this.instructions,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  // Méthode pour vérifier si le médicament arrive bientôt à expiration
  ExpirationStatus getExpirationStatus() {
    final now = DateTime.now();
    final difference = expirationDate.difference(now).inDays;

    if (difference <= 0) {
      return ExpirationStatus.expired;
    } else if (difference <= 14) {
      return ExpirationStatus.critical;
    } else if (difference <= 30) {
      return ExpirationStatus.warning;
    } else {
      return ExpirationStatus.ok;
    }
  }
}

enum ExpirationStatus { ok, warning, critical, expired }

extension ExpirationStatusExtension on ExpirationStatus {
  bool get needsAttention =>
      this == ExpirationStatus.warning ||
      this == ExpirationStatus.critical ||
      this == ExpirationStatus.expired;

  Color getColor() {
    switch (this) {
      case ExpirationStatus.ok:
        return Colors.green;
      case ExpirationStatus.warning:
        return Colors.orange;
      case ExpirationStatus.critical:
        return Colors.red;
      case ExpirationStatus.expired:
        return Colors.red.shade900;
    }
  }

  IconData getIcon() {
    switch (this) {
      case ExpirationStatus.ok:
        return Icons.check_circle;
      case ExpirationStatus.warning:
        return Icons.warning;
      case ExpirationStatus.critical:
        return Icons.error;
      case ExpirationStatus.expired:
        return Icons.dangerous;
    }
  }
}
