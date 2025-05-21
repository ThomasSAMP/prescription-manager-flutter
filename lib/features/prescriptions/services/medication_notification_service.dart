import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:injectable/injectable.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/di/injection.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/utils/logger.dart';
import '../models/medicament_model.dart';
import '../repositories/medicament_repository.dart';
import 'background_task_service.dart';

@lazySingleton
class MedicationNotificationService {
  final NotificationService _notificationService;
  final MedicamentRepository _medicamentRepository;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  MedicationNotificationService(this._notificationService, this._medicamentRepository);

  // Initialiser le service
  Future<void> initialize() async {
    try {
      // S'assurer que le service de notification principal est initialisé
      await _notificationService.initialize();

      // Initialiser le timezone
      tz_data.initializeTimeZones();
      final local = tz.getLocation('Europe/Paris');

      // Configurer le canal de notification pour les médicaments
      const androidChannel = AndroidNotificationChannel(
        'medication_channel',
        'Medication Alerts',
        description: 'Notifications for medications nearing expiration',
        importance: Importance.high,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidChannel);

      AppLogger.info('MedicationNotificationService initialized successfully');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to initialize MedicationNotificationService', e, stackTrace);
    }
  }

  // Vérifier les médicaments qui arrivent à expiration et envoyer des notifications
  Future<void> checkExpiringMedications() async {
    try {
      final expiringMedications = await _medicamentRepository.getMedicamentsNearingExpiration();

      for (final medication in expiringMedications) {
        await _sendExpirationNotification(medication);
      }

      AppLogger.debug('Checked ${expiringMedications.length} expiring medications');
    } catch (e, stackTrace) {
      AppLogger.error('Error checking expiring medications', e, stackTrace);
    }
  }

  // Envoyer une notification pour un médicament qui arrive à expiration
  Future<void> _sendExpirationNotification(MedicamentModel medication) async {
    try {
      final status = medication.getExpirationStatus();
      String title;
      String body;

      switch (status) {
        case ExpirationStatus.expired:
          title = 'Médicament expiré !';
          body = 'Le médicament ${medication.name} est expiré. Veuillez renouveler l\'ordonnance.';
          break;
        case ExpirationStatus.critical:
          title = 'Médicament bientôt expiré !';
          body = 'Le médicament ${medication.name} expire dans moins de 14 jours.';
          break;
        case ExpirationStatus.warning:
          title = 'Attention à l\'expiration';
          body = 'Le médicament ${medication.name} expire dans moins de 30 jours.';
          break;
        default:
          return; // Ne pas envoyer de notification pour les médicaments non expirés
      }

      // Envoyer une notification locale
      await _localNotifications.show(
        medication.id.hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'medication_channel',
            'Medication Alerts',
            channelDescription: 'Notifications for medications nearing expiration',
            importance: Importance.high,
            priority: Priority.high,
            color: status.getColor(),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: '{"screen": "medication_detail", "id": "${medication.id}"}',
      );

      AppLogger.debug('Sent notification for expiring medication: ${medication.id}');
    } catch (e, stackTrace) {
      AppLogger.error('Error sending medication expiration notification', e, stackTrace);
    }
  }

  // Planifier une vérification quotidienne des médicaments qui arrivent à expiration
  Future<void> scheduleExpirationChecks() async {
    try {
      // Initialiser le service de tâches en arrière-plan
      await getIt<BackgroundTaskService>().initialize();

      // Vérifier immédiatement les médicaments qui arrivent à expiration
      await checkExpiringMedications();

      AppLogger.info('Scheduled medication expiration checks');
    } catch (e, stackTrace) {
      AppLogger.error('Error scheduling medication expiration checks', e, stackTrace);
    }
  }

  // Programmer des vérifications périodiques pour iOS
  Future<void> schedulePeriodicChecks() async {
    if (!Platform.isIOS) return;

    try {
      // Initialiser timezone
      tz_data.initializeTimeZones();
      final local = tz.getLocation('Europe/Paris'); // Ajustez selon votre fuseau horaire

      // Programmer une notification quotidienne qui déclenchera une vérification
      final now = DateTime.now();
      final scheduledTime = tz.TZDateTime(
        local,
        now.year,
        now.month,
        now.day,
        8,
        0,
        0, // 8h00 du matin
      ).add(const Duration(days: 1)); // À partir de demain

      // Configurer la notification quotidienne
      await _localNotifications.zonedSchedule(
        0, // ID unique
        'Vérification des médicaments',
        'Vérification quotidienne des médicaments qui arrivent à expiration',
        scheduledTime,
        const NotificationDetails(
          iOS: DarwinNotificationDetails(
            presentAlert: false, // Ne pas afficher d'alerte
            presentBadge: false, // Ne pas mettre à jour le badge
            presentSound: false, // Ne pas jouer de son
          ),
          android: AndroidNotificationDetails(
            'medication_check_channel',
            'Medication Checks',
            channelDescription: 'Daily checks for medication expiration',
            importance: Importance.low,
            priority: Priority.low,
            showWhen: false,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time, // Répéter chaque jour à la même heure
        payload: 'check_medications',
      );

      AppLogger.info('Scheduled daily medication checks for iOS');
    } catch (e, stackTrace) {
      AppLogger.error('Error scheduling periodic checks for iOS', e, stackTrace);
    }
  }
}
