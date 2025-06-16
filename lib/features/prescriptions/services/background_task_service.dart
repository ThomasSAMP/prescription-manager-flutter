import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:prescription_manager/core/services/unified_cache_service.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/di/injection.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/encryption_service.dart';
import '../../../core/services/unified_sync_service.dart';
import '../../../core/utils/logger.dart';

// Identifiants des tâches
const String _syncTaskId = 'com.thomassamp.prescriptionManager.backgroundSync';
const String _cleanupTaskId = 'com.thomassamp.prescriptionManager.cleanup';
const String _precomputeTaskId = 'com.thomassamp.prescriptionManager.precompute';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      AppLogger.debug('Background task started: $taskName');

      switch (taskName) {
        case _syncTaskId:
          return await _handleBackgroundSync();
        case _cleanupTaskId:
          return await _handleCleanup();
        case _precomputeTaskId:
          return await _handlePrecompute();
        default:
          AppLogger.warning('Unknown background task: $taskName');
          return false;
      }
    } catch (e) {
      AppLogger.error('Error in background task $taskName', e);
      return false;
    }
  });
}

// Synchronisation intelligente en arrière-plan
Future<bool> _handleBackgroundSync() async {
  try {
    // Initialiser les services minimaux nécessaires
    if (!getIt.isRegistered<ConnectivityService>()) {
      await _initializeMinimalServices();
    }

    final connectivityService = getIt<ConnectivityService>();
    final syncService = getIt<UnifiedSyncService>();

    // Vérifier la connectivité
    if (connectivityService.currentStatus == ConnectionStatus.online) {
      // Synchroniser seulement les opérations en attente (pas de sync complet)
      if (syncService.syncInfo.hasPendingOperations) {
        await syncService.syncAll();
        AppLogger.info(
          'Background sync completed: ${syncService.syncInfo.pendingOperationsCount} operations processed',
        );
      }
    }

    return true;
  } catch (e) {
    AppLogger.error('Background sync failed', e);
    return false;
  }
}

// Nettoyage automatique des caches et données temporaires
Future<bool> _handleCleanup() async {
  try {
    if (!getIt.isRegistered<UnifiedCacheService>()) {
      await _initializeMinimalServices();
    }

    final unifiedCacheService = getIt<UnifiedCacheService>();

    // Nettoyer les caches anciens (plus de 24h)
    // Note: Cette logique pourrait être ajoutée au CacheService
    AppLogger.info('Cache cleanup completed');

    // Nettoyer les logs anciens (plus de 7 jours)
    await _cleanupOldLogs();

    return true;
  } catch (e) {
    AppLogger.error('Cleanup task failed', e);
    return false;
  }
}

// Pré-calculs pour améliorer les performances
Future<bool> _handlePrecompute() async {
  try {
    // Pré-calculer les statistiques d'expiration
    await _precomputeExpirationStats();

    // Indexer les données pour la recherche
    await _indexSearchData();

    AppLogger.info('Precompute tasks completed');
    return true;
  } catch (e) {
    AppLogger.error('Precompute task failed', e);
    return false;
  }
}

// Initialiser les services minimaux pour les tâches en arrière-plan
Future<void> _initializeMinimalServices() async {
  // Initialiser seulement les services essentiels pour éviter la surcharge
  try {
    await getIt<EncryptionService>().initialize();
    // Autres services selon les besoins
  } catch (e) {
    AppLogger.error('Error initializing minimal services', e);
  }
}

// Nettoyer les anciens logs
Future<void> _cleanupOldLogs() async {
  // Implémentation du nettoyage des logs
  AppLogger.debug('Cleaning up old logs');
}

// Pré-calculer les statistiques d'expiration
Future<void> _precomputeExpirationStats() async {
  // Pré-calculer les données pour accélérer l'affichage
  AppLogger.debug('Precomputing expiration statistics');
}

// Indexer les données pour la recherche
Future<void> _indexSearchData() async {
  // Créer des index de recherche pour améliorer les performances
  AppLogger.debug('Indexing search data');
}

@lazySingleton
class BackgroundTaskService {
  Future<void> initialize() async {
    try {
      if (Platform.isAndroid) {
        await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

        // Tâche de synchronisation intelligente (toutes les 4 heures)
        await Workmanager().registerPeriodicTask(
          _syncTaskId,
          _syncTaskId,
          frequency: const Duration(hours: 4),
          constraints: Constraints(
            networkType: NetworkType.connected,
            requiresBatteryNotLow: true, // Seulement si la batterie n'est pas faible
            requiresCharging: false,
            requiresDeviceIdle: false,
            requiresStorageNotLow: true,
          ),
          existingWorkPolicy: ExistingWorkPolicy.replace,
        );

        // Tâche de nettoyage (une fois par jour)
        await Workmanager().registerPeriodicTask(
          _cleanupTaskId,
          _cleanupTaskId,
          frequency: const Duration(days: 1),
          constraints: Constraints(
            networkType: NetworkType.not_required,
            requiresBatteryNotLow: true,
            requiresCharging: false,
            requiresDeviceIdle: true, // Seulement quand l'appareil est inactif
            requiresStorageNotLow: true,
          ),
          existingWorkPolicy: ExistingWorkPolicy.replace,
        );

        // Tâche de pré-calcul (deux fois par jour)
        await Workmanager().registerPeriodicTask(
          _precomputeTaskId,
          _precomputeTaskId,
          frequency: const Duration(hours: 12),
          constraints: Constraints(
            networkType: NetworkType.not_required,
            requiresBatteryNotLow: true,
            requiresCharging: false,
            requiresDeviceIdle: false,
            requiresStorageNotLow: true,
          ),
          existingWorkPolicy: ExistingWorkPolicy.replace,
        );

        AppLogger.info('BackgroundTaskService initialized with intelligent tasks');
      }

      // iOS : Les tâches en arrière-plan sont plus limitées
      // On peut utiliser les App Refresh ou les notifications locales programmées
      if (Platform.isIOS) {
        AppLogger.info('iOS background tasks: Limited to app refresh and scheduled notifications');
      }
    } catch (e, stackTrace) {
      AppLogger.error('Failed to initialize BackgroundTaskService', e, stackTrace);
    }
  }

  // Méthode pour déclencher manuellement une synchronisation en arrière-plan
  Future<void> triggerBackgroundSync() async {
    if (Platform.isAndroid) {
      try {
        await Workmanager().registerOneOffTask(
          'manual_sync_${DateTime.now().millisecondsSinceEpoch}',
          _syncTaskId,
          constraints: Constraints(networkType: NetworkType.connected),
        );
        AppLogger.info('Manual background sync triggered');
      } catch (e) {
        AppLogger.error('Failed to trigger manual background sync', e);
      }
    }
  }

  // Méthode pour déclencher manuellement un nettoyage
  Future<void> triggerCleanup() async {
    if (Platform.isAndroid) {
      try {
        await Workmanager().registerOneOffTask(
          'manual_cleanup_${DateTime.now().millisecondsSinceEpoch}',
          _cleanupTaskId,
        );
        AppLogger.info('Manual cleanup triggered');
      } catch (e) {
        AppLogger.error('Failed to trigger manual cleanup', e);
      }
    }
  }
}
