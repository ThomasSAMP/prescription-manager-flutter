import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';

import '../../features/prescriptions/models/medicament_model.dart';
import '../../features/prescriptions/models/ordonnance_model.dart';
import '../../features/prescriptions/repositories/medicament_repository.dart';
import '../../features/prescriptions/repositories/ordonnance_repository.dart';
import '../di/injection.dart';
import '../utils/logger.dart';
import 'event_bus_service.dart';

@lazySingleton
class FirestoreListenerService {
  final FirebaseFirestore _firestore;
  final OrdonnanceRepository _ordonnanceRepository;
  final MedicamentRepository _medicamentRepository;

  // Garder une référence aux abonnements pour pouvoir les annuler
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> _subscriptions = {};

  FirestoreListenerService(this._firestore, this._ordonnanceRepository, this._medicamentRepository);

  /// Démarre l'écoute des changements pour les ordonnances
  Future<void> startListeningToOrdonnances() async {
    if (_subscriptions.containsKey('ordonnances')) {
      AppLogger.debug('Already listening to ordonnances');
      return;
    }

    try {
      AppLogger.debug('Starting to listen to ordonnances');

      // Créer un écouteur pour la collection des ordonnances
      final subscription = _firestore
          .collection('ordonnances')
          .snapshots()
          .listen(
            _handleOrdonnancesSnapshot,
            onError: (error) {
              AppLogger.error('Error listening to ordonnances', error);
            },
          );

      _subscriptions['ordonnances'] = subscription;
    } catch (e) {
      AppLogger.error('Failed to start listening to ordonnances', e);
    }
  }

  /// Démarre l'écoute des changements pour les médicaments
  Future<void> startListeningToMedicaments() async {
    if (_subscriptions.containsKey('medicaments')) {
      AppLogger.debug('Already listening to medicaments');
      return;
    }

    try {
      AppLogger.debug('Starting to listen to medicaments');

      // Créer un écouteur pour la collection des médicaments
      final subscription = _firestore
          .collection('medicaments')
          .snapshots()
          .listen(
            _handleMedicamentsSnapshot,
            onError: (error) {
              AppLogger.error('Error listening to medicaments', error);
            },
          );

      _subscriptions['medicaments'] = subscription;
    } catch (e) {
      AppLogger.error('Failed to start listening to medicaments', e);
    }
  }

  /// Gère les changements dans la collection des ordonnances
  void _handleOrdonnancesSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    try {
      // Traiter les documents modifiés et ajoutés
      for (var change in snapshot.docChanges) {
        final data = change.doc.data()!;
        data['id'] = change.doc.id;

        final ordonnance = OrdonnanceModel.fromJson(data);

        switch (change.type) {
          case DocumentChangeType.added:
          case DocumentChangeType.modified:
            // Sauvegarder l'ordonnance localement (avec isSynced = true)
            _ordonnanceRepository.saveLocally(ordonnance.copyWith(isSynced: true));
            // AppLogger.debug('Ordonnance ${change.type.name}: ${ordonnance.id}');
            break;
          case DocumentChangeType.removed:
            // Supprimer l'ordonnance localement
            _ordonnanceRepository.deleteLocally(ordonnance.id);
            // AppLogger.debug('Ordonnance removed: ${ordonnance.id}');
            break;
        }
      }

      // Notifier les providers que les données ont changé
      _notifyOrdonnanceDataChanged();
    } catch (e) {
      AppLogger.error('Error handling ordonnances snapshot', e);
    }
  }

  /// Gère les changements dans la collection des médicaments
  void _handleMedicamentsSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    try {
      // Traiter les documents modifiés et ajoutés
      for (var change in snapshot.docChanges) {
        final data = change.doc.data()!;
        data['id'] = change.doc.id;

        final medicament = MedicamentModel.fromJson(data);

        switch (change.type) {
          case DocumentChangeType.added:
          case DocumentChangeType.modified:
            // Sauvegarder le médicament localement (avec isSynced = true)
            _medicamentRepository.saveLocally(medicament.copyWith(isSynced: true));
            // AppLogger.debug('Medicament ${change.type.name}: ${medicament.id}');
            break;
          case DocumentChangeType.removed:
            // Supprimer le médicament localement
            _medicamentRepository.deleteLocally(medicament.id);
            // AppLogger.debug('Medicament removed: ${medicament.id}');
            break;
        }
      }

      // Notifier les providers que les données ont changé
      _notifyMedicamentDataChanged();
    } catch (e) {
      AppLogger.error('Error handling medicaments snapshot', e);
    }
  }

  /// Notifie les providers que les données des ordonnances ont changé
  void _notifyOrdonnanceDataChanged() {
    try {
      // Invalider le cache du repository
      _ordonnanceRepository.invalidateCache();

      // Publier un événement pour notifier les providers
      getIt<EventBusService>().publish(AppEvent(EventType.ordonnancesChanged));
    } catch (e) {
      AppLogger.error('Error notifying ordonnance data changed', e);
    }
  }

  /// Notifie les providers que les données des médicaments ont changé
  void _notifyMedicamentDataChanged() {
    try {
      // Invalider le cache du repository
      _medicamentRepository.invalidateCache();

      // Publier un événement pour notifier les providers
      getIt<EventBusService>().publish(AppEvent(EventType.medicamentsChanged));
    } catch (e) {
      AppLogger.error('Error notifying medicament data changed', e);
    }
  }

  /// Arrête l'écoute des changements pour toutes les collections
  Future<void> stopAllListeners() async {
    try {
      for (var entry in _subscriptions.entries) {
        await entry.value.cancel();
        AppLogger.debug('Stopped listening to ${entry.key}');
      }
      _subscriptions.clear();
    } catch (e) {
      AppLogger.error('Error stopping listeners', e);
    }
  }

  /// Démarre l'écoute des changements pour toutes les collections
  Future<void> startAllListeners() async {
    await startListeningToOrdonnances();
    await startListeningToMedicaments();
  }
}
