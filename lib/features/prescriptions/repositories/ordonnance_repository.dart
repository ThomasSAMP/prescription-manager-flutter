import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

import '../../../core/repositories/offline_repository_base.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/encryption_service.dart';
import '../../../core/services/local_storage_service.dart';
import '../../../core/utils/logger.dart';
import '../models/ordonnance_model.dart';

@lazySingleton
class OrdonnanceRepository extends OfflineRepositoryBase<OrdonnanceModel> {
  final FirebaseFirestore _firestore;
  final EncryptionService _encryptionService;
  final Uuid _uuid = const Uuid();

  // Ajout d'un cache en mémoire
  final List<OrdonnanceModel> _cachedOrdonnances = [];
  bool _isCacheInitialized = false;
  DateTime _lastCacheUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  // Collection Firestore pour les ordonnances
  CollectionReference<Map<String, dynamic>> get _ordonnancesCollection =>
      _firestore.collection('ordonnances');

  OrdonnanceRepository(
    this._firestore,
    this._encryptionService,
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

  // Obtenir toutes les ordonnances
  Future<List<OrdonnanceModel>> getOrdonnances() async {
    try {
      // Vérifier si le cache en mémoire est récent (moins de 5 minutes)
      final now = DateTime.now();
      if (_isCacheInitialized && now.difference(_lastCacheUpdate).inMinutes < 5) {
        AppLogger.debug(
          'Using in-memory cache for ordonnances (${_cachedOrdonnances.length} items)',
        );
        return _cachedOrdonnances;
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

      // Mettre à jour le cache en mémoire
      _cachedOrdonnances.clear();
      _cachedOrdonnances.addAll(_decryptOrdonnances(ordonnances));
      _isCacheInitialized = true;
      _lastCacheUpdate = now;

      return _cachedOrdonnances;
    } catch (e) {
      AppLogger.error('Error getting ordonnances', e);

      // En cas d'erreur, utiliser le cache en mémoire si disponible
      if (_isCacheInitialized) {
        AppLogger.debug('Using in-memory cache after error');
        return _cachedOrdonnances;
      }

      // Sinon, charger depuis le stockage local
      final ordonnances = loadAllLocally();

      // Mettre à jour le cache en mémoire
      _cachedOrdonnances.clear();
      _cachedOrdonnances.addAll(_decryptOrdonnances(ordonnances));
      _isCacheInitialized = true;
      _lastCacheUpdate = DateTime.now();

      return _cachedOrdonnances;
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

  void invalidateCache() {
    _isCacheInitialized = false;
    _cachedOrdonnances.clear();
  }

  @override
  Future<void> saveToRemote(OrdonnanceModel ordonnance) async {
    try {
      final updatedOrdonnance = ordonnance.copyWith(isSynced: true);
      await _ordonnancesCollection.doc(ordonnance.id).set(updatedOrdonnance.toJson());

      // Mettre à jour le stockage local avec l'ordonnance synchronisée
      await saveLocally(updatedOrdonnance);

      AppLogger.debug('Ordonnance saved to Firestore: ${ordonnance.id}');
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
}
