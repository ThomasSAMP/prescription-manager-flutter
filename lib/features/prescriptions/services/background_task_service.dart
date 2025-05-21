import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/di/injection.dart';
import '../../../core/services/encryption_service.dart';
import '../../../core/utils/logger.dart';
import 'medication_notification_service.dart';

// Identifiant de la tâche périodique
const _taskIdentifier = 'com.thomassamp.prescriptionManager.checkMedicationExpiration';

// Fonction de rappel pour Workmanager (Android)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      // Initialiser Firebase
      WidgetsFlutterBinding.ensureInitialized();
      await Firebase.initializeApp();

      // Initialiser les services nécessaires
      await _initializeServices();

      // Vérifier les médicaments qui arrivent à expiration
      if (taskName == _taskIdentifier) {
        await getIt<MedicationNotificationService>().checkExpiringMedications();
      }

      return true;
    } catch (e) {
      AppLogger.error('Error in background task', e);
      return false;
    }
  });
}

// Initialiser les services nécessaires
Future<void> _initializeServices() async {
  // Initialiser l'injection de dépendances si ce n'est pas déjà fait
  if (!getIt.isRegistered<EncryptionService>()) {
    await configureDependencies();
  }

  // Initialiser le service de chiffrement
  await getIt<EncryptionService>().initialize();

  // Initialiser le service de notification
  await getIt<MedicationNotificationService>().initialize();
}

@lazySingleton
class BackgroundTaskService {
  // Initialiser le service
  Future<void> initialize() async {
    try {
      if (Platform.isAndroid) {
        // Initialiser Workmanager pour Android
        await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

        // Enregistrer une tâche périodique
        await Workmanager().registerPeriodicTask(
          _taskIdentifier,
          _taskIdentifier,
          frequency: const Duration(hours: 12), // Vérifier deux fois par jour
          constraints: Constraints(
            networkType: NetworkType.connected, // Exécuter uniquement lorsque connecté
            requiresBatteryNotLow: false,
            requiresCharging: false,
            requiresDeviceIdle: false,
            requiresStorageNotLow: false,
          ),
          existingWorkPolicy: ExistingWorkPolicy.replace,
          backoffPolicy: BackoffPolicy.linear,
          backoffPolicyDelay: const Duration(minutes: 30),
        );

        AppLogger.info('Workmanager initialized successfully');
      } else if (Platform.isIOS) {
        // Pour iOS, nous utiliserons les notifications programmées localement
        // au lieu de background fetch
        AppLogger.info('Using scheduled notifications for iOS');

        // Vérifier immédiatement les médicaments qui arrivent à expiration
        await getIt<MedicationNotificationService>().checkExpiringMedications();

        // Programmer des vérifications quotidiennes via des notifications locales
        await getIt<MedicationNotificationService>().schedulePeriodicChecks();
      }
    } catch (e, stackTrace) {
      AppLogger.error('Failed to initialize BackgroundTaskService', e, stackTrace);
    }
  }
}
