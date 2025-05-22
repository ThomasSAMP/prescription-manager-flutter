import 'dart:math' as math;

import '../../features/prescriptions/models/medicament_model.dart';
import '../../features/prescriptions/models/ordonnance_model.dart';
import '../models/syncable_model.dart';

class ModelMerger {
  /// Fusionne deux versions d'un modèle
  static T merge<T extends SyncableModel>(T local, T remote) {
    if (local is OrdonnanceModel && remote is OrdonnanceModel) {
      return _mergeOrdonnance(local, remote) as T;
    } else if (local is MedicamentModel && remote is MedicamentModel) {
      return _mergeMedicament(local, remote) as T;
    } else {
      // Pour les autres types, utiliser la version la plus récente
      if (local.updatedAt.isAfter(remote.updatedAt)) {
        return local;
      } else {
        return remote;
      }
    }
  }

  /// Fusionne deux versions d'une ordonnance
  static OrdonnanceModel _mergeOrdonnance(OrdonnanceModel local, OrdonnanceModel remote) {
    // Pour une ordonnance, nous prenons la version la plus récente du nom du patient
    // et conservons les autres champs de la version la plus récente
    if (local.updatedAt.isAfter(remote.updatedAt)) {
      // La version locale est plus récente
      return local.incrementVersion();
    } else {
      // La version distante est plus récente
      return remote.incrementVersion();
    }
  }

  /// Fusionne deux versions d'un médicament
  static MedicamentModel _mergeMedicament(MedicamentModel local, MedicamentModel remote) {
    // Pour un médicament, nous pouvons fusionner les champs individuellement
    // en prenant les valeurs les plus récentes
    final updatedAt =
        local.updatedAt.isAfter(remote.updatedAt) ? local.updatedAt : remote.updatedAt;

    // Prendre la date d'expiration la plus récente
    final expirationDate =
        local.updatedAt.isAfter(remote.updatedAt) ? local.expirationDate : remote.expirationDate;

    // Prendre le dosage le plus récent
    final dosage = local.updatedAt.isAfter(remote.updatedAt) ? local.dosage : remote.dosage;

    // Prendre les instructions les plus récentes
    final instructions =
        local.updatedAt.isAfter(remote.updatedAt) ? local.instructions : remote.instructions;

    // Prendre le nom le plus récent
    final name = local.updatedAt.isAfter(remote.updatedAt) ? local.name : remote.name;

    return MedicamentModel(
      id: local.id,
      ordonnanceId: local.ordonnanceId,
      name: name,
      expirationDate: expirationDate,
      dosage: dosage,
      instructions: instructions,
      createdAt: local.createdAt,
      updatedAt: updatedAt,
      version: math.max(local.version, remote.version) + 1, // Incrémenter la version la plus élevée
      isSynced: false,
    );
  }
}
