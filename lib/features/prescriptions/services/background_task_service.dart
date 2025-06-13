import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/utils/logger.dart';

@lazySingleton
class BackgroundTaskService {
  // Ce service est maintenant simplifié car les Cloud Functions Firebase gèrent déjà les vérifications quotidiennes et l'envoi des notifications push

  Future<void> initialize() async {
    try {
      if (Platform.isAndroid) {
        // Initialiser Workmanager pour Android uniquement pour des tâches locales comme la synchronisation des données en arrière-plan si nécessaire
        await Workmanager().initialize(_callbackDispatcher, isInDebugMode: false);

        AppLogger.info('BackgroundTaskService initialized for Android');
      }

      // iOS et Android reçoivent tous les deux les notifications push depuis les Cloud Functions Firebase - pas besoin de logique spécifique
      AppLogger.info('Background notifications handled by Firebase Cloud Functions');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to initialize BackgroundTaskService', e, stackTrace);
    }
  }
}

@pragma('vm:entry-point')
void _callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      // Ici on pourrait ajouter des tâches locales si nécessaire comme la synchronisation des données en arrière-plan
      AppLogger.debug('Background task executed: $taskName');
      return true;
    } catch (e) {
      AppLogger.error('Error in background task', e);
      return false;
    }
  });
}
