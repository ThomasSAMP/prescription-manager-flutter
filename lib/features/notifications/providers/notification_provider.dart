import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/injection.dart';
import '../models/notification_model.dart';
import '../repositories/notification_repository.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return getIt<NotificationRepository>();
});

final notificationsStreamProvider = StreamProvider<List<NotificationModel>>((ref) {
  final repository = ref.watch(notificationRepositoryProvider);
  return repository.getNotificationsStream();
});

// Provider pour les notifications groupées par date
final groupedNotificationsProvider = Provider<Map<String, List<NotificationModel>>>((ref) {
  final notificationsAsyncValue = ref.watch(notificationsStreamProvider);

  return notificationsAsyncValue.when(
    data: (notifications) {
      final grouped = <String, List<NotificationModel>>{};

      for (final notification in notifications) {
        final group = notification.getDateGroup();
        if (!grouped.containsKey(group)) {
          grouped[group] = [];
        }
        grouped[group]!.add(notification);
      }

      return grouped;
    },
    loading: () => {},
    error: (_, __) => {},
  );
});

// Provider pour le nombre de notifications non lues
final unreadNotificationsCountProvider = Provider<int>((ref) {
  final notificationsAsyncValue = ref.watch(notificationsStreamProvider);

  return notificationsAsyncValue.when(
    data: (notifications) {
      return notifications.where((notification) => !notification.read).length;
    },
    loading: () => 0,
    error: (_, __) => 0,
  );
});
