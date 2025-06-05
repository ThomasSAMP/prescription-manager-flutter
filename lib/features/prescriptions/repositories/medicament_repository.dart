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
import '../models/medicament_model.dart';

@lazySingleton
class MedicamentRepository extends OfflineRepositoryBase<MedicamentModel> {
  final FirebaseFirestore _firestore;
  final EncryptionService _encryptionService;
  final CacheService _cacheService;
  final Uuid _uuid = const Uuid();

  static const String _cacheKey = 'medicaments';

  final ConflictResolver _conflictResolver = ConflictResolver(
    strategy: ConflictResolutionStrategy.newerWins,
  );

  CollectionReference<Map<String, dynamic>> get _medicamentsCollection =>
      _firestore.collection('medicaments');

  MedicamentRepository(
    this._firestore,
    this._encryptionService,
    this._cacheService,
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
      addPendingOperation(
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
      addPendingOperation(
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

      addPendingOperation(
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

  // Obtenir tous les médicaments pour une ordonnance
  Future<List<MedicamentModel>> getMedicamentsByOrdonnance(String ordonnanceId) async {
    try {
      // Utiliser le cache en mémoire si possible
      if (_cacheService.isCacheValid(_cacheKey)) {
        final cachedMedicaments = _cacheService.getFromCache<MedicamentModel>(_cacheKey);
        final filteredMedicaments =
            cachedMedicaments.where((m) => m.ordonnanceId == ordonnanceId).toList();

        AppLogger.debug(
          'Using in-memory cache for ordonnance $ordonnanceId medicaments (${filteredMedicaments.length} items)',
        );
        return filteredMedicaments;
      }

      // Si le cache n'est pas initialisé, charger tous les médicaments d'abord
      await getAllMedicaments();

      // Puis filtrer pour l'ordonnance spécifique
      final cachedMedicaments = _cacheService.getFromCache<MedicamentModel>(_cacheKey);
      return cachedMedicaments.where((m) => m.ordonnanceId == ordonnanceId).toList();
    } catch (e) {
      AppLogger.error('Error getting medicaments for ordonnance: $ordonnanceId', e);

      // En cas d'erreur, charger depuis le stockage local
      final allMedicaments = loadAllLocally();
      final medicaments = _decryptMedicaments(
        allMedicaments.where((m) => m.ordonnanceId == ordonnanceId).toList(),
      );

      return medicaments;
    }
  }

  // Obtenir tous les médicaments qui arrivent bientôt à expiration
  Future<List<MedicamentModel>> getMedicamentsNearingExpiration() async {
    try {
      final allMedicaments = await getAllMedicaments();

      // Filtrer les médicaments qui arrivent à expiration dans les 30 jours
      return allMedicaments.where((medicament) {
        final status = medicament.getExpirationStatus();
        return status.needsAttention;
      }).toList();
    } catch (e) {
      AppLogger.error('Error getting medicaments nearing expiration', e);
      return [];
    }
  }

  // Obtenir tous les médicaments
  Future<List<MedicamentModel>> getAllMedicaments() async {
    try {
      // Vérifier le cache unifié
      if (_cacheService.isCacheValid(_cacheKey)) {
        final cachedMedicaments = _cacheService.getFromCache<MedicamentModel>(_cacheKey);
        AppLogger.debug(
          'Using in-memory cache for medicaments (${cachedMedicaments.length} items)',
        );
        return cachedMedicaments;
      }

      List<MedicamentModel> medicaments;

      // Si nous sommes en ligne, essayer de récupérer depuis Firestore
      if (connectivityService.currentStatus == ConnectionStatus.online) {
        medicaments = await loadAllFromRemote();

        // Sauvegarder dans le stockage local
        await localStorageService.saveModelList<MedicamentModel>(
          storageKey,
          medicaments.map((m) => m.copyWith(isSynced: true)).toList(),
        );

        AppLogger.debug('Loaded ${medicaments.length} medicaments from remote');
      } else {
        // Sinon, charger depuis le stockage local
        medicaments = loadAllLocally();
        AppLogger.debug('Loaded ${medicaments.length} medicaments from local storage');
      }

      // Déchiffrer et mettre en cache
      final decryptedMedicaments = _decryptMedicaments(medicaments);
      _cacheService.updateCache(_cacheKey, decryptedMedicaments);

      return decryptedMedicaments;
    } catch (e) {
      AppLogger.error('Error getting all medicaments', e);

      // En cas d'erreur, essayer le cache puis le stockage local
      final cachedMedicaments = _cacheService.getFromCache<MedicamentModel>(_cacheKey);
      if (cachedMedicaments.isNotEmpty) {
        AppLogger.debug('Using stale cache after error');
        return cachedMedicaments;
      }

      // Dernier recours : stockage local
      final medicaments = loadAllLocally();
      final decryptedMedicaments = _decryptMedicaments(medicaments);
      _cacheService.updateCache(_cacheKey, decryptedMedicaments);

      return decryptedMedicaments;
    }
  }

  // Obtenir un médicament avec l'ID
  Future<MedicamentModel?> getMedicamentById(String medicamentId) async {
    try {
      // Vérifier d'abord dans le cache en mémoire
      if (_cacheService.isCacheValid(_cacheKey)) {
        final cachedMedicaments = _cacheService.getFromCache<MedicamentModel>(_cacheKey);
        final cachedMedicament = cachedMedicaments.firstWhere(
          (m) => m.id == medicamentId,
          orElse: () => null as MedicamentModel,
        );

        AppLogger.debug('Using in-memory cache for medicament: $medicamentId');
        return cachedMedicament;
      }

      // Si nous sommes en ligne, essayer de récupérer depuis Firestore
      if (connectivityService.currentStatus == ConnectionStatus.online) {
        final doc = await _medicamentsCollection.doc(medicamentId).get();

        if (!doc.exists) {
          return null;
        }

        final data = Map<String, dynamic>.from(doc.data()!);
        data['id'] = doc.id;

        final medicament = MedicamentModel.fromJson(data);

        // Sauvegarder dans le stockage local
        await saveLocally(medicament.copyWith(isSynced: true));

        // Déchiffrer et retourner
        return _decryptMedicaments([medicament]).first;
      } else {
        // En mode hors ligne, charger depuis le stockage local
        final allMedicaments = loadAllLocally();
        final filteredMedicaments = allMedicaments.where((m) => m.id == medicamentId).toList();

        if (filteredMedicaments.isEmpty) {
          return null;
        }

        return _decryptMedicaments(filteredMedicaments).first;
      }
    } catch (e) {
      AppLogger.error('Error getting medicament by ID: $medicamentId', e);

      // En cas d'erreur, essayer de charger depuis le stockage local
      final allMedicaments = loadAllLocally();
      final filteredMedicaments = allMedicaments.where((m) => m.id == medicamentId).toList();

      if (filteredMedicaments.isEmpty) {
        return null;
      }

      return _decryptMedicaments(filteredMedicaments).first;
    }
  }

  // Déchiffrer les données sensibles des médicaments
  List<MedicamentModel> _decryptMedicaments(List<MedicamentModel> medicaments) {
    return medicaments.map((medicament) {
      try {
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
        AppLogger.error('Error decrypting medicament data', e);
        return medicament;
      }
    }).toList();
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
    } catch (e) {
      AppLogger.error('Error saving medicament to Firestore', e);
      rethrow;
    }
  }

  @override
  Future<void> deleteFromRemote(String id) async {
    try {
      await _medicamentsCollection.doc(id).delete();
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
      addPendingOperation(
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

  void invalidateCache() {
    _cacheService.invalidateCache(_cacheKey);
  }
}
