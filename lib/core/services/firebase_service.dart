import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

import '../di/injection.dart';
import '../utils/logger.dart';
import 'analytics_service.dart';
import 'error_service.dart';
import 'notification_service.dart';
import 'update_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialiser Firebase si nécessaire (pour les messages en arrière-plan)
  await Firebase.initializeApp();

  AppLogger.info('Background message received: ${message.notification?.title}');
  AppLogger.debug('Message data: ${message.data}');

  // Les données du message sont automatiquement gérées par le système
  // La navigation sera traitée quand l'utilisateur tapera sur la notification
}

@lazySingleton
class FirebaseService {
  Future<void> initialize() async {
    try {
      await Firebase.initializeApp();

      // Configurer les émulateurs en mode debug
      // if (kDebugMode && EnvConfig.isDevelopment) {
      //   DefaultFirebaseOptions.configureEmulators();
      // }

      // Initialiser le service d'erreur en premier
      await getIt<ErrorService>().initialize();

      // Configurer le gestionnaire de messages en arrière-plan
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Initialiser le service de notification
      await getIt<NotificationService>().initialize();

      // Initialiser le service d'analytics
      await getIt<AnalyticsService>().initialize();

      // Initialiser le service de mise à jour
      await getIt<UpdateService>().initialize();

      // Initialiser le service de connectivité
      // await getIt<ConnectivityService>().initialize();
      // ==> Pas besoin d'initialiser le service de connectivité explicitement car le constructeur s'en charge

      AppLogger.info('Firebase initialized successfully');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to initialize Firebase', e, stackTrace);
      if (!kDebugMode) {
        // Utiliser directement FirebaseCrashlytics ici car ErrorService pourrait ne pas être initialisé
        await FirebaseCrashlytics.instance.recordError(e, stackTrace);
      }
    }
  }
}
