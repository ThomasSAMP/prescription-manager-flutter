import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/models/syncable_model.dart';

class OrdonnanceModel implements SyncableModel {
  @override
  final String id;
  final String patientName;
  final String createdBy;
  @override
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  @override
  final bool isSynced;

  OrdonnanceModel({
    required this.id,
    required this.patientName,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.isSynced = false,
  });

  factory OrdonnanceModel.fromJson(Map<String, dynamic> json) {
    return OrdonnanceModel(
      id: json['id'],
      patientName: json['patientName'],
      createdBy: json['createdBy'],
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
      'patientName': patientName,
      'createdBy': createdBy,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isSynced': isSynced,
    };
  }

  @override
  OrdonnanceModel copyWith({
    String? id,
    String? patientName,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isSynced,
  }) {
    return OrdonnanceModel(
      id: id ?? this.id,
      patientName: patientName ?? this.patientName,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
    );
  }
}
