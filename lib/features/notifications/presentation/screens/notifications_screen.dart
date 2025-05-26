import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/navigation_service.dart';
import '../../../../shared/widgets/app_bar.dart';
import '../../models/notification_model.dart';
import '../../providers/notification_provider.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigationService = getIt<NavigationService>();
    final notificationsAsyncValue = ref.watch(notificationsStreamProvider);
    final groupedNotifications = ref.watch(groupedNotificationsProvider);

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
                final repository = ref.read(notificationRepositoryProvider);
                await repository.markAllAsRead();
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
              // Confirmer l'action
              final confirm = await navigationService.showConfirmationDialog(
                context,
                title: 'Supprimer tout',
                message: 'Supprimer toutes les notifications ?',
                confirmText: 'Supprimer',
                cancelText: 'Annuler',
              );

              if (confirm == true) {
                final repository = ref.read(notificationRepositoryProvider);
                await repository.deleteAllNotifications();
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
      body: notificationsAsyncValue.when(
        data: (notifications) {
          if (notifications.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.builder(
            itemCount: groupedNotifications.length,
            itemBuilder: (context, index) {
              final group = groupedNotifications.keys.elementAt(index);
              final groupNotifications = groupedNotifications[group]!;

              return _buildNotificationGroup(context, ref, group, groupNotifications);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (error, stackTrace) =>
                Center(child: Text('Erreur lors du chargement des notifications: $error')),
      ),
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
    List<NotificationModel> notifications,
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
                  // Confirmer l'action
                  final confirm = await getIt<NavigationService>().showConfirmationDialog(
                    context,
                    title: 'Supprimer le groupe',
                    message: 'Supprimer toutes les notifications de "$group" ?',
                    confirmText: 'Supprimer',
                    cancelText: 'Annuler',
                  );

                  if (confirm == true) {
                    final repository = ref.read(notificationRepositoryProvider);
                    await repository.deleteNotificationGroup(group);
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
            final notification = notifications[index];
            return _buildNotificationItem(context, ref, notification);
          },
        ),
        const Divider(thickness: 1),
      ],
    );
  }

  Widget _buildNotificationItem(
    BuildContext context,
    WidgetRef ref,
    NotificationModel notification,
  ) {
    final dateFormat = DateFormat('HH:mm');
    final navigationService = getIt<NavigationService>();
    final repository = ref.read(notificationRepositoryProvider);

    return Dismissible(
      key: Key(notification.id),
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      direction: DismissDirection.endToStart,
      onDismissed: (direction) {
        repository.deleteNotification(notification.id);
        navigationService.showSnackBar(
          context,
          message: 'Notification supprimée',
          action: SnackBarAction(
            label: 'Annuler',
            onPressed: () {
              // La logique pour annuler la suppression irait ici
              // Mais comme nous n'avons pas de méthode pour recréer une notification,
              // cette fonctionnalité n'est pas implémentée
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
          style: TextStyle(fontWeight: notification.read ? FontWeight.normal : FontWeight.bold),
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
            notification.read
                ? IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => repository.deleteNotification(notification.id),
                )
                : Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
        onTap: () {
          // Marquer comme lu
          if (!notification.read) {
            repository.markAsRead(notification.id);
          }

          // Naviguer vers l'ordonnance si disponible
          if (notification.ordonnanceId != null) {
            context.go('/ordonnances/${notification.ordonnanceId}');
          }
        },
      ),
    );
  }
}
