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
import '../models/medicament_model.dart';

@lazySingleton
class MedicamentRepository extends OfflineRepositoryBase<MedicamentModel> {
  final FirebaseFirestore _firestore;
  final EncryptionService _encryptionService;
  final UnifiedCacheService _unifiedCache;
  final Uuid _uuid = const Uuid();

  static const String _cacheKey = 'medicaments';
  static const String _cacheKeyByOrdonnance = 'medicaments_by_ordonnance';

  final ConflictResolver _conflictResolver = ConflictResolver(
    strategy: ConflictResolutionStrategy.newerWins,
  );

  CollectionReference<Map<String, dynamic>> get _medicamentsCollection =>
      _firestore.collection('medicaments');

  MedicamentRepository(
    this._firestore,
    this._encryptionService,
    this._unifiedCache, // Nouveau service unifié
    LocalStorageService localStorageService,
    ConnectivityService connectivityService,
  ) : super(
        connectivityService: connectivityService,
        localStorageService: localStorageService,
        storageKey: 'offline_medicaments',
        pendingOperationsKey: 'pending_medicament_operations',
        fromJson: MedicamentModel.fromJson,
      );

  // Créer un nouveau médicament
  Future<MedicamentModel> createMedicament({
    required String ordonnanceId,
    required String name,
    required DateTime expirationDate,
    String? dosage,
    String? instructions,
  }) async {
    // Chiffrer les données sensibles
    final encryptedName = _encryptionService.encrypt(name);
    final encryptedDosage = dosage != null ? _encryptionService.encrypt(dosage) : null;
    final encryptedInstructions =
        instructions != null ? _encryptionService.encrypt(instructions) : null;

    final medicament = MedicamentModel(
      id: _uuid.v4(),
      ordonnanceId: ordonnanceId,
      name: encryptedName,
      expirationDate: expirationDate,
      dosage: encryptedDosage,
      instructions: encryptedInstructions,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isSynced: false,
      version: 1, // Version initiale
    );

    // Sauvegarder localement
    await saveLocally(medicament);

    // Invalider le cache
    invalidateCache();

    // Si nous sommes en ligne, synchroniser avec le serveur
    if (connectivityService.currentStatus == ConnectionStatus.online) {
      await saveToRemote(medicament);
    } else {
      // Sinon, ajouter à la file d'attente des opérations en attente
      await addPendingOperation(
        PendingOperation<MedicamentModel>(
          type: OperationType.create,
          data: medicament,
          execute: () => saveToRemote(medicament),
        ),
      );

      // Sauvegarder les opérations en attente
      await savePendingOperations();
    }

    return medicament;
  }

  // Mettre à jour un médicament existant
  Future<MedicamentModel> updateMedicament({
    required MedicamentModel medicament,
    String? newName,
    DateTime? newExpirationDate,
    String? newDosage,
    String? newInstructions,
  }) async {
    // Chiffrer les nouvelles données si elles sont fournies
    final encryptedName = newName != null ? _encryptionService.encrypt(newName) : null;
    final encryptedDosage = newDosage != null ? _encryptionService.encrypt(newDosage) : null;
    final encryptedInstructions =
        newInstructions != null ? _encryptionService.encrypt(newInstructions) : null;

    final updatedMedicament = medicament.copyWith(
      name: encryptedName,
      expirationDate: newExpirationDate,
      dosage: encryptedDosage,
      instructions: encryptedInstructions,
      updatedAt: DateTime.now(),
      isSynced: false,
      // Ne pas incrémenter la version ici, cela sera fait lors de la sauvegarde sur le serveur
    );

    // Sauvegarder localement
    await saveLocally(updatedMedicament);

    // Invalider le cache
    invalidateCache();

    // Si nous sommes en ligne, synchroniser avec le serveur
    if (connectivityService.currentStatus == ConnectionStatus.online) {
      await saveToRemote(updatedMedicament);
    } else {
      // Sinon, ajouter à la file d'attente des opérations en attente
      await addPendingOperation(
        PendingOperation<MedicamentModel>(
          type: OperationType.update,
          data: updatedMedicament,
          execute: () => saveToRemote(updatedMedicament),
        ),
      );

      // Sauvegarder les opérations en attente
      await savePendingOperations();
    }

    return updatedMedicament;
  }

