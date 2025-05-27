import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';

import '../../../core/services/encryption_service.dart';
import '../../../core/utils/logger.dart';
import '../models/notification_model.dart';

@lazySingleton
class NotificationRepository {
  final FirebaseFirestore _firestore;
  final EncryptionService _encryptionService;

  NotificationRepository(this._firestore, this._encryptionService);

  // Collection Firestore pour les notifications
  CollectionReference<Map<String, dynamic>> get _notificationsCollection =>
      _firestore.collection('notifications');

  // Obtenir toutes les notifications
  Stream<List<NotificationModel>> getNotificationsStream() {
    return _notificationsCollection.orderBy('createdAt', descending: true).snapshots().map((
      snapshot,
    ) {
      return snapshot.docs.map((doc) {
        final notification = NotificationModel.fromJson(doc.data(), doc.id);
        return _decryptNotification(notification);
      }).toList();
    });
  }

  // Déchiffrer les données sensibles d'une notification
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

  // Supprimer une notification
  Future<void> deleteNotification(String notificationId) async {
    try {
      await _notificationsCollection.doc(notificationId).delete();
      AppLogger.debug('Notification deleted: $notificationId');
    } catch (e) {
      AppLogger.error('Error deleting notification', e);
      rethrow;
    }
  }

  // Obtenir une notification par ID
  Future<NotificationModel?> getNotificationById(String notificationId) async {
    try {
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
