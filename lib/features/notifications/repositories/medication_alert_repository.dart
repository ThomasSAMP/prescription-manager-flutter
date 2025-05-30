import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';

import '../../../core/services/encryption_service.dart';
import '../../../core/utils/logger.dart';
import '../models/medication_alert_model.dart';

@lazySingleton
class MedicationAlertRepository {
  final FirebaseFirestore _firestore;
  final EncryptionService _encryptionService;

  // Cache en mémoire
  final List<MedicationAlertModel> _cachedAlerts = [];
  bool _isCacheInitialized = false;
  DateTime _lastCacheUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  MedicationAlertRepository(this._firestore, this._encryptionService);

  CollectionReference<Map<String, dynamic>> get _alertsCollection =>
      _firestore.collection('medication_alerts');

  // Obtenir toutes les alertes
  Future<List<MedicationAlertModel>> getAllAlerts() async {
    try {
      // Vérifier le cache (2 minutes pour les alertes)
      final now = DateTime.now();
      if (_isCacheInitialized && now.difference(_lastCacheUpdate).inMinutes < 2) {
        AppLogger.debug('Using cached alerts (${_cachedAlerts.length} items)');
        return _cachedAlerts;
      }

      // Charger depuis Firestore
      final alerts = await _loadAllFromFirestore();

      // Mettre à jour le cache
      _cachedAlerts.clear();
      _cachedAlerts.addAll(alerts);
      _isCacheInitialized = true;
      _lastCacheUpdate = now;

      AppLogger.debug('Loaded ${alerts.length} alerts and updated cache');
      return _cachedAlerts;
    } catch (e) {
      AppLogger.error('Error getting all alerts', e);

      // En cas d'erreur, utiliser le cache si disponible
      if (_isCacheInitialized) {
        AppLogger.debug('Using cached alerts after error');
        return _cachedAlerts;
      }

      return [];
    }
  }

  // Charger depuis Firestore avec tri
  Future<List<MedicationAlertModel>> _loadAllFromFirestore() async {
    try {
      final snapshot =
          await _alertsCollection
              .orderBy('alertDate', descending: true)
              .orderBy('createdAt', descending: true)
              .get();

      return snapshot.docs.map((doc) {
        final alert = MedicationAlertModel.fromJson(doc.data(), doc.id);
        return _decryptAlert(alert);
      }).toList();
    } catch (e) {
      AppLogger.error('Error loading alerts from Firestore', e);
      rethrow;
    }
  }

  // Déchiffrer les données sensibles
  MedicationAlertModel _decryptAlert(MedicationAlertModel alert) {
    try {
      final decryptedPatientName = _encryptionService.decrypt(alert.patientName);
      final decryptedMedicamentName = _encryptionService.decrypt(alert.medicamentName);

      return alert.copyWith(
        patientName: decryptedPatientName,
        medicamentName: decryptedMedicamentName,
      );
    } catch (e) {
      AppLogger.error('Error decrypting alert data', e);
      return alert;
    }
  }

  // Mettre à jour l'état d'une alerte pour un utilisateur
  Future<void> updateUserAlertState({
    required String alertId,
    required String userId,
    bool? isRead,
    bool? isHidden,
  }) async {
    try {
      final alertRef = _alertsCollection.doc(alertId);

      // Construire le chemin pour l'état utilisateur
      final updateData = <String, dynamic>{};

      if (isRead != null) {
        updateData['userStates.$userId.isRead'] = isRead;
        if (isRead) {
          updateData['userStates.$userId.readAt'] = FieldValue.serverTimestamp();
        }
      }

      if (isHidden != null) {
        updateData['userStates.$userId.isHidden'] = isHidden;
      }

      await alertRef.update(updateData);

      // Invalider le cache
      invalidateCache();

      AppLogger.debug('Updated user alert state: $alertId for user: $userId');
    } catch (e) {
      AppLogger.error('Error updating user alert state', e);
      rethrow;
    }
  }

  // Marquer comme lu
  Future<void> markAsRead(String alertId, String userId) async {
    await updateUserAlertState(alertId: alertId, userId: userId, isRead: true);
  }

  // Marquer comme caché
  Future<void> markAsHidden(String alertId, String userId) async {
    await updateUserAlertState(alertId: alertId, userId: userId, isHidden: true);
  }

