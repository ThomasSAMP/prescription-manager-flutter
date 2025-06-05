import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

import '../../../core/repositories/offline_repository_base.dart';
import '../../../core/services/cache_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/encryption_service.dart';
import '../../../core/services/local_storage_service.dart';
import '../../../core/utils/conflict_resolver.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/model_merger.dart';
import '../../../shared/widgets/conflict_resolution_dialog.dart';
import '../models/ordonnance_model.dart';

@lazySingleton
class OrdonnanceRepository extends OfflineRepositoryBase<OrdonnanceModel> {
  final FirebaseFirestore _firestore;
  final EncryptionService _encryptionService;
  final CacheService _cacheService;
  final Uuid _uuid = const Uuid();

  static const String _cacheKey = 'ordonnances';

  final ConflictResolver _conflictResolver = ConflictResolver(
    strategy: ConflictResolutionStrategy.newerWins,
  );

  CollectionReference<Map<String, dynamic>> get _ordonnancesCollection =>
      _firestore.collection('ordonnances');

  OrdonnanceRepository(
    this._firestore,
    this._encryptionService,
    this._cacheService,
    LocalStorageService localStorageService,
    ConnectivityService connectivityService,
  ) : super(
        connectivityService: connectivityService,
        localStorageService: localStorageService,
        storageKey: 'offline_ordonnances',
        pendingOperationsKey: 'pending_ordonnance_operations',
        fromJson: OrdonnanceModel.fromJson,
      );

  // Créer une nouvelle ordonnance
  Future<OrdonnanceModel> createOrdonnance(String patientName, String userId) async {
    // Chiffrer le nom du patient
    final encryptedPatientName = _encryptionService.encrypt(patientName);

    final ordonnance = OrdonnanceModel(
      id: _uuid.v4(),
      patientName: encryptedPatientName,
      createdBy: userId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isSynced: false,
      version: 1, // Version initiale
    );

    // Sauvegarder localement
    await saveLocally(ordonnance);

    // Invalider le cache
    invalidateCache();

    // Si nous sommes en ligne, synchroniser avec le serveur
    if (connectivityService.currentStatus == ConnectionStatus.online) {
      await saveToRemote(ordonnance);
    } else {
      // Sinon, ajouter à la file d'attente des opérations en attente
      addPendingOperation(
        PendingOperation<OrdonnanceModel>(
          type: OperationType.create,
          data: ordonnance,
          execute: () => saveToRemote(ordonnance),
        ),
      );

      // Sauvegarder les opérations en attente
      await savePendingOperations();
    }

    return ordonnance;
  }

  // Mettre à jour une ordonnance existante
  Future<OrdonnanceModel> updateOrdonnance(
    OrdonnanceModel ordonnance, {
    String? newPatientName,
  }) async {
    // Si le nom du patient est fourni, le chiffrer
    final updatedOrdonnance = ordonnance.copyWith(
      patientName: newPatientName != null ? _encryptionService.encrypt(newPatientName) : null,
      updatedAt: DateTime.now(),
      isSynced: false,
      // Ne pas incrémenter la version ici, cela sera fait lors de la sauvegarde sur le serveur
    );

    // Sauvegarder localement
    await saveLocally(updatedOrdonnance);

    // Invalider le cache
    invalidateCache();

    // Si nous sommes en ligne, synchroniser avec le serveur
    if (connectivityService.currentStatus == ConnectionStatus.online) {
      await saveToRemote(updatedOrdonnance);
    } else {
      // Sinon, ajouter à la file d'attente des opérations en attente
      addPendingOperation(
        PendingOperation<OrdonnanceModel>(
          type: OperationType.update,
          data: updatedOrdonnance,
          execute: () => saveToRemote(updatedOrdonnance),
        ),
      );

      // Sauvegarder les opérations en attente
      await savePendingOperations();
    }

    return updatedOrdonnance;
  }

