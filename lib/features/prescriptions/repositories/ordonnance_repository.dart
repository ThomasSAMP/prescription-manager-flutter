import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/syncable_model.dart';
import '../../../core/repositories/offline_repository_base.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/encryption_service.dart';
import '../../../core/services/local_storage_service.dart';
import '../../../core/services/unified_cache_service.dart';
import '../../../core/utils/conflict_resolver.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/model_merger.dart';
import '../../../shared/widgets/conflict_resolution_dialog.dart';
import '../models/ordonnance_model.dart';

@lazySingleton
class OrdonnanceRepository extends OfflineRepositoryBase<OrdonnanceModel> {
  final FirebaseFirestore _firestore;
  final EncryptionService _encryptionService;
  final UnifiedCacheService _unifiedCache;
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
    this._unifiedCache,
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
      await addPendingOperation(
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
      await addPendingOperation(
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

      await addPendingOperation(
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
      // 1. Essayer le cache unifié (données DÉJÀ déchiffrées)
      final cachedOrdonnances = await _unifiedCache.get<OrdonnanceListModel>(
        _cacheKey,
        OrdonnanceListModel.fromJson,
      );

      if (cachedOrdonnances != null) {
        // ✅ Les données du cache sont DÉJÀ déchiffrées
        AppLogger.debug(
          'Using unified cache for ordonnances (${cachedOrdonnances.ordonnances.length} items)',
        );
        return cachedOrdonnances.ordonnances; // PAS de déchiffrement ici
      }

      // 2. Charger depuis la source de données (données chiffrées)
      List<OrdonnanceModel> ordonnances;

      if (connectivityService.currentStatus == ConnectionStatus.online) {
        ordonnances = await loadAllFromRemote();

        await localStorageService.saveModelList<OrdonnanceModel>(
          storageKey,
          ordonnances.map((o) => o.copyWith(isSynced: true)).toList(),
        );

        AppLogger.debug('Loaded ${ordonnances.length} ordonnances from Firestore');
      } else {
        ordonnances = loadAllLocally();
        AppLogger.debug('Loaded ${ordonnances.length} ordonnances from local storage');
      }

      // 3. Déchiffrer une seule fois
      final decryptedOrdonnances = _decryptOrdonnances(ordonnances);

      // 4. Sauvegarder dans le cache unifié (données déchiffrées)
      await _saveToUnifiedCache(decryptedOrdonnances);

      return decryptedOrdonnances;
    } catch (e) {
      AppLogger.error('Error getting ordonnances', e);
      return _handleErrorFallback();
    }
  }

  // Obtenir une ordonnance spécifique avec cache individuel
  Future<OrdonnanceModel?> getOrdonnanceById(String ordonnanceId) async {
    try {
      final cacheKey = '${_cacheKey}_$ordonnanceId';

      // 1. Essayer le cache unifié
      final cachedOrdonnance = await _unifiedCache.get<OrdonnanceModel>(
        cacheKey,
        OrdonnanceModel.fromJson,
      );

      if (cachedOrdonnance != null) {
        final decrypted = _decryptOrdonnances([cachedOrdonnance]).first;
        AppLogger.debug('Using unified cache for ordonnance: $ordonnanceId');
        return decrypted;
      }

      // 2. Charger depuis la source de données
      OrdonnanceModel? ordonnance;

      if (connectivityService.currentStatus == ConnectionStatus.online) {
        final doc = await _ordonnancesCollection.doc(ordonnanceId).get();
        if (doc.exists) {
          final data = Map<String, dynamic>.from(doc.data()!);
          data['id'] = doc.id;
          ordonnance = OrdonnanceModel.fromJson(data);

          // Sauvegarder localement
          await saveLocally(ordonnance.copyWith(isSynced: true));
        }
      } else {
        // Mode hors ligne
        final allOrdonnances = loadAllLocally();
        ordonnance = allOrdonnances.firstWhere(
          (o) => o.id == ordonnanceId,
          orElse: () => null as OrdonnanceModel,
        );
      }

      if (ordonnance != null) {
        final decrypted = _decryptOrdonnances([ordonnance]).first;

        // Sauvegarder dans le cache unifié
        await _unifiedCache.put(
          cacheKey,
          decrypted,
          ttl: const Duration(hours: 1),
          level: CacheLevel.both,
        );

        return decrypted;
      }

      return null;
    } catch (e) {
      AppLogger.error('Error getting ordonnance by ID: $ordonnanceId', e);

      // Fallback vers le stockage local
      final allOrdonnances = loadAllLocally();
      final ordonnance = allOrdonnances.firstWhere(
        (o) => o.id == ordonnanceId,
        orElse: () => null as OrdonnanceModel,
      );

      return ordonnance != null ? _decryptOrdonnances([ordonnance]).first : null;
    }
  }

  // Déchiffrer les noms des patients dans les ordonnances
  List<OrdonnanceModel> _decryptOrdonnances(List<OrdonnanceModel> ordonnances) {
    return ordonnances.map((ordonnance) {
      try {
        // Vérifier si les données sont déjà déchiffrées
        if (_isAlreadyDecrypted(ordonnance.patientName)) {
          AppLogger.debug('Data already decrypted for ordonnance: ${ordonnance.id}');
          return ordonnance;
        }

        final decryptedPatientName = _encryptionService.decrypt(ordonnance.patientName);
        return ordonnance.copyWith(patientName: decryptedPatientName);
      } catch (e) {
        AppLogger.error('Error decrypting patient name for ordonnance ${ordonnance.id}', e);
        return ordonnance;
      }
    }).toList();
  }

  // Méthode pour vérifier si les données sont déjà déchiffrées
  bool _isAlreadyDecrypted(String data) {
    try {
      base64.decode(data);
      return false; // C'est du base64 valide, donc chiffré
    } catch (e) {
      return true; // Pas du base64, donc déjà déchiffré
    }
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

  // Méthode pour sauvegarder dans le cache unifié
  Future<void> _saveToUnifiedCache(List<OrdonnanceModel> ordonnances) async {
    try {
      // Créer un modèle wrapper pour la liste
      final cacheData = OrdonnanceListModel(ordonnances: ordonnances, lastUpdated: DateTime.now());

      await _unifiedCache.put(
        _cacheKey,
        cacheData,
        ttl: const Duration(hours: 2), // Cache plus long pour les ordonnances
        level: CacheLevel.both,
        strategy: InvalidationStrategy.smart,
      );

      AppLogger.debug('Saved ${ordonnances.length} ordonnances to unified cache');
    } catch (e) {
      AppLogger.error('Error saving ordonnances to unified cache', e);
    }
  }

  // Fallback en cas d'erreur
  Future<List<OrdonnanceModel>> _handleErrorFallback() async {
    try {
      // 1. Essayer le stockage local (données chiffrées)
      final localOrdonnances = loadAllLocally();
      if (localOrdonnances.isNotEmpty) {
        final decrypted = _decryptOrdonnances(localOrdonnances);
        AppLogger.debug('Using local storage fallback: ${decrypted.length} ordonnances');
        return decrypted;
      }

      // 2. Essayer le cache périmé (données DÉJÀ déchiffrées)
      final staleCache = await _unifiedCache.get<OrdonnanceListModel>(
        _cacheKey,
        OrdonnanceListModel.fromJson,
        updateAccess: false,
      );

      if (staleCache != null) {
        AppLogger.warning(
          'Using stale cache as fallback: ${staleCache.ordonnances.length} ordonnances',
        );
        return staleCache.ordonnances; // PAS de déchiffrement ici
      }

      return [];
    } catch (e) {
      AppLogger.error('Error in fallback handling', e);
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

      // Invalider le cache après modification
      await invalidateCache();
    } catch (e) {
      AppLogger.error('Error saving ordonnance to Firestore', e);
      rethrow;
    }
  }

  @override
  Future<void> deleteFromRemote(String id) async {
    try {
      await _ordonnancesCollection.doc(id).delete();

      // Invalider le cache après suppression
      await invalidateCache();

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
      await addPendingOperation(
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

  // Invalider le cache lors des modifications
  Future<void> invalidateCache() async {
    try {
      // Invalider tous les caches liés aux ordonnances
      await _unifiedCache.invalidatePattern('$_cacheKey*');
      AppLogger.debug('Invalidated ordonnances cache');
    } catch (e) {
      AppLogger.error('Error invalidating ordonnances cache', e);
    }
  }
}

// Modèle wrapper pour la liste d'ordonnances dans le cache
class OrdonnanceListModel implements SyncableModel {
  final List<OrdonnanceModel> ordonnances;
  final DateTime lastUpdated;

  OrdonnanceListModel({required this.ordonnances, required this.lastUpdated});

  @override
  String get id => 'ordonnances_list';

  @override
  bool get isSynced => true;

  @override
  DateTime get createdAt => lastUpdated;

  @override
  DateTime get updatedAt => lastUpdated;

  @override
  int get version => 1;

  @override
  Map<String, dynamic> toJson() {
    return {
      'ordonnances':
          ordonnances
              .map(
                (o) => {
                  'id': o.id,
                  'patientName': o.patientName, // ✅ Stocké déchiffré dans le cache
                  'createdBy': o.createdBy,
                  'createdAt': o.createdAt.toIso8601String(),
                  'updatedAt': o.updatedAt.toIso8601String(),
                  'isSynced': o.isSynced,
                  'version': o.version,
                },
              )
              .toList(),
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }

  factory OrdonnanceListModel.fromJson(Map<String, dynamic> json) {
    return OrdonnanceListModel(
      ordonnances:
          (json['ordonnances'] as List)
              .map(
                (o) => OrdonnanceModel(
                  id: o['id'],
                  patientName: o['patientName'], // ✅ Déjà déchiffré depuis le cache
                  createdBy: o['createdBy'],
                  createdAt: DateTime.parse(o['createdAt']),
                  updatedAt: DateTime.parse(o['updatedAt']),
                  isSynced: o['isSynced'],
                  version: o['version'],
                ),
              )
              .toList(),
      lastUpdated: DateTime.parse(json['lastUpdated']),
    );
  }

  @override
  SyncableModel copyWith({bool? isSynced, int? version}) {
    return this; // Immutable pour le cache
  }
}
