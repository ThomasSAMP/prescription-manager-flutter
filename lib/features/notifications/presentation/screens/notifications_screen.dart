import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/navigation_service.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/utils/refresh_helper.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/widgets/app_bar.dart';
import '../../../../shared/widgets/shimmer_loading.dart';
import '../../../../shared/widgets/shimmer_placeholder.dart';
import '../../providers/notification_provider.dart';
import '../../providers/notification_state_provider.dart';
import '../widgets/notification_skeleton_item.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Déclencher le chargement après le premier rendu
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerLoading();
    });
  }

  // Méthode pour déclencher le chargement sans bloquer l'UI
  void _triggerLoading() {
    // Déclencher le chargement sans await pour afficher le skeleton immédiatement si nécessaire
    unawaited(ref.read(notificationsProvider.notifier).loadItems());
  }

  // Méthode pour le pull-to-refresh
  Future<void> _refreshData() async {
    await RefreshHelper.refreshData(
      context: context,
      ref: ref,
      onlineRefresh: () async {
        // Ici nous voulons attendre, donc pas de unawaited
        await ref.read(notificationsProvider.notifier).forceReload();
      },
      offlineRefresh: () async {
        // Ici aussi nous voulons attendre
        await ref.read(notificationsProvider.notifier).loadItems();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    AppLogger.debug('NotificationsScreen: Building');

    final navigationService = getIt<NavigationService>();
    final authState = ref.watch(authStateProvider);
    final notificationsState = ref.watch(notificationsProvider);
    final isLoading = notificationsState.isLoading;

    // Si l'authentification est en cours de chargement, afficher le skeleton
    if (authState is AsyncLoading) {
      return Scaffold(
        appBar: const AppBarWidget(title: 'Notifications', showBackButton: false),
        body: _buildLoadingState(),
      );
    }

    // Si erreur d'authentification
    if (authState is AsyncError) {
      AppLogger.error(
        'NotificationsScreen: Auth state error',
        authState.error,
        authState.stackTrace,
      );
      return Scaffold(
        appBar: const AppBarWidget(title: 'Notifications', showBackButton: false),
        body: Center(child: Text('Erreur d\'authentification: ${authState.error}')),
      );
    }

    // Si utilisateur non connecté
    final user = authState.value;
    if (user == null) {
      AppLogger.debug('NotificationsScreen: User is null');
      return const Scaffold(
        appBar: AppBarWidget(title: 'Notifications', showBackButton: false),
        body: Center(child: Text('Vous devez être connecté pour voir vos notifications')),
      );
    }

    // À ce stade, nous avons l'utilisateur connecté
    final groupedNotifications = ref.watch(groupedNotificationsWithStateProvider);

    return Scaffold(
      appBar: AppBarWidget(
        title: 'Notifications',
        showBackButton: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            onPressed: () async {
              // Confirmer l'action
              final confirm = await navigationService.showConfirmationDialog(
                context,
                title: 'Marquer comme lu',
                message: 'Marquer toutes les notifications comme lues ?',
                confirmText: 'Marquer comme lu',
                cancelText: 'Annuler',
              );

              if (confirm == true) {
                final repository = ref.read(notificationStateRepositoryProvider);
                // Ici nous voulons attendre car l'utilisateur s'attend à voir le changement
                await repository.markAllAsRead(user.uid);
                navigationService.showSnackBar(
                  context,
                  message: 'Toutes les notifications ont été marquées comme lues',
                );
              }
            },
            tooltip: 'Marquer tout comme lu',
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () async {
              final userId = getIt<AuthService>().currentUser?.uid;
              if (userId == null) return;

              // Confirmer l'action
              final confirm = await navigationService.showConfirmationDialog(
                context,
                title: 'Supprimer tout',
                message: 'Supprimer toutes les notifications ?',
                confirmText: 'Supprimer',
                cancelText: 'Annuler',
              );

              if (confirm == true) {
                // Marquer toutes les notifications comme cachées
                final notificationStateRepository = ref.read(notificationStateRepositoryProvider);
                final allNotifications = ref.read(notificationsWithStateProvider);

                // Ici nous voulons attendre car l'utilisateur s'attend à voir le changement
                for (final notificationWithState in allNotifications) {
                  await notificationStateRepository.markAsHidden(
                    notificationWithState.notification.id,
                    userId,
                  );
                }

                navigationService.showSnackBar(
                  context,
                  message: 'Toutes les notifications ont été supprimées',
                );
              }
            },
            tooltip: 'Supprimer tout',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: _buildNotificationsList(isLoading, groupedNotifications, navigationService),
      ),
    );
  }

  Widget _buildNotificationsList(
    bool isLoading,
    Map<String, List<NotificationWithState>> groupedNotifications,
    NavigationService navigationService,
  ) {
    // Si en chargement, afficher les skeletons
    if (isLoading) {
      return _buildLoadingState();
    }

    // Si aucune notification après filtrage, afficher l'état vide
    if (groupedNotifications.isEmpty) {
      return _buildEmptyState();
    }

    // Sinon, afficher la liste des notifications
    return ListView.builder(
      itemCount: groupedNotifications.length,
      itemBuilder: (context, index) {
        final group = groupedNotifications.keys.elementAt(index);
        final groupNotifications = groupedNotifications[group]!;

        return _buildNotificationGroup(context, ref, group, groupNotifications);
      },
    );
  }

  Widget _buildLoadingState() {
    return ListView(
      children: [
        // Premier groupe
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 30, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ShimmerLoading(isLoading: true, child: ShimmerPlaceholder(width: 100, height: 16)),
              ShimmerLoading(isLoading: true, child: ShimmerPlaceholder(width: 80, height: 14)),
            ],
          ),
        ),
        const SizedBox(height: 25),
        ...List.generate(
          7,
          (index) => const Padding(
            padding: EdgeInsets.only(bottom: 8.0),
            child: ShimmerLoading(isLoading: true, child: NotificationSkeletonItem()),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_off_outlined, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('Aucune notification', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text(
            'Vous recevrez des notifications lorsque des médicaments arriveront à expiration',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationGroup(
    BuildContext context,
    WidgetRef ref,
    String group,
    List<NotificationWithState> notifications,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                group,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.delete, size: 16),
                label: const Text('Supprimer'),
                onPressed: () async {
                  final userId = getIt<AuthService>().currentUser?.uid;
                  if (userId == null) return;

                  // Confirmer l'action
                  final confirm = await getIt<NavigationService>().showConfirmationDialog(
                    context,
                    title: 'Supprimer le groupe',
                    message: 'Supprimer toutes les notifications de "$group" ?',
                    confirmText: 'Supprimer',
                    cancelText: 'Annuler',
                  );

                  if (confirm == true) {
                    // Marquer toutes les notifications du groupe comme cachées
                    final notificationStateRepository = ref.read(
                      notificationStateRepositoryProvider,
                    );
                    for (final notificationWithState in notifications) {
                      await notificationStateRepository.markAsHidden(
                        notificationWithState.notification.id,
                        userId,
                      );
                    }

                    getIt<NavigationService>().showSnackBar(
                      context,
                      message: 'Notifications de "$group" supprimées',
                    );
                  }
                },
              ),
            ],
          ),
        ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: notifications.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final notificationWithState = notifications[index];
            return _buildNotificationItem(context, ref, notificationWithState);
          },
        ),
        const Divider(thickness: 1),
      ],
    );
  }

  Widget _buildNotificationItem(
    BuildContext context,
    WidgetRef ref,
    NotificationWithState notificationWithState,
  ) {
    final notification = notificationWithState.notification;
    final state = notificationWithState.state;
    final dateFormat = DateFormat('HH:mm');
    final navigationService = getIt<NavigationService>();
    final notificationStateRepository = ref.read(notificationStateRepositoryProvider);
    final userId = getIt<AuthService>().currentUser?.uid;

    return Dismissible(
      key: Key(notification.id),
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      direction: DismissDirection.endToStart,
      onDismissed: (direction) async {
        // Marquer comme caché plutôt que de supprimer
        if (userId != null) {
          await notificationStateRepository.markAsHidden(notification.id, userId);
        }

        navigationService.showSnackBar(
          context,
          message: 'Notification supprimée',
          action: SnackBarAction(
            label: 'Annuler',
            onPressed: () async {
              // Annuler la suppression en marquant comme non caché
              if (userId != null) {
                await notificationStateRepository.setNotificationState(
                  notificationId: notification.id,
                  userId: userId,
                  isHidden: false,
                );
              }
            },
          ),
        );
      },
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: notification.getColor().withOpacity(0.2),
          child: Icon(notification.getIcon(), color: notification.getColor()),
        ),
        title: Text(
          notification.title,
          style: TextStyle(fontWeight: state.isRead ? FontWeight.normal : FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(notification.body),
            if (notification.patientName != null) ...[
              const SizedBox(height: 4),
              Text(
                'Patient: ${notification.patientName}',
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              dateFormat.format(notification.createdAt),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        trailing:
            state.isRead
                ? IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    if (userId != null) {
                      await notificationStateRepository.markAsHidden(notification.id, userId);
                    }
                  },
                )
                : Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
        onTap: () async {
          // Marquer comme lu
          if (!state.isRead && userId != null) {
            await notificationStateRepository.markAsRead(notification.id, userId);
          }

          // Naviguer vers l'ordonnance si disponible
          if (notification.ordonnanceId != null) {
            context.go(
              '/ordonnances/${notification.ordonnanceId}',
              extra: {'fromNotifications': true},
            );
          }
        },
      ),
    );
  }
}