  // Supprimer une ordonnance
  Future<void> deleteOrdonnance(String ordonnanceId) async {
    // Supprimer localement
    await deleteLocally(ordonnanceId);

    // Invalider le cache
    invalidateCache();

    // Si nous sommes en ligne, supprimer du serveur
    if (connectivityService.currentStatus == ConnectionStatus.online) {
      await deleteFromRemote(ordonnanceId);
    } else {
      // Sinon, ajouter à la file d'attente des opérations en attente
      final ordonnances = loadAllLocally();
      final ordonnanceToDelete = ordonnances.firstWhere(
        (ordonnance) => ordonnance.id == ordonnanceId,
        orElse:
            () => OrdonnanceModel(
              id: ordonnanceId,
              patientName: '',
              createdBy: '',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
      );

      addPendingOperation(
        PendingOperation<OrdonnanceModel>(
          type: OperationType.delete,
          data: ordonnanceToDelete,
          execute: () => deleteFromRemote(ordonnanceId),
        ),
      );

      // Sauvegarder les opérations en attente
      await savePendingOperations();
    }
  }

  // Obtenir toutes les ordonnances sans pagination
  Future<List<OrdonnanceModel>> getOrdonnances() async {
    try {
      // Vérifier le cache unifié
      if (_cacheService.isCacheValid(_cacheKey)) {
        final cachedOrdonnances = _cacheService.getFromCache<OrdonnanceModel>(_cacheKey);
        AppLogger.debug(
          'Using in-memory cache for ordonnances (${cachedOrdonnances.length} items)',
        );
        return cachedOrdonnances;
      }

      List<OrdonnanceModel> ordonnances;

      // Si nous sommes en ligne, essayer de récupérer depuis Firestore
      if (connectivityService.currentStatus == ConnectionStatus.online) {
        ordonnances = await loadAllFromRemote();

        // Sauvegarder dans le stockage local en une seule opération
        await localStorageService.saveModelList<OrdonnanceModel>(
          storageKey,
          ordonnances.map((o) => o.copyWith(isSynced: true)).toList(),
        );

        AppLogger.debug(
          'Loaded ${ordonnances.length} ordonnances from remote and saved to local storage',
        );
      } else {
        // Sinon, charger depuis le stockage local
        ordonnances = loadAllLocally();
        AppLogger.debug('Loaded ${ordonnances.length} ordonnances from local storage');
      }

      // Déchiffrer et mettre en cache
      final decryptedOrdonnances = _decryptOrdonnances(ordonnances);
      _cacheService.updateCache(_cacheKey, decryptedOrdonnances);

      return decryptedOrdonnances;
    } catch (e) {
      AppLogger.error('Error getting ordonnances', e);

      // En cas d'erreur, essayer le cache puis le stockage local
      final cachedOrdonnances = _cacheService.getFromCache<OrdonnanceModel>(_cacheKey);
      if (cachedOrdonnances.isNotEmpty) {
        AppLogger.debug('Using stale cache after error');
        return cachedOrdonnances;
      }

      // Dernier recours : stockage local
      final ordonnances = loadAllLocally();
      final decryptedOrdonnances = _decryptOrdonnances(ordonnances);
      _cacheService.updateCache(_cacheKey, decryptedOrdonnances);

      return decryptedOrdonnances;
    }
  }

  Future<OrdonnanceModel?> getOrdonnanceById(String ordonnanceId) async {
    try {
      // Si nous sommes en ligne, essayer de récupérer depuis Firestore
      if (connectivityService.currentStatus == ConnectionStatus.online) {
        final doc = await _ordonnancesCollection.doc(ordonnanceId).get();

        if (!doc.exists) {
          return null;
        }

        final data = Map<String, dynamic>.from(doc.data()!);
        data['id'] = doc.id;

        final ordonnance = OrdonnanceModel.fromJson(data);

        // Sauvegarder dans le stockage local
        await saveLocally(ordonnance.copyWith(isSynced: true));

        return _decryptOrdonnances([ordonnance]).first;
      } else {
        // En mode hors ligne, charger depuis le stockage local
        final allOrdonnances = loadAllLocally();
        final filteredOrdonnances = allOrdonnances.where((o) => o.id == ordonnanceId).toList();

        if (filteredOrdonnances.isEmpty) {
          return null;
        }

        return _decryptOrdonnances(filteredOrdonnances).first;
      }
    } catch (e) {
      AppLogger.error('Error getting ordonnance by ID: $ordonnanceId', e);

      // En cas d'erreur, essayer de charger depuis le stockage local
      final allOrdonnances = loadAllLocally();
      final filteredOrdonnances = allOrdonnances.where((o) => o.id == ordonnanceId).toList();

      if (filteredOrdonnances.isEmpty) {
        return null;
      }

      return _decryptOrdonnances(filteredOrdonnances).first;
    }
  }

  Future<List<OrdonnanceModel>> getOrdonnancesWithoutPagination() async {
    try {
      if (connectivityService.currentStatus == ConnectionStatus.online) {
        // En ligne: charger depuis Firestore sans limite
        final snapshot = await _firestore.collection('ordonnances').get();

        final ordonnances =
            snapshot.docs.map((doc) {
              final data = Map<String, dynamic>.from(doc.data());
              data['id'] = doc.id;
              return OrdonnanceModel.fromJson(data);
            }).toList();

        // Mettre à jour le stockage local
        for (final ordonnance in ordonnances) {
          await saveLocally(ordonnance.copyWith(isSynced: true));
        }

        AppLogger.debug(
          'Loaded ${ordonnances.length} ordonnances from Firestore without pagination',
        );

        return _decryptOrdonnances(ordonnances);
      } else {
        // Hors ligne: charger depuis le stockage local
        final ordonnances = loadAllLocally();
        AppLogger.debug('Loaded ${ordonnances.length} ordonnances from local storage');
        return _decryptOrdonnances(ordonnances);
      }
    } catch (e) {
      AppLogger.error('Error getting ordonnances without pagination', e);
      // En cas d'erreur, essayer de charger depuis le stockage local
      final ordonnances = loadAllLocally();
      return _decryptOrdonnances(ordonnances);
    }
  }

  // Déchiffrer les noms des patients dans les ordonnances
  List<OrdonnanceModel> _decryptOrdonnances(List<OrdonnanceModel> ordonnances) {
    return ordonnances.map((ordonnance) {
      try {
        final decryptedPatientName = _encryptionService.decrypt(ordonnance.patientName);
        return ordonnance.copyWith(patientName: decryptedPatientName);
      } catch (e) {
        AppLogger.error('Error decrypting patient name', e);
        return ordonnance;
      }
    }).toList();
  }

  Future<int?> getTotalOrdonnancesCount() async {
    try {
      if (connectivityService.currentStatus == ConnectionStatus.online) {
        // En ligne: obtenir le nombre depuis Firestore
        final snapshot = await _firestore.collection('ordonnances').count().get();
        final count = snapshot.count;

        AppLogger.debug('Got total ordonnances count from Firestore: $count');
        return count;
      } else {
        // Hors ligne: compter les ordonnances locales
        final localOrdonnances = loadAllLocally();
        return localOrdonnances.length;
      }
    } catch (e) {
      AppLogger.error('Error getting total ordonnances count', e);

      // En cas d'erreur, essayer de compter les ordonnances locales
      try {
        final localOrdonnances = loadAllLocally();
        return localOrdonnances.length;
      } catch (_) {
        // Si tout échoue, retourner une estimation (par exemple, 100)
        // ou retourner le nombre d'éléments actuellement chargés
        return 0;
      }
    }
  }

  Future<List<OrdonnanceModel>> getOrdonnancesPaginated({
    int limit = 10,
    String? lastOrdonnanceId,
  }) async {
    try {
      if (connectivityService.currentStatus == ConnectionStatus.online) {
        var query = _ordonnancesCollection.orderBy('updatedAt', descending: true).limit(limit);

        if (lastOrdonnanceId != null) {
          // Obtenir le document pour le cursor
          final lastDocSnapshot = await _ordonnancesCollection.doc(lastOrdonnanceId).get();
          if (lastDocSnapshot.exists) {
            query = query.startAfterDocument(lastDocSnapshot);
          }
        }

        final snapshot = await query.get();
        final ordonnances =
            snapshot.docs.map((doc) {
              final data = Map<String, dynamic>.from(doc.data());
              data['id'] = doc.id;
              return OrdonnanceModel.fromJson(data);
            }).toList();

        // Sauvegarder dans le cache local
        for (final ordonnance in ordonnances) {
          await saveLocally(ordonnance.copyWith(isSynced: true));
        }

        return _decryptOrdonnances(ordonnances);
      } else {
        // En mode hors ligne, charger depuis le stockage local
        // mais simuler la pagination
        final allOrdonnances = loadAllLocally();
        final decryptedOrdonnances = _decryptOrdonnances(allOrdonnances);

        // Trier par date de mise à jour
        decryptedOrdonnances.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        // Appliquer la pagination
        var startIndex = 0;
        if (lastOrdonnanceId != null) {
          final lastIndex = decryptedOrdonnances.indexWhere((o) => o.id == lastOrdonnanceId);
          if (lastIndex != -1) {
            startIndex = lastIndex + 1;
          }
        }

        final endIndex = startIndex + limit;
        if (startIndex >= decryptedOrdonnances.length) {
          return [];
        }

        return decryptedOrdonnances.sublist(
          startIndex,
          endIndex < decryptedOrdonnances.length ? endIndex : decryptedOrdonnances.length,
        );
      }
    } catch (e) {
      AppLogger.error('Error getting paginated ordonnances', e);
      return [];
    }
  }

  @override
  Future<void> saveToRemote(OrdonnanceModel ordonnance) async {
    try {
      // Vérifier si l'ordonnance existe déjà sur le serveur
      final docRef = _ordonnancesCollection.doc(ordonnance.id);
      final docSnapshot = await docRef.get();

      if (docSnapshot.exists) {
        // L'ordonnance existe déjà, vérifier s'il y a un conflit
        final remoteData = docSnapshot.data()!;
        remoteData['id'] = docSnapshot.id;
        final remoteOrdonnance = OrdonnanceModel.fromJson(remoteData);

        if (_conflictResolver.hasConflict(ordonnance, remoteOrdonnance)) {
          // Il y a un conflit, le résoudre
          final resolvedOrdonnance = _conflictResolver.resolve(ordonnance, remoteOrdonnance);

          // Incrémenter la version et sauvegarder
          final updatedOrdonnance = resolvedOrdonnance.incrementVersion().copyWith(isSynced: true);
          await docRef.set(updatedOrdonnance.toJson());

          // Mettre à jour le stockage local avec l'ordonnance résolue
          await saveLocally(updatedOrdonnance);

          AppLogger.info('Conflict resolved and saved for ordonnance: ${ordonnance.id}');
        } else {
          // Pas de conflit, incrémenter la version et sauvegarder
          final updatedOrdonnance = ordonnance.incrementVersion().copyWith(isSynced: true);
          await docRef.set(updatedOrdonnance.toJson());

          // Mettre à jour le stockage local
          await saveLocally(updatedOrdonnance);

          AppLogger.debug('Ordonnance updated without conflict: ${ordonnance.id}');
        }
      } else {
        // L'ordonnance n'existe pas encore, la sauvegarder
        final updatedOrdonnance = ordonnance.copyWith(isSynced: true);
        await docRef.set(updatedOrdonnance.toJson());

        // Mettre à jour le stockage local
        await saveLocally(updatedOrdonnance);

        AppLogger.debug('New ordonnance saved to Firestore: ${ordonnance.id}');
      }
    } catch (e) {
      AppLogger.error('Error saving ordonnance to Firestore', e);
      rethrow;
    }
  }

  @override
  Future<void> deleteFromRemote(String id) async {
    try {
      await _ordonnancesCollection.doc(id).delete();
      AppLogger.debug('Ordonnance deleted from Firestore: $id');
    } catch (e) {
      AppLogger.error('Error deleting ordonnance from Firestore', e);
      rethrow;
    }
  }

  @override
  Future<List<OrdonnanceModel>> loadAllFromRemote() async {
    try {
      final snapshot = await _ordonnancesCollection.get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return OrdonnanceModel.fromJson(data);
      }).toList();
    } catch (e) {
      AppLogger.error('Error loading ordonnances from Firestore', e);
      rethrow;
    }
  }

  /// Résout manuellement un conflit entre deux versions d'une ordonnance
  Future<OrdonnanceModel> resolveConflictManually(
    OrdonnanceModel local,
    OrdonnanceModel remote,
    ConflictChoice choice,
  ) async {
    OrdonnanceModel resolvedOrdonnance;

    switch (choice) {
      case ConflictChoice.useLocal:
        resolvedOrdonnance = local.incrementVersion();
        break;
      case ConflictChoice.useRemote:
        resolvedOrdonnance = remote.incrementVersion();
        break;
      case ConflictChoice.merge:
        resolvedOrdonnance = ModelMerger.merge(local, remote);
        break;
    }

    // Sauvegarder l'ordonnance résolue
    resolvedOrdonnance = resolvedOrdonnance.copyWith(updatedAt: DateTime.now(), isSynced: false);

    // Sauvegarder localement
    await saveLocally(resolvedOrdonnance);

    // Si nous sommes en ligne, synchroniser avec le serveur
    if (connectivityService.currentStatus == ConnectionStatus.online) {
      await saveToRemote(resolvedOrdonnance);
    } else {
      // Sinon, ajouter à la file d'attente des opérations en attente
      addPendingOperation(
        PendingOperation<OrdonnanceModel>(
          type: OperationType.update,
          data: resolvedOrdonnance,
          execute: () => saveToRemote(resolvedOrdonnance),
        ),
      );

      // Sauvegarder les opérations en attente
      await savePendingOperations();
    }

    // Invalider le cache
    invalidateCache();

    return resolvedOrdonnance;
  }

  void invalidateCache() {
    _cacheService.invalidateCache(_cacheKey);
  }
}
