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
      // Si nous sommes en ligne, essayer de récupérer depuis Firestore
      if (connectivityService.currentStatus == ConnectionStatus.online) {
        final ordonnances = await loadAllFromRemote();

        // Mettre à jour le stockage local avec les données du serveur
        for (final ordonnance in ordonnances) {
          await saveLocally(ordonnance.copyWith(isSynced: true));
        }

        return _decryptOrdonnances(ordonnances);
      } else {
        // Sinon, charger depuis le stockage local
        final ordonnances = loadAllLocally();
        return _decryptOrdonnances(ordonnances);
      }
    } catch (e) {
      AppLogger.error('Error getting ordonnances', e);
      // En cas d'erreur, charger depuis le stockage local
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
