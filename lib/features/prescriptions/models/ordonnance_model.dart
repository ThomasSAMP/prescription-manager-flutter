import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/models/syncable_model.dart';
import '../../../core/utils/logger.dart';

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
  @override
  final int version;

  OrdonnanceModel({
    required this.id,
    required this.patientName,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.isSynced = false,
    this.version = 1,
  });

  factory OrdonnanceModel.fromJson(Map<String, dynamic> json) {
    try {
      // Vérifier que les champs obligatoires sont présents
      if (json['id'] == null ||
          json['patientName'] == null ||
          json['createdBy'] == null ||
          json['createdAt'] == null ||
          json['updatedAt'] == null) {
        throw const FormatException('Missing required fields in OrdonnanceModel.fromJson');
      }

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
        version: json['version'] ?? 1,
      );
    } catch (e) {
      AppLogger.error('Error parsing OrdonnanceModel from JSON', e);
      // Retourner un modèle par défaut ou null
      rethrow; // Ou gérer différemment
    }
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
      'version': version,
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
    int? version,
  }) {
    return OrdonnanceModel(
      id: id ?? this.id,
      patientName: patientName ?? this.patientName,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
      version: version ?? this.version,
    );
  }

  // Méthode pour incrémenter la version
  OrdonnanceModel incrementVersion() {
    return copyWith(version: version + 1, updatedAt: DateTime.now());
  }
}
