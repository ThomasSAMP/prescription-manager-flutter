import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

import '../di/injection.dart';
import '../utils/logger.dart';
import 'analytics_service.dart';
import 'error_service.dart';
import 'unified_notification_service.dart';
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

      // Initialisation en parallèle des services
      await Future.wait([
        getIt<ErrorService>().initialize(),
        getIt<UnifiedNotificationService>().initialize(),
        getIt<AnalyticsService>().initialize(),
        getIt<UpdateService>().initialize(),
      ]);

      // Configuration du gestionnaire de messages en arrière-plan
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      AppLogger.info('Firebase initialized successfully');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to initialize Firebase', e, stackTrace);
      if (!kDebugMode) {
        await FirebaseCrashlytics.instance.recordError(e, stackTrace);
      }
    }
  }
}