  // Marquer toutes les alertes comme lues pour un utilisateur
  Future<void> markAllAsRead(String userId) async {
    try {
      final alerts = await getAllAlerts();
      final batch = _firestore.batch();

      for (final alert in alerts) {
        final userState = alert.getUserState(userId);
        if (!userState.isRead && !userState.isHidden) {
          final alertRef = _alertsCollection.doc(alert.id);
          batch.update(alertRef, {
            'userStates.$userId.isRead': true,
            'userStates.$userId.readAt': FieldValue.serverTimestamp(),
          });
        }
      }

      await batch.commit();
      invalidateCache();

      AppLogger.debug('Marked all alerts as read for user: $userId');
    } catch (e) {
      AppLogger.error('Error marking all alerts as read', e);
      rethrow;
    }
  }

  // Marquer toutes les alertes comme cachées pour un utilisateur
  Future<void> markAllAsHidden(String userId) async {
    try {
      final alerts = await getAllAlerts();
      final batch = _firestore.batch();

      for (final alert in alerts) {
        final userState = alert.getUserState(userId);
        if (!userState.isHidden) {
          final alertRef = _alertsCollection.doc(alert.id);
          batch.update(alertRef, {'userStates.$userId.isHidden': true});
        }
      }

      await batch.commit();
      invalidateCache();

      AppLogger.debug('Marked all alerts as hidden for user: $userId');
    } catch (e) {
      AppLogger.error('Error marking all alerts as hidden', e);
      rethrow;
    }
  }

  // Obtenir les alertes filtrées pour un utilisateur
  List<MedicationAlertModel> getAlertsForUser(List<MedicationAlertModel> alerts, String userId) {
    return alerts.where((alert) {
      final userState = alert.getUserState(userId);
      return !userState.isHidden;
    }).toList();
  }

  // Obtenir le nombre d'alertes non lues pour un utilisateur
  int getUnreadCount(List<MedicationAlertModel> alerts, String userId) {
    return alerts.where((alert) {
      final userState = alert.getUserState(userId);
      return !userState.isRead && !userState.isHidden;
    }).length;
  }

  // Grouper les alertes par date
  Map<String, List<MedicationAlertModel>> groupAlertsByDate(List<MedicationAlertModel> alerts) {
    final grouped = <String, List<MedicationAlertModel>>{};

    for (final alert in alerts) {
      final group = alert.getDateGroup();
      if (!grouped.containsKey(group)) {
        grouped[group] = [];
      }
      grouped[group]!.add(alert);
    }

    // Trier chaque groupe par criticité puis par date de création
    for (final group in grouped.values) {
      group.sort((a, b) {
        // D'abord par criticité (expired > critical > warning)
        final aPriority = _getAlertPriority(a.alertLevel);
        final bPriority = _getAlertPriority(b.alertLevel);

        if (aPriority != bPriority) {
          return bPriority.compareTo(aPriority); // Décroissant
        }

        // Puis par date de création (plus récent en premier)
        return b.createdAt.compareTo(a.createdAt);
      });
    }

    return grouped;
  }

  int _getAlertPriority(AlertLevel level) {
    switch (level) {
      case AlertLevel.expired:
        return 3;
      case AlertLevel.critical:
        return 2;
      case AlertLevel.warning:
        return 1;
    }
  }

  // Stream pour les alertes en temps réel
  Stream<List<MedicationAlertModel>> getAlertsStream() {
    return _alertsCollection
        .orderBy('alertDate', descending: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          final alerts =
              snapshot.docs.map((doc) {
                final alert = MedicationAlertModel.fromJson(doc.data(), doc.id);
                return _decryptAlert(alert);
              }).toList();

          // Mettre à jour le cache
          _updateCache(alerts);

          return alerts;
        })
        .handleError((error) {
          AppLogger.error('Error in alerts stream', error);
          return _isCacheInitialized ? _cachedAlerts : <MedicationAlertModel>[];
        });
  }

  // Mettre à jour le cache
  void _updateCache(List<MedicationAlertModel> alerts) {
    _cachedAlerts.clear();
    _cachedAlerts.addAll(alerts);
    _isCacheInitialized = true;
    _lastCacheUpdate = DateTime.now();
  }

  // Invalider le cache
  void invalidateCache() {
    _isCacheInitialized = false;
    _cachedAlerts.clear();
    AppLogger.debug('Medication alerts cache invalidated');
  }

  // Forcer le rechargement
  Future<List<MedicationAlertModel>> forceReload() async {
    invalidateCache();
    return getAllAlerts();
  }
}
