import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/injection.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/utils/logger.dart';
import '../../../shared/providers/auth_provider.dart';
import '../models/notification_model.dart';
import '../models/notification_state_model.dart';
import '../repositories/notification_state_repository.dart';
import 'notification_provider.dart';

final notificationStateRepositoryProvider = Provider<NotificationStateRepository>((ref) {
  return getIt<NotificationStateRepository>();
});

// Provider pour les états de notification de l'utilisateur actuel
final userNotificationStatesProvider = StreamProvider<List<NotificationStateModel>>((ref) {
  final authState = ref.watch(authStateProvider);

  AppLogger.debug('userNotificationStatesProvider: Auth state changed');

  return authState.when(
    data: (user) {
      if (user == null) {
        AppLogger.debug('userNotificationStatesProvider: User is null, returning empty list');
        return Stream.value([]);
      }

      AppLogger.debug('userNotificationStatesProvider: User authenticated with ID: ${user.uid}');
      final repository = ref.watch(notificationStateRepositoryProvider);
      return repository.getNotificationStatesForUser(user.uid);
    },
    loading: () {
      AppLogger.debug('userNotificationStatesProvider: Auth state loading');
      return Stream.value([]);
    },
    error: (error, stack) {
      AppLogger.error('userNotificationStatesProvider: Auth state error', error, stack);
      return Stream.value([]);
    },
  );
});

// Provider pour obtenir l'état d'une notification spécifique
final notificationStateProvider = Provider.family<NotificationStateModel?, String>((
  ref,
  notificationId,
) {
  final statesAsync = ref.watch(userNotificationStatesProvider);

  return statesAsync.when(
    data: (states) {
      return states.firstWhere(
        (state) => state.notificationId == notificationId,
        orElse:
            () => NotificationStateModel(
              id: 'temp-$notificationId',
              notificationId: notificationId,
              userId: getIt<AuthService>().currentUser?.uid ?? '',
              isRead: false,
              isHidden: false,
              updatedAt: DateTime.now(),
            ),
      );
    },
    loading: () => null,
    error: (_, __) => null,
  );
});

// Provider pour les notifications avec leur état
final notificationsWithStateProvider = Provider<List<NotificationWithState>>((ref) {
  final authState = ref.watch(authStateProvider);

  // Court-circuiter si l'authentification est en cours ou si l'utilisateur n'est pas connecté
  if (authState is! AsyncData || authState.value == null) {
    return [];
  }

  final notificationsAsync = ref.watch(notificationsStreamProvider);
  final statesAsync = ref.watch(userNotificationStatesProvider);

  // Court-circuiter si l'un des streams n'a pas encore de données
  if (notificationsAsync is! AsyncData || statesAsync is! AsyncData) {
    return [];
  }

  // Court-circuiter si l'un des streams est en chargement
  if (notificationsAsync is AsyncLoading || statesAsync is AsyncLoading) {
    return [];
  }

  // Court-circuiter si l'un des streams est en erreur
  if (notificationsAsync is AsyncError || statesAsync is AsyncError) {
    return [];
  }

  final user = authState.value!;
  final notifications = notificationsAsync.value ?? [];
  final states = statesAsync.value ?? [];

  return notifications.map((notification) {
    final state = states.firstWhere(
      (state) => state.notificationId == notification.id,
      orElse:
          () => NotificationStateModel(
            id: 'temp-${notification.id}',
            notificationId: notification.id,
            userId: user.uid,
            isRead: false,
            isHidden: false,
            updatedAt: DateTime.now(),
          ),
    );

    return NotificationWithState(notification: notification, state: state);
  }).toList();
});

// Provider pour les notifications groupées avec leur état
final groupedNotificationsWithStateProvider = Provider<Map<String, List<NotificationWithState>>>((
  ref,
) {
  final notificationsWithState = ref.watch(notificationsWithStateProvider);

  // Court-circuiter si la liste est vide
  if (notificationsWithState.isEmpty) {
    return {};
  }

  // Filtrer les notifications cachées
  final visibleNotifications = notificationsWithState.where((n) => !n.state.isHidden).toList();

  final grouped = <String, List<NotificationWithState>>{};

  for (final notificationWithState in visibleNotifications) {
    final group = notificationWithState.notification.getDateGroup();
    if (!grouped.containsKey(group)) {
      grouped[group] = [];
    }
    grouped[group]!.add(notificationWithState);
  }

  return grouped;
});

// Provider pour le nombre de notifications non lues
final unreadNotificationsCountProvider = Provider<int>((ref) {
  final notificationsWithStateAsync = ref.watch(notificationsWithStateProvider);
  return notificationsWithStateAsync.where((n) => !n.state.isRead && !n.state.isHidden).length;
});

// Classe pour combiner une notification avec son état
class NotificationWithState {
  final NotificationModel notification;
  final NotificationStateModel state;

  NotificationWithState({required this.notification, required this.state});
}
