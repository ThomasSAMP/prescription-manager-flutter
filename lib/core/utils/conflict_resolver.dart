import 'dart:math' as math;

import '../models/syncable_model.dart';
import 'logger.dart';
import 'model_merger.dart';

enum ConflictResolutionStrategy {
  // La version la plus récente gagne toujours
  newerWins,

  // La version du serveur gagne toujours
  serverWins,

  // La version locale gagne toujours
  clientWins,

  // Fusionner les modifications si possible, sinon utiliser newerWins
  mergeOrNewerWins,
}

class ConflictResolver {
  final ConflictResolutionStrategy strategy;

  ConflictResolver({this.strategy = ConflictResolutionStrategy.newerWins});

  /// Détecte s'il y a un conflit entre deux versions d'un modèle
  bool hasConflict<T extends SyncableModel>(T local, T remote) {
    // Si les versions sont différentes, il y a un conflit potentiel
    return local.version != remote.version;
  }

  /// Résout un conflit entre deux versions d'un modèle
  T resolve<T extends SyncableModel>(T local, T remote) {
    if (!hasConflict(local, remote)) {
      // Pas de conflit, retourner la version locale
      return local;
    }

    AppLogger.info(
      'Resolving conflict for ${local.id}: local version ${local.version}, remote version ${remote.version}',
    );

    switch (strategy) {
      case ConflictResolutionStrategy.newerWins:
        // La version la plus récente gagne
        if (local.updatedAt.isAfter(remote.updatedAt)) {
          AppLogger.debug('Local version is newer, keeping local');
          return local;
        } else {
          AppLogger.debug('Remote version is newer, using remote');
          return remote;
        }

      case ConflictResolutionStrategy.serverWins:
        // La version du serveur gagne toujours
        AppLogger.debug('Using server version as per strategy');
        return remote;

      case ConflictResolutionStrategy.clientWins:
        // La version locale gagne toujours
        AppLogger.debug('Using local version as per strategy');
        return local;

      case ConflictResolutionStrategy.mergeOrNewerWins:
        // Tenter de fusionner les modifications
        AppLogger.debug('Attempting to merge changes');
        try {
          return ModelMerger.merge(local, remote);
        } catch (e) {
          AppLogger.error('Failed to merge changes, falling back to newerWins', e);
          // En cas d'échec, utiliser newerWins comme fallback
          if (local.updatedAt.isAfter(remote.updatedAt)) {
            return local.copyWith(version: math.max(local.version, remote.version) + 1) as T;
          } else {
            return remote.copyWith(version: math.max(local.version, remote.version) + 1) as T;
          }
        }
    }
  }
}
