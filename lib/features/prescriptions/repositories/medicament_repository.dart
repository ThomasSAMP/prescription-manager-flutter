// lib/features/prescriptions/repositories/medicament_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

import '../../../core/repositories/offline_repository_base.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/encryption_service.dart';
import '../../../core/services/local_storage_service.dart';
import '../../../core/utils/logger.dart';
import '../models/medicament_model.dart';

@lazySingleton
class MedicamentRepository extends OfflineRepositoryBase<MedicamentModel> {
  final FirebaseFirestore _firestore;
  final EncryptionService _encryptionService;
  final Uuid _uuid = const Uuid();

  // Collection Firestore pour les médicaments
  CollectionReference<Map<String, dynamic>> get _medicamentsCollection =>
      _firestore.collection('medicaments');

  MedicamentRepository(
    this._firestore,
    this._encryptionService,
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
    );

    // Sauvegarder localement
    await saveLocally(medicament);

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
    );

    // Sauvegarder localement
    await saveLocally(updatedMedicament);

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
      List<MedicamentModel> medicaments;

      // Si nous sommes en ligne, essayer de récupérer depuis Firestore
      if (connectivityService.currentStatus == ConnectionStatus.online) {
        final snapshot =
            await _medicamentsCollection.where('ordonnanceId', isEqualTo: ordonnanceId).get();

        medicaments =
            snapshot.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return MedicamentModel.fromJson(data);
            }).toList();

        // Mettre à jour le stockage local avec les données du serveur
        for (final medicament in medicaments) {
          await saveLocally(medicament.copyWith(isSynced: true));
        }
      } else {
        // Sinon, charger depuis le stockage local
        final allMedicaments = loadAllLocally();
        medicaments = allMedicaments.where((m) => m.ordonnanceId == ordonnanceId).toList();
      }

      return _decryptMedicaments(medicaments);
    } catch (e) {
      AppLogger.error('Error getting medicaments for ordonnance: $ordonnanceId', e);
      // En cas d'erreur, charger depuis le stockage local
      final allMedicaments = loadAllLocally();
      final medicaments = allMedicaments.where((m) => m.ordonnanceId == ordonnanceId).toList();
      return _decryptMedicaments(medicaments);
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
      List<MedicamentModel> medicaments;

      // Si nous sommes en ligne, essayer de récupérer depuis Firestore
      if (connectivityService.currentStatus == ConnectionStatus.online) {
        medicaments = await loadAllFromRemote();

        // Mettre à jour le stockage local avec les données du serveur
        for (final medicament in medicaments) {
          await saveLocally(medicament.copyWith(isSynced: true));
        }
      } else {
        // Sinon, charger depuis le stockage local
        medicaments = loadAllLocally();
      }

      return _decryptMedicaments(medicaments);
    } catch (e) {
      AppLogger.error('Error getting all medicaments', e);
      // En cas d'erreur, charger depuis le stockage local
      final medicaments = loadAllLocally();
      return _decryptMedicaments(medicaments);
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
      final updatedMedicament = medicament.copyWith(isSynced: true);
      await _medicamentsCollection.doc(medicament.id).set(updatedMedicament.toJson());

      // Mettre à jour le stockage local avec le médicament synchronisé
      await saveLocally(updatedMedicament);

      AppLogger.debug('Medicament saved to Firestore: ${medicament.id}');
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
}