  // Supprimer un médicament
  Future<void> deleteMedicament(String medicamentId) async {
    // Supprimer localement
    await deleteLocally(medicamentId);

    // Invalider le cache
    invalidateCache();

    // Si nous sommes en ligne, supprimer du serveur
    if (connectivityService.currentStatus == ConnectionStatus.online) {
      await deleteFromRemote(medicamentId);
    } else {
      // Sinon, ajouter à la file d'attente des opérations en attente
      final medicaments = loadAllLocally();
      final medicamentToDelete = medicaments.firstWhere(
        (medicament) => medicament.id == medicamentId,
        orElse:
            () => MedicamentModel(
              id: medicamentId,
              ordonnanceId: '',
              name: '',
              expirationDate: DateTime.now(),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
      );

      await addPendingOperation(
        PendingOperation<MedicamentModel>(
          type: OperationType.delete,
          data: medicamentToDelete,
          execute: () => deleteFromRemote(medicamentId),
        ),
      );

      // Sauvegarder les opérations en attente
      await savePendingOperations();
    }
  }

  // Méthode pour obtenir tous les médicaments
  Future<List<MedicamentModel>> getAllMedicaments() async {
    try {
      // 1. Essayer le cache unifié (données DÉJÀ déchiffrées)
      final cachedMedicaments = await _unifiedCache.get<MedicamentListModel>(
        _cacheKey,
        MedicamentListModel.fromJson,
      );

      if (cachedMedicaments != null) {
        // ✅ Les données du cache sont DÉJÀ déchiffrées
        AppLogger.debug(
          'Using unified cache for medicaments (${cachedMedicaments.medicaments.length} items)',
        );
        return cachedMedicaments.medicaments; // PAS de déchiffrement ici
      }

      // 2. Charger depuis la source de données (données chiffrées)
      List<MedicamentModel> medicaments;

      if (connectivityService.currentStatus == ConnectionStatus.online) {
        // En ligne : charger depuis Firestore (données chiffrées)
        medicaments = await loadAllFromRemote();

        // Sauvegarder dans le stockage local (données chiffrées)
        await localStorageService.saveModelList<MedicamentModel>(
          storageKey,
          medicaments.map((m) => m.copyWith(isSynced: true)).toList(),
        );

        AppLogger.debug('Loaded ${medicaments.length} medicaments from Firestore');
      } else {
        // Hors ligne : charger depuis le stockage local (données chiffrées)
        medicaments = loadAllLocally();
        AppLogger.debug('Loaded ${medicaments.length} medicaments from local storage');
      }

      // 3. Déchiffrer une seule fois
      final decryptedMedicaments = _decryptMedicaments(medicaments);

      // 4. Sauvegarder dans le cache unifié (données déchiffrées)
      await _saveToUnifiedCache(decryptedMedicaments);

      return decryptedMedicaments;
    } catch (e) {
      AppLogger.error('Error getting all medicaments', e);
      return _handleErrorFallback();
    }
  }

  // Obtenir un médicament avec l'ID
  Future<MedicamentModel?> getMedicamentById(String medicamentId) async {
    try {
      final cacheKey = '${_cacheKey}_$medicamentId';

      // 1. Essayer le cache unifié (données DÉJÀ déchiffrées)
      final cachedMedicament = await _unifiedCache.get<MedicamentModel>(
        cacheKey,
        MedicamentModel.fromJson,
      );

      if (cachedMedicament != null) {
        // ✅ Les données du cache sont DÉJÀ déchiffrées
        AppLogger.debug('Using unified cache for medicament: $medicamentId');
        return cachedMedicament; // PAS de déchiffrement ici
      }

      // 2. Charger depuis la source de données (données chiffrées)
      MedicamentModel? medicament;

      if (connectivityService.currentStatus == ConnectionStatus.online) {
        final doc = await _medicamentsCollection.doc(medicamentId).get();
        if (doc.exists) {
          final data = Map<String, dynamic>.from(doc.data()!);
          data['id'] = doc.id;
          medicament = MedicamentModel.fromJson(data); // Données chiffrées

          // Sauvegarder localement (données chiffrées)
          await saveLocally(medicament.copyWith(isSynced: true));
        }
      } else {
        // Mode hors ligne (données chiffrées)
        final allMedicaments = loadAllLocally();
        medicament = allMedicaments.firstWhere(
          (m) => m.id == medicamentId,
          orElse: () => null as MedicamentModel,
        );
      }

      if (medicament != null) {
        // Déchiffrer une seule fois
        final decrypted = _decryptMedicaments([medicament]).first;

        // Sauvegarder dans le cache unifié (données déchiffrées)
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
      AppLogger.error('Error getting medicament by ID: $medicamentId', e);

      // Fallback vers le stockage local (données chiffrées)
      final allMedicaments = loadAllLocally();
      final medicament = allMedicaments.firstWhere(
        (m) => m.id == medicamentId,
        orElse: () => null as MedicamentModel,
      );

      return medicament != null ? _decryptMedicaments([medicament]).first : null;
    }
  }

  // Obtenir tous les médicaments pour une ordonnance
  Future<List<MedicamentModel>> getMedicamentsByOrdonnance(String ordonnanceId) async {
    try {
      final cacheKey = '${_cacheKeyByOrdonnance}_$ordonnanceId';

      // 1. Essayer le cache unifié (données DÉJÀ déchiffrées)
      final cachedMedicaments = await _unifiedCache.get<MedicamentListModel>(
        cacheKey,
        MedicamentListModel.fromJson,
      );

      if (cachedMedicaments != null) {
        // ✅ Les données du cache sont DÉJÀ déchiffrées
        AppLogger.debug(
          'Using unified cache for ordonnance $ordonnanceId medicaments (${cachedMedicaments.medicaments.length} items)',
        );
        return cachedMedicaments.medicaments; // PAS de déchiffrement ici
      }

      // 2. Charger tous les médicaments et filtrer
      final allMedicaments = await getAllMedicaments(); // Déjà déchiffrés
      final filteredMedicaments =
          allMedicaments.where((m) => m.ordonnanceId == ordonnanceId).toList();

      // 3. Mettre en cache le résultat filtré (données déjà déchiffrées)
      await _saveMedicamentsByOrdonnanceToCache(ordonnanceId, filteredMedicaments);

      return filteredMedicaments;
    } catch (e) {
      AppLogger.error('Error getting medicaments for ordonnance: $ordonnanceId', e);

      // Fallback vers le stockage local (données chiffrées)
      final allMedicaments = loadAllLocally();
      final medicaments = _decryptMedicaments(
        allMedicaments.where((m) => m.ordonnanceId == ordonnanceId).toList(),
      );

      return medicaments;
    }
  }

  // Déchiffrer les données sensibles des médicaments
  List<MedicamentModel> _decryptMedicaments(List<MedicamentModel> medicaments) {
    return medicaments.map((medicament) {
      try {
        // Vérifier si les données sont déjà déchiffrées
        if (_isAlreadyDecrypted(medicament.name)) {
          AppLogger.debug('Data already decrypted for medicament: ${medicament.id}');
          return medicament;
        }

        final decryptedName = _encryptionService.decrypt(medicament.name);
        final decryptedDosage =
            medicament.dosage != null ? _encryptionService.decrypt(medicament.dosage!) : null;
        final decryptedInstructions =
            medicament.instructions != null
                ? _encryptionService.decrypt(medicament.instructions!)
                : null;

        return medicament.copyWith(
          name: decryptedName,
          dosage: decryptedDosage,
          instructions: decryptedInstructions,
        );
      } catch (e) {
        AppLogger.error('Error decrypting medicament data for ${medicament.id}', e);
        // En cas d'erreur de déchiffrement, retourner les données telles quelles
        return medicament;
      }
    }).toList();
  }

  // Méthode pour vérifier si les données sont déjà déchiffrées
  bool _isAlreadyDecrypted(String data) {
    try {
      // Essayer de décoder en base64, si ça échoue c'est que c'est déjà déchiffré
      base64.decode(data);
      return false; // C'est du base64 valide, donc chiffré
    } catch (e) {
      return true; // Pas du base64, donc déjà déchiffré
    }
  }

  // Méthodes pour sauvegarder dans le cache unifié
  Future<void> _saveToUnifiedCache(List<MedicamentModel> medicaments) async {
    try {
      final cacheData = MedicamentListModel(medicaments: medicaments, lastUpdated: DateTime.now());

      await _unifiedCache.put(
        _cacheKey,
        cacheData,
        ttl: const Duration(hours: 1), // TTL plus court car données plus volatiles
        level: CacheLevel.both,
        strategy: InvalidationStrategy.smart,
      );

      AppLogger.debug('Saved ${medicaments.length} medicaments to unified cache');
    } catch (e) {
      AppLogger.error('Error saving medicaments to unified cache', e);
    }
  }

  Future<void> _saveMedicamentsByOrdonnanceToCache(
    String ordonnanceId,
    List<MedicamentModel> medicaments,
  ) async {
    try {
      final cacheKey = '${_cacheKeyByOrdonnance}_$ordonnanceId';
      final cacheData = MedicamentListModel(medicaments: medicaments, lastUpdated: DateTime.now());

      await _unifiedCache.put(
        cacheKey,
        cacheData,
        ttl: const Duration(hours: 2), // TTL plus long pour les données par ordonnance
        level: CacheLevel.both,
      );

      AppLogger.debug(
        'Saved ${medicaments.length} medicaments for ordonnance $ordonnanceId to cache',
      );
    } catch (e) {
      AppLogger.error('Error saving medicaments by ordonnance to cache', e);
    }
  }

  Future<void> _saveExpiringMedicamentsToCache(List<MedicamentModel> medicaments) async {
    try {
      const cacheKey = 'medicaments_expiring';
      final cacheData = MedicamentListModel(medicaments: medicaments, lastUpdated: DateTime.now());

      await _unifiedCache.put(
        cacheKey,
        cacheData,
        ttl: const Duration(minutes: 15), // TTL très court pour les données critiques
        level: CacheLevel.memory, // Seulement en mémoire car données volatiles
      );

      AppLogger.debug('Saved ${medicaments.length} expiring medicaments to cache');
    } catch (e) {
      AppLogger.error('Error saving expiring medicaments to cache', e);
    }
  }

  // Fallback en cas d'erreur
  Future<List<MedicamentModel>> _handleErrorFallback() async {
    try {
      // 1. Essayer le stockage local (données chiffrées)
      final localMedicaments = loadAllLocally();
      if (localMedicaments.isNotEmpty) {
        final decrypted = _decryptMedicaments(localMedicaments);
        AppLogger.debug('Using local storage fallback: ${decrypted.length} medicaments');
        return decrypted;
      }

      // 2. Essayer le cache périmé comme dernier recours (données DÉJÀ déchiffrées)
      final staleCache = await _unifiedCache.get<MedicamentListModel>(
        _cacheKey,
        MedicamentListModel.fromJson,
        updateAccess: false,
      );

      if (staleCache != null) {
        AppLogger.warning(
          'Using stale cache as fallback: ${staleCache.medicaments.length} medicaments',
        );
        return staleCache.medicaments; // PAS de déchiffrement ici
      }

      return [];
    } catch (e) {
      AppLogger.error('Error in fallback handling', e);
      return [];
    }
  }

  @override
  Future<void> saveToRemote(MedicamentModel medicament) async {
    try {
      // Vérifier si le médicament existe déjà sur le serveur
      final docRef = _medicamentsCollection.doc(medicament.id);
      final docSnapshot = await docRef.get();

      if (docSnapshot.exists) {
        // Le médicament existe déjà, vérifier s'il y a un conflit
        final remoteData = docSnapshot.data()!;
        remoteData['id'] = docSnapshot.id;
        final remoteMedicament = MedicamentModel.fromJson(remoteData);

        if (_conflictResolver.hasConflict(medicament, remoteMedicament)) {
          // Il y a un conflit, le résoudre
          final resolvedMedicament = _conflictResolver.resolve(medicament, remoteMedicament);

          // Incrémenter la version et sauvegarder
          final updatedMedicament = resolvedMedicament.incrementVersion().copyWith(isSynced: true);
          await docRef.set(updatedMedicament.toJson());

          // Mettre à jour le stockage local avec le médicament résolu
          await saveLocally(updatedMedicament);
          AppLogger.info('Conflict resolved and saved for medicament: ${medicament.id}');
        } else {
          // Pas de conflit, incrémenter la version et sauvegarder
          final updatedMedicament = medicament.incrementVersion().copyWith(isSynced: true);
          await docRef.set(updatedMedicament.toJson());

          // Mettre à jour le stockage local
          await saveLocally(updatedMedicament);
          AppLogger.debug('Medicament updated without conflict: ${medicament.id}');
        }
      } else {
        // Le médicament n'existe pas encore, le sauvegarder
        final updatedMedicament = medicament.copyWith(isSynced: true);
        await docRef.set(updatedMedicament.toJson());

        // Mettre à jour le stockage local
        await saveLocally(updatedMedicament);
        AppLogger.debug('New medicament saved to Firestore: ${medicament.id}');
      }

      // Invalider les caches appropriés après modification
      await invalidateCache();
      await invalidateCacheForOrdonnance(medicament.ordonnanceId);
    } catch (e) {
      AppLogger.error('Error saving medicament to Firestore', e);
      rethrow;
    }
  }

  @override
  Future<void> deleteFromRemote(String id) async {
    try {
      // Récupérer l'ordonnanceId avant suppression pour invalider le cache
      String? ordonnanceId;
      try {
        final medicament = await getMedicamentById(id);
        ordonnanceId = medicament?.ordonnanceId;
      } catch (e) {
        AppLogger.warning('Could not get ordonnanceId for medicament $id before deletion');
      }

      await _medicamentsCollection.doc(id).delete();

      // Invalider les caches après suppression
      await invalidateCache();
      if (ordonnanceId != null) {
        await invalidateCacheForOrdonnance(ordonnanceId);
      }

      AppLogger.debug('Medicament deleted from Firestore: $id');
    } catch (e) {
      AppLogger.error('Error deleting medicament from Firestore', e);
      rethrow;
    }
  }

  @override
  Future<List<MedicamentModel>> loadAllFromRemote() async {
    try {
      final snapshot = await _medicamentsCollection.get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return MedicamentModel.fromJson(data);
      }).toList();
    } catch (e) {
      AppLogger.error('Error loading medicaments from Firestore', e);
      rethrow;
    }
  }

