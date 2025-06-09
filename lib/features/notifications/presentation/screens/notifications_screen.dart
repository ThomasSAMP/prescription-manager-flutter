import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/navigation_service.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/utils/refresh_helper.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/widgets/app_bar.dart';
import '../../../../shared/widgets/shimmer_loading.dart';
import '../../../../shared/widgets/shimmer_placeholder.dart';
import '../../models/medication_alert_model.dart';
import '../../providers/medication_alert_provider.dart';
import '../../repositories/medication_alert_repository.dart';
import '../widgets/medication_alert_skeleton_item.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  final bool fromNotification;
  final bool forceRefresh;

  const NotificationsScreen({super.key, this.fromNotification = false, this.forceRefresh = false});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerLoading();
    });
  }

  void _triggerLoading() {
    if (widget.fromNotification && widget.forceRefresh) {
      unawaited(ref.read(medicationAlertsProvider.notifier).forceReload());
    } else {
      unawaited(ref.read(medicationAlertsProvider.notifier).loadItems());
    }
  }

  Future<void> _clearNotificationCollections() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Appeler la fonction Cloud
      final callable = FirebaseFunctions.instanceFor(
        region: 'europe-west1',
      ).httpsCallable('clearNotificationCollections');

      AppLogger.info('Calling Cloud Function to clear notification collections...');

      final result = await callable.call();
      final data = result.data as Map<String, dynamic>;

      AppLogger.info('Cloud Function result: $data');

      // Invalider les caches locaux
      final medicationAlertRepository = getIt<MedicationAlertRepository>();
      medicationAlertRepository.invalidateCache();

      // Rafraîchir les providers
      ref.refresh(medicationAlertsProvider);

      if (mounted) {
        final totalDeleted = data['totalDeleted'] ?? 0;
        final collections = data['collections'] as Map<String, dynamic>? ?? {};

        var detailMessage = 'Collections nettoyées :\n';
        collections.forEach((collection, count) {
          detailMessage += '• $collection: $count documents\n';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $detailMessage\nTotal: $totalDeleted documents supprimés'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error calling clearNotificationCollections function', e, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erreur lors du nettoyage: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshData() async {
    try {
      AppLogger.debug('NotificationsScreen: Starting refresh');

      await RefreshHelper.refreshData(
        context: context,
        ref: ref,
        onlineRefresh: () async {
          AppLogger.debug('NotificationsScreen: Force reloading alerts');
          await ref.read(medicationAlertsProvider.notifier).forceReload();
        },
        offlineRefresh: () async {
          AppLogger.debug('NotificationsScreen: Loading alerts from cache');
          await ref.read(medicationAlertsProvider.notifier).loadItems();
        },
      );

      AppLogger.debug('NotificationsScreen: Refresh completed');
    } catch (e) {
      AppLogger.error('NotificationsScreen: Error during refresh', e);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de l\'actualisation: ${e.toString()}'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Réessayer',
              textColor: Colors.white,
              onPressed: _refreshData,
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLogger.debug('NotificationsScreen: Building');

    final navigationService = getIt<NavigationService>();
    final authState = ref.watch(authStateProvider);
    final alertsState = ref.watch(medicationAlertsProvider);
    final isLoading = alertsState.isLoading;

    // Si l'authentification est en cours de chargement
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

    // Obtenir les alertes groupées pour cet utilisateur
    final groupedAlerts = ref.watch(groupedMedicationAlertsProvider);

    return Scaffold(
      appBar: AppBarWidget(
        title: 'Notifications',
        showBackButton: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            onPressed: () async {
              final confirm = await navigationService.showConfirmationDialog(
                context,
                title: 'Marquer comme lu',
                message: 'Marquer toutes les notifications comme lues ?',
                confirmText: 'Marquer comme lu',
                cancelText: 'Annuler',
              );

              if (confirm == true) {
                try {
                  await ref.read(medicationAlertsProvider.notifier).markAllAsRead(user.uid);
                  navigationService.showSnackBar(
                    context,
                    message: 'Toutes les notifications ont été marquées comme lues',
                  );
                } catch (e) {
                  navigationService.showSnackBar(
                    context,
                    message: 'Erreur lors de la mise à jour: $e',
                  );
                }
              }
            },
            tooltip: 'Marquer tout comme lu',
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () async {
              final confirm = await navigationService.showConfirmationDialog(
                context,
                title: 'Supprimer tout',
                message: 'Supprimer toutes les notifications ?',
                confirmText: 'Supprimer',
                cancelText: 'Annuler',
              );

              if (confirm == true) {
                try {
                  await ref.read(medicationAlertsProvider.notifier).markAllAsHidden(user.uid);
                  navigationService.showSnackBar(
                    context,
                    message: 'Toutes les notifications ont été supprimées',
                  );
                } catch (e) {
                  navigationService.showSnackBar(
                    context,
                    message: 'Erreur lors de la suppression: $e',
                  );
                }
              }
            },
            tooltip: 'Supprimer tout',
          ),
          // BOUTON TEMPORAIRE
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.orange),
            onPressed: () async {
              final confirm = await navigationService.showConfirmationDialog(
                context,
                title: 'Reset notifications (DEV)',
                message: 'Remettre toutes les notifications à l\'état non-lu et visible ?',
                confirmText: 'Reset',
                cancelText: 'Annuler',
              );

              if (confirm == true) {
                try {
                  await ref
                      .read(medicationAlertsProvider.notifier)
                      .resetAllUserNotifications(user.uid);
                  navigationService.showSnackBar(
                    context,
                    message: 'Toutes les notifications ont été remises à zéro',
                  );
                } catch (e) {
                  navigationService.showSnackBar(context, message: 'Erreur lors du reset: $e');
                }
              }
            },
            tooltip: 'Reset notifications (DEV)',
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.red),
            onPressed:
                _isLoading
                    ? null
                    : () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder:
                            (context) => AlertDialog(
                              title: const Text('⚠️ Attention'),
                              content: const Text(
                                'Cette action va supprimer TOUTES les données des collections :\n\n'
                                '• daily_stats\n'
                                '• medication_alerts\n'
                                '• medication_tracking\n'
                                '• notification_logs\n\n'
                                'Cette action est irréversible !\n\n'
                                'Continuer ?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(false),
                                  child: const Text('Annuler'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(true),
                                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                                  child: const Text('Supprimer'),
                                ),
                              ],
                            ),
                      );

                      if (confirm == true) {
                        await _clearNotificationCollections();
                      }
                    },
            tooltip: 'Reset notifications (DEV)',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: _buildAlertsList(isLoading, groupedAlerts, navigationService, user.uid),
      ),
    );
  }

  Widget _buildAlertsList(
    bool isLoading,
    Map<String, List<MedicationAlertModel>> groupedAlerts,
    NavigationService navigationService,
    String userId,
  ) {
    if (isLoading) {
      return _buildLoadingState();
    }

    if (groupedAlerts.isEmpty) {
      return _buildEmptyStateWithRefresh();
    }

    return ListView.builder(
      itemCount: groupedAlerts.length,
      itemBuilder: (context, index) {
        final group = groupedAlerts.keys.elementAt(index);
        final groupAlerts = groupedAlerts[group]!;

        return _buildAlertGroup(context, ref, group, groupAlerts, userId, index);
      },
    );
  }

  Widget _buildLoadingState() {
    return ListView(
      children: [
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
            child: ShimmerLoading(isLoading: true, child: MedicationAlertSkeletonItem()),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyStateWithRefresh() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Aucune notification',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Vous recevrez des notifications lorsque des médicaments arriveront à expiration',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertGroup(
    BuildContext context,
    WidgetRef ref,
    String group,
    List<MedicationAlertModel> alerts,
    String userId,
    int groupIndex,
  ) {
    return ExpansionTile(
      initiallyExpanded: groupIndex == 0,
      title: Text(
        group,
        style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            icon: const Icon(Icons.delete, size: 16),
            label: const Text('Supprimer'),
            onPressed: () async {
              final confirm = await getIt<NavigationService>().showConfirmationDialog(
                context,
                title: 'Supprimer le groupe',
                message: 'Supprimer toutes les notifications de "$group" ?',
                confirmText: 'Supprimer',
                cancelText: 'Annuler',
              );

              if (confirm == true) {
                try {
                  for (final alert in alerts) {
                    await ref
                        .read(medicationAlertsProvider.notifier)
                        .markAsHidden(alert.id, userId);
                  }

                  getIt<NavigationService>().showSnackBar(
                    context,
                    message: 'Notifications de "$group" supprimées',
                  );
                } catch (e) {
                  getIt<NavigationService>().showSnackBar(
                    context,
                    message: 'Erreur lors de la suppression: $e',
                  );
                }
              }
            },
          ),
          const Icon(Icons.expand_more),
        ],
      ),
      children: [
        // Retirez le Column et le Divider externe
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: alerts.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final alert = alerts[index];
            return _buildAlertItem(context, ref, alert, userId);
          },
        ),
      ],
    );
  }

  Widget _buildAlertItem(
    BuildContext context,
    WidgetRef ref,
    MedicationAlertModel alert,
    String userId,
  ) {
    final userState = alert.getUserState(userId);
    final dateFormat = DateFormat('HH:mm');
    final navigationService = getIt<NavigationService>();

    return Dismissible(
      key: Key(alert.id),
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      direction: DismissDirection.endToStart,
      onDismissed: (direction) async {
        try {
          await ref.read(medicationAlertsProvider.notifier).markAsHidden(alert.id, userId);

          navigationService.showSnackBar(
            context,
            message: 'Notification supprimée',
            action: SnackBarAction(
              label: 'Annuler',
              onPressed: () async {
                // Annuler la suppression
                try {
                  await ref
                      .read(medicationAlertRepositoryProvider)
                      .updateUserAlertState(alertId: alert.id, userId: userId, isHidden: false);
                  // Recharger les données
                  await ref.read(medicationAlertsProvider.notifier).refreshData();
                } catch (e) {
                  navigationService.showSnackBar(
                    context,
                    message: 'Erreur lors de l\'annulation: $e',
                  );
                }
              },
            ),
          );
        } catch (e) {
          navigationService.showSnackBar(context, message: 'Erreur lors de la suppression: $e');
        }
      },
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: alert.getColor().withOpacity(0.2),
          child: Icon(alert.getIcon(), color: alert.getColor()),
        ),
        title: Text(
          _buildAlertTitle(alert),
          style: TextStyle(fontWeight: userState.isRead ? FontWeight.normal : FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_buildAlertSubtitle(alert)),
            const SizedBox(height: 4),
            Text(
              'Patient: ${alert.patientName}',
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 4),
            Text(dateFormat.format(alert.createdAt), style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        trailing:
            userState.isRead
                ? IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    try {
                      await ref
                          .read(medicationAlertsProvider.notifier)
                          .markAsHidden(alert.id, userId);
                    } catch (e) {
                      navigationService.showSnackBar(
                        context,
                        message: 'Erreur lors de la suppression: $e',
                      );
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
          if (!userState.isRead) {
            try {
              await ref.read(medicationAlertsProvider.notifier).markAsRead(alert.id, userId);
            } catch (e) {
              navigationService.showSnackBar(context, message: 'Erreur lors de la mise à jour: $e');
            }
          }

          // Naviguer directement vers l'ordonnance sans passer par la liste
          context.go('/ordonnance/${alert.ordonnanceId}', extra: {'fromNotifications': true});
        },
      ),
    );
  }

  String _buildAlertTitle(MedicationAlertModel alert) {
    switch (alert.alertLevel) {
      case AlertLevel.expired:
        return 'Médicament expiré !';
      case AlertLevel.critical:
        return 'Médicament bientôt expiré !';
      case AlertLevel.warning:
        return 'Attention à l\'expiration';
    }
  }

  String _buildAlertSubtitle(MedicationAlertModel alert) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    final expirationDateStr = dateFormat.format(alert.expirationDate);

    switch (alert.alertLevel) {
      case AlertLevel.expired:
        return 'Le médicament ${alert.medicamentName} est expiré depuis le $expirationDateStr';
      case AlertLevel.critical:
        return 'Le médicament ${alert.medicamentName} expire le $expirationDateStr (moins de 14 jours)';
      case AlertLevel.warning:
        return 'Le médicament ${alert.medicamentName} expire le $expirationDateStr (moins de 30 jours)';
    }
  }
}
