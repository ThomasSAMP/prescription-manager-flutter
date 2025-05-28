// lib/features/settings/presentation/screens/notification_settings_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/navigation_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../shared/widgets/app_bar.dart';
import '../../../../shared/widgets/app_button.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends ConsumerState<NotificationSettingsScreen> {
  final _navigationService = getIt<NavigationService>();
  final _notificationService = getIt<NotificationService>();
  bool _isLoading = false;
  bool _notificationsEnabled = false;

  @override
  void initState() {
    super.initState();
    _checkNotificationPermission();
  }

  Future<void> _checkNotificationPermission() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final status = await Permission.notification.status;
      setState(() {
        _notificationsEnabled = status.isGranted;
      });
    } catch (e) {
      // Gérer l'erreur
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _requestNotificationPermission() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final status = await Permission.notification.request();
      setState(() {
        _notificationsEnabled = status.isGranted;
      });

      if (status.isGranted) {
        // S'abonner au topic pour tous les utilisateurs sans attendre
        unawaited(_notificationService.subscribeToAllUsers());

        if (mounted) {
          _navigationService.showSnackBar(context, message: 'Notifications activées avec succès');
        }
      } else if (status.isPermanentlyDenied) {
        if (mounted) {
          _navigationService.showSnackBar(
            context,
            message: 'Vous devez activer les notifications dans les paramètres de l\'appareil',
            action: const SnackBarAction(label: 'Ouvrir', onPressed: openAppSettings),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _navigationService.showSnackBar(
          context,
          message: 'Erreur lors de la demande d\'autorisation: $e',
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPop = context.canPop();

    return Scaffold(
      appBar: AppBarWidget(
        title: 'Paramètres de notification',
        showBackButton: canPop,
        leading:
            !canPop
                ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => _navigationService.navigateTo(context, '/settings'),
                )
                : null,
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Notifications push',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Les notifications push vous permettent de recevoir des alertes importantes, comme les médicaments qui arrivent à expiration.',
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Activer les notifications'),
                    subtitle: Text(
                      _notificationsEnabled
                          ? 'Les notifications sont activées'
                          : 'Les notifications sont désactivées',
                    ),
                    value: _notificationsEnabled,
                    onChanged: (value) {
                      if (value) {
                        _requestNotificationPermission();
                      } else {
                        _navigationService.showSnackBar(
                          context,
                          message:
                              'Pour désactiver les notifications, allez dans les paramètres de l\'appareil',
                          action: const SnackBarAction(label: 'Ouvrir', onPressed: openAppSettings),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  if (!_notificationsEnabled)
                    AppButton(
                      text: 'Activer les notifications',
                      onPressed: _requestNotificationPermission,
                      icon: Icons.notifications_active,
                    ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Text(
                    'Fréquence des vérifications',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Les médicaments sont vérifiés automatiquement tous les jours à 8h du matin pour détecter ceux qui arrivent à expiration.',
                  ),
                  const SizedBox(height: 16),
                  const ListTile(
                    leading: Icon(Icons.schedule),
                    title: Text('Vérification quotidienne'),
                    subtitle: Text('Tous les jours à 8h00'),
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Text(
                    'Test des notifications',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                    text: 'Envoyer une notification de test',
                    onPressed: () async {
                      try {
                        // Envoyer une notification de test
                        await _notificationService.showLocalNotification(
                          id: 9999,
                          title: 'Notification de test',
                          body:
                              'Ceci est une notification de test. Si vous voyez ceci, les notifications fonctionnent correctement.',
                          payload: '{"screen": "notifications"}',
                        );

                        if (mounted) {
                          _navigationService.showSnackBar(
                            context,
                            message: 'Notification de test envoyée',
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          _navigationService.showSnackBar(
                            context,
                            message: 'Erreur lors de l\'envoi de la notification: $e',
                          );
                        }
                      }
                    },
                    icon: Icons.send,
                  ),
                ],
              ),
    );
  }
}