  Future<MedicamentModel> resolveConflictManually(
    MedicamentModel local,
    MedicamentModel remote,
    ConflictChoice choice,
  ) async {
    MedicamentModel resolvedMedicament;

    switch (choice) {
      case ConflictChoice.useLocal:
        resolvedMedicament = local.incrementVersion();
        break;
      case ConflictChoice.useRemote:
        resolvedMedicament = remote.incrementVersion();
        break;
      case ConflictChoice.merge:
        resolvedMedicament = ModelMerger.merge(local, remote);
        break;
    }

    // Sauvegarder le médicament résolu
    resolvedMedicament = resolvedMedicament.copyWith(updatedAt: DateTime.now(), isSynced: false);

    // Sauvegarder localement
    await saveLocally(resolvedMedicament);

    // Si nous sommes en ligne, synchroniser avec le serveur
    if (connectivityService.currentStatus == ConnectionStatus.online) {
      await saveToRemote(resolvedMedicament);
    } else {
      // Sinon, ajouter à la file d'attente des opérations en attente
      await addPendingOperation(
        PendingOperation<MedicamentModel>(
          type: OperationType.update,
          data: resolvedMedicament,
          execute: () => saveToRemote(resolvedMedicament),
        ),
      );

      // Sauvegarder les opérations en attente
      await savePendingOperations();
    }

    // Invalider le cache
    invalidateCache();

    return resolvedMedicament;
  }

