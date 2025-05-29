import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';

import '../../../core/services/encryption_service.dart';
import '../../../core/utils/logger.dart';
import '../models/notification_model.dart';

@lazySingleton
class NotificationRepository {
  final FirebaseFirestore _firestore;
  final EncryptionService _encryptionService;

  // Ajout d'un cache en mémoire
  final List<NotificationModel> _cachedNotifications = [];
  bool _isCacheInitialized = false;
  DateTime _lastCacheUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  NotificationRepository(this._firestore, this._encryptionService);

  // Collection Firestore pour les notifications
  CollectionReference<Map<String, dynamic>> get _notificationsCollection =>
      _firestore.collection('notifications');

  // Méthode optimisée pour obtenir toutes les notifications
  Future<List<NotificationModel>> getAllNotifications() async {
    try {
      // Vérifier si le cache en mémoire est récent (moins de 2 minutes pour les notifications)
      final now = DateTime.now();
      if (_isCacheInitialized && now.difference(_lastCacheUpdate).inMinutes < 2) {
        AppLogger.debug(
          'Using in-memory cache for notifications (${_cachedNotifications.length} items)',
        );
        return _cachedNotifications;
      }

      // Charger depuis Firestore
      final notifications = await _loadAllFromFirestore();

      // Mettre à jour le cache en mémoire
      _cachedNotifications.clear();
      _cachedNotifications.addAll(notifications);
      _isCacheInitialized = true;
      _lastCacheUpdate = now;

      AppLogger.debug('Loaded ${notifications.length} notifications and updated cache');
      return _cachedNotifications;
    } catch (e) {
      AppLogger.error('Error getting all notifications', e);

      // En cas d'erreur, utiliser le cache en mémoire si disponible
      if (_isCacheInitialized) {
        AppLogger.debug('Using in-memory cache after error');
        return _cachedNotifications;
      }

      return [];
    }
  }

  // Méthode privée pour charger depuis Firestore
  Future<List<NotificationModel>> _loadAllFromFirestore() async {
    try {
      final snapshot = await _notificationsCollection.orderBy('createdAt', descending: true).get();

      return snapshot.docs.map((doc) {
        final notification = NotificationModel.fromJson(doc.data(), doc.id);
        return _decryptNotification(notification);
      }).toList();
    } catch (e) {
      AppLogger.error('Error loading notifications from Firestore', e);
      rethrow;
    }
  }

  // Obtenir toutes les notifications
  Stream<List<NotificationModel>> getNotificationsStream() {
    AppLogger.debug('NotificationRepository: Starting notifications stream');

    return _notificationsCollection
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          AppLogger.debug(
            'NotificationRepository: Received snapshot with ${snapshot.docs.length} notifications',
          );

          final notifications =
              snapshot.docs.map((doc) {
                final notification = NotificationModel.fromJson(doc.data(), doc.id);
                return _decryptNotification(notification);
              }).toList();

          // Mettre à jour le cache avec les nouvelles données
          _updateCache(notifications);

          return notifications;
        })
        .handleError((error) {
          AppLogger.error('NotificationRepository: Stream error', error);

          // En cas d'erreur de stream, retourner le cache si disponible
          if (_isCacheInitialized) {
            return _cachedNotifications;
          }
          return <NotificationModel>[];
        });
  }

  // Méthode pour mettre à jour le cache
  void _updateCache(List<NotificationModel> notifications) {
    _cachedNotifications.clear();
    _cachedNotifications.addAll(notifications);
    _isCacheInitialized = true;
    _lastCacheUpdate = DateTime.now();
  }

  // Méthode pour invalider le cache
  void invalidateCache() {
    _isCacheInitialized = false;
    _cachedNotifications.clear();
    AppLogger.debug('Notification cache invalidated');
  }

  // Méthode pour forcer le rechargement
  Future<List<NotificationModel>> forceReload() async {
    invalidateCache();
    return getAllNotifications();
  }

  // Déchiffrer les données sensibles d'une notification (méthode existante inchangée)
  NotificationModel _decryptNotification(NotificationModel notification) {
    try {
      // Déchiffrer le nom du patient si présent
      String? decryptedPatientName;
      if (notification.patientName != null) {
        decryptedPatientName = _encryptionService.decrypt(notification.patientName!);
      }

      // Déchiffrer le nom du médicament si présent
      String? decryptedMedicamentName;
      if (notification.medicamentName != null) {
        decryptedMedicamentName = _encryptionService.decrypt(notification.medicamentName!);
      }

      // Mettre à jour le corps du message avec les données déchiffrées
      var updatedBody = notification.body;
      if (notification.medicamentName != null && decryptedMedicamentName != null) {
        updatedBody = updatedBody.replaceAll(notification.medicamentName!, decryptedMedicamentName);
      }

      return notification.copyWith(
        patientName: decryptedPatientName,
        medicamentName: decryptedMedicamentName,
        body: updatedBody,
      );
    } catch (e) {
      AppLogger.error('Error decrypting notification data', e);
      return notification;
    }
  }

  Future<void> deleteNotification(String notificationId) async {
    try {
      await _notificationsCollection.doc(notificationId).delete();

      // Invalider le cache après suppression
      invalidateCache();

      AppLogger.debug('Notification deleted: $notificationId');
    } catch (e) {
      AppLogger.error('Error deleting notification', e);
      rethrow;
    }
  }

  Future<NotificationModel?> getNotificationById(String notificationId) async {
    try {
      // Vérifier d'abord dans le cache
      if (_isCacheInitialized) {
        final cachedNotification =
            _cachedNotifications.where((n) => n.id == notificationId).firstOrNull;
        if (cachedNotification != null) {
          return cachedNotification;
        }
      }

      // Si pas trouvé dans le cache, charger depuis Firestore
      final doc = await _notificationsCollection.doc(notificationId).get();
      if (!doc.exists) {
        return null;
      }

      final notification = NotificationModel.fromJson(doc.data()!, doc.id);
      return _decryptNotification(notification);
    } catch (e) {
      AppLogger.error('Error getting notification by ID', e);
      return null;
    }
  }
}
