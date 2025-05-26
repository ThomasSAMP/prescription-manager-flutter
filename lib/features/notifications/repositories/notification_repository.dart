// lib/features/notifications/repositories/notification_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';

import '../../../core/utils/logger.dart';
import '../models/notification_model.dart';

@lazySingleton
class NotificationRepository {
  final FirebaseFirestore _firestore;

  NotificationRepository(this._firestore);

  // Collection Firestore pour les notifications
  CollectionReference<Map<String, dynamic>> get _notificationsCollection =>
      _firestore.collection('notifications');

  // Obtenir toutes les notifications
  Stream<List<NotificationModel>> getNotificationsStream() {
    return _notificationsCollection.orderBy('createdAt', descending: true).snapshots().map((
      snapshot,
    ) {
      return snapshot.docs.map((doc) {
        return NotificationModel.fromJson(doc.data(), doc.id);
      }).toList();
    });
  }

  // Marquer une notification comme lue
  Future<void> markAsRead(String notificationId) async {
    try {
      await _notificationsCollection.doc(notificationId).update({'read': true});
      AppLogger.debug('Notification marked as read: $notificationId');
    } catch (e) {
      AppLogger.error('Error marking notification as read', e);
      rethrow;
    }
  }

  // Marquer toutes les notifications comme lues
  Future<void> markAllAsRead() async {
    try {
      final batch = _firestore.batch();
      final snapshot = await _notificationsCollection.where('read', isEqualTo: false).get();

      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {'read': true});
      }

      await batch.commit();
      AppLogger.debug('All notifications marked as read');
    } catch (e) {
      AppLogger.error('Error marking all notifications as read', e);
      rethrow;
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

  // Supprimer toutes les notifications
  Future<void> deleteAllNotifications() async {
    try {
      final batch = _firestore.batch();
      final snapshot = await _notificationsCollection.get();

      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
      AppLogger.debug('All notifications deleted');
    } catch (e) {
      AppLogger.error('Error deleting all notifications', e);
      rethrow;
    }
  }

  // Supprimer les notifications d'un groupe spécifique
  Future<void> deleteNotificationGroup(String group) async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final lastWeek = today.subtract(const Duration(days: 7));

      DateTime? startDate;
      DateTime? endDate;

      switch (group) {
        case 'Aujourd\'hui':
          startDate = today;
          endDate = now;
          break;
        case 'Hier':
          startDate = yesterday;
          endDate = today;
          break;
        case 'Cette semaine':
          startDate = lastWeek;
          endDate = yesterday;
          break;
        case 'Plus ancien':
          endDate = lastWeek;
          break;
      }

      final batch = _firestore.batch();
      QuerySnapshot<Map<String, dynamic>> snapshot;

      if (startDate != null && endDate != null) {
        snapshot =
            await _notificationsCollection
                .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
                .where('createdAt', isLessThan: Timestamp.fromDate(endDate))
                .get();
      } else if (endDate != null) {
        snapshot =
            await _notificationsCollection
                .where('createdAt', isLessThan: Timestamp.fromDate(endDate))
                .get();
      } else {
        throw Exception('Invalid date group');
      }

      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
      AppLogger.debug('Notifications from group $group deleted');
    } catch (e) {
      AppLogger.error('Error deleting notification group', e);
      rethrow;
    }
  }
}