  Future<void> invalidateCache() async {
    try {
      // Invalider tous les caches liés aux médicaments
      await _unifiedCache.invalidatePattern('$_cacheKey*');
      await _unifiedCache.invalidatePattern('$_cacheKeyByOrdonnance*');
      await _unifiedCache.invalidate('medicaments_expiring');

      AppLogger.debug('Invalidated medicaments cache');
    } catch (e) {
      AppLogger.error('Error invalidating medicaments cache', e);
    }
  }

  Future<void> invalidateCacheForOrdonnance(String ordonnanceId) async {
    try {
      await _unifiedCache.invalidate('${_cacheKeyByOrdonnance}_$ordonnanceId');
      await _unifiedCache.invalidate(
        'medicaments_expiring',
      ); // Les données d'expiration peuvent changer

      AppLogger.debug('Invalidated medicaments cache for ordonnance: $ordonnanceId');
    } catch (e) {
      AppLogger.error('Error invalidating medicaments cache for ordonnance', e);
    }
  }
}

// Modèle wrapper pour la liste de médicaments dans le cache
class MedicamentListModel implements SyncableModel {
  final List<MedicamentModel> medicaments;
  final DateTime lastUpdated;

  MedicamentListModel({required this.medicaments, required this.lastUpdated});

  @override
  String get id => 'medicaments_list';

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
      'medicaments':
          medicaments
              .map(
                (m) => {
                  'id': m.id,
                  'ordonnanceId': m.ordonnanceId,
                  'name': m.name, // ✅ Stocké déchiffré dans le cache
                  'expirationDate': m.expirationDate.toIso8601String(),
                  'dosage': m.dosage, // ✅ Stocké déchiffré dans le cache
                  'instructions': m.instructions, // ✅ Stocké déchiffré dans le cache
                  'createdAt': m.createdAt.toIso8601String(),
                  'updatedAt': m.updatedAt.toIso8601String(),
                  'isSynced': m.isSynced,
                  'version': m.version,
                },
              )
              .toList(),
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }

  factory MedicamentListModel.fromJson(Map<String, dynamic> json) {
    return MedicamentListModel(
      medicaments:
          (json['medicaments'] as List)
              .map(
                (m) => MedicamentModel(
                  id: m['id'],
                  ordonnanceId: m['ordonnanceId'],
                  name: m['name'], // ✅ Déjà déchiffré depuis le cache
                  expirationDate: DateTime.parse(m['expirationDate']),
                  dosage: m['dosage'], // ✅ Déjà déchiffré depuis le cache
                  instructions: m['instructions'], // ✅ Déjà déchiffré depuis le cache
                  createdAt: DateTime.parse(m['createdAt']),
                  updatedAt: DateTime.parse(m['updatedAt']),
                  isSynced: m['isSynced'],
                  version: m['version'],
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
