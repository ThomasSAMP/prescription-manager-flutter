import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

import '../../../core/utils/logger.dart';
import '../models/notification_state_model.dart';

@lazySingleton
class NotificationStateRepository {
  final FirebaseFirestore _firestore;
  final Uuid _uuid = const Uuid();

  NotificationStateRepository(this._firestore);

  // Collection Firestore pour les états de notification
  CollectionReference<Map<String, dynamic>> get _notificationStatesCollection =>
      _firestore.collection('notification_states');

  // Obtenir l'état d'une notification pour un utilisateur spécifique
  Future<NotificationStateModel?> getNotificationState(String notificationId, String userId) async {
    try {
      final query =
          await _notificationStatesCollection
              .where('notificationId', isEqualTo: notificationId)
              .where('userId', isEqualTo: userId)
              .limit(1)
              .get();

      if (query.docs.isEmpty) {
        return null;
      }

      final doc = query.docs.first;
      return NotificationStateModel.fromJson(doc.data(), doc.id);
    } catch (e) {
      AppLogger.error('Error getting notification state', e);
      return null;
    }
  }

  // Créer ou mettre à jour l'état d'une notification
  Future<NotificationStateModel> setNotificationState({
    required String notificationId,
    required String userId,
    bool? isRead,
    bool? isHidden,
  }) async {
    try {
      // Vérifier si l'état existe déjà
      final existingState = await getNotificationState(notificationId, userId);

      if (existingState != null) {
        // Mettre à jour l'état existant
        final updatedState = existingState.copyWith(
          isRead: isRead,
          isHidden: isHidden,
          updatedAt: DateTime.now(),
        );

        await _notificationStatesCollection.doc(existingState.id).update(updatedState.toJson());
        return updatedState;
      } else {
        // Créer un nouvel état
        final newState = NotificationStateModel(
          id: _uuid.v4(),
          notificationId: notificationId,
          userId: userId,
          isRead: isRead ?? false,
          isHidden: isHidden ?? false,
          updatedAt: DateTime.now(),
        );

        await _notificationStatesCollection.doc(newState.id).set(newState.toJson());
        return newState;
      }
    } catch (e) {
      AppLogger.error('Error setting notification state', e);
      throw Exception('Failed to set notification state: ${e.toString()}');
    }
  }

  // Marquer une notification comme lue
  Future<void> markAsRead(String notificationId, String userId) async {
    try {
      await setNotificationState(notificationId: notificationId, userId: userId, isRead: true);
      AppLogger.debug('Notification marked as read: $notificationId for user: $userId');
    } catch (e) {
      AppLogger.error('Error marking notification as read', e);
      throw Exception('Failed to mark notification as read: ${e.toString()}');
    }
  }

  // Marquer une notification comme cachée
  Future<void> markAsHidden(String notificationId, String userId) async {
    try {
      await setNotificationState(notificationId: notificationId, userId: userId, isHidden: true);
      AppLogger.debug('Notification marked as hidden: $notificationId for user: $userId');
    } catch (e) {
      AppLogger.error('Error marking notification as hidden', e);
      throw Exception('Failed to mark notification as hidden: ${e.toString()}');
    }
  }

  // Marquer toutes les notifications comme lues pour un utilisateur
  Future<void> markAllAsRead(String userId) async {
    try {
      // Obtenir toutes les notifications non lues pour cet utilisateur
      final batch = _firestore.batch();
      final states =
          await _notificationStatesCollection
              .where('userId', isEqualTo: userId)
              .where('isRead', isEqualTo: false)
              .get();

      for (var doc in states.docs) {
        batch.update(doc.reference, {'isRead': true, 'updatedAt': FieldValue.serverTimestamp()});
      }

      await batch.commit();
      AppLogger.debug('All notifications marked as read for user: $userId');
    } catch (e) {
      AppLogger.error('Error marking all notifications as read', e);
      throw Exception('Failed to mark all notifications as read: ${e.toString()}');
    }
  }

  // Obtenir tous les états de notification pour un utilisateur
  Stream<List<NotificationStateModel>> getNotificationStatesForUser(String userId) {
    AppLogger.debug('getNotificationStatesForUser called for userId: $userId');

    try {
      return _notificationStatesCollection
          .where('userId', isEqualTo: userId)
          .snapshots()
          .map((snapshot) {
            AppLogger.debug(
              'getNotificationStatesForUser: Received snapshot with ${snapshot.docs.length} docs',
            );
            return snapshot.docs.map((doc) {
              return NotificationStateModel.fromJson(doc.data(), doc.id);
            }).toList();
          })
          .handleError((error) {
            AppLogger.error('getNotificationStatesForUser: Stream error', error);
            return <NotificationStateModel>[];
          });
    } catch (e) {
      AppLogger.error('getNotificationStatesForUser: Setup error', e);
      return Stream.value([]);
    }
  }
}
