import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';

import '../../../core/services/encryption_service.dart';
import '../../../core/services/unified_cache_service.dart';
import '../../../core/utils/logger.dart';
import '../models/medication_alert_model.dart';

@lazySingleton
class MedicationAlertRepository {
  final FirebaseFirestore _firestore;
  final EncryptionService _encryptionService;
  final UnifiedCacheService _cacheService;

  static const String _cacheKey = 'medication_alerts';

  MedicationAlertRepository(this._firestore, this._encryptionService, this._cacheService);

  CollectionReference<Map<String, dynamic>> get _alertsCollection =>
      _firestore.collection('medication_alerts');

  // Obtenir toutes les alertes
  Future<List<MedicationAlertModel>> getAllAlerts() async {
    try {
      // Vérifier le cache unifié
      if (_cacheService.isCacheValid(_cacheKey)) {
        final cachedAlerts = _cacheService.getFromCache<MedicationAlertModel>(_cacheKey);
        AppLogger.debug('Using in-memory cache for alerts (${cachedAlerts.length} items)');
        return cachedAlerts;
      }

      // Charger depuis Firestore
      final alerts = await _loadAllFromFirestore();

      // Mettre à jour le cache
      _cacheService.updateCache(_cacheKey, alerts);

      AppLogger.debug('Loaded ${alerts.length} alerts and updated cache');
      return alerts;
    } catch (e) {
      AppLogger.error('Error getting all alerts', e);

      // En cas d'erreur, utiliser le cache si disponible
      final cachedAlerts = _cacheService.getFromCache<MedicationAlertModel>(_cacheKey);
      if (cachedAlerts.isNotEmpty) {
        AppLogger.debug('Using stale cache after error');
        return cachedAlerts;
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

  // Méthode temporaire pour reset toutes les notifications d'un utilisateur
  Future<void> resetAllUserNotifications(String userId) async {
    try {
      final alerts = await _loadAllFromFirestore();
      final batch = _firestore.batch();

      for (final alert in alerts) {
        final alertRef = _alertsCollection.doc(alert.id);
        batch.update(alertRef, {
          'userStates.$userId.isRead': false,
          'userStates.$userId.isHidden': false,
          'userStates.$userId.readAt': FieldValue.delete(),
        });
      }

      await batch.commit();
      invalidateCache();

      AppLogger.debug('Reset all notifications for user: $userId');
    } catch (e) {
      AppLogger.error('Error resetting all notifications', e);
      rethrow;
    }
  }

  // Forcer le rechargement
  Future<List<MedicationAlertModel>> forceReload() async {
    invalidateCache();
    return getAllAlerts();
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

  void invalidateCache() {
    _cacheService.invalidateCache(_cacheKey);
  }
}
