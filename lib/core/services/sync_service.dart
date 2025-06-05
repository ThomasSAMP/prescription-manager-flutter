import 'package:injectable/injectable.dart';

import '../../features/prescriptions/repositories/medicament_repository.dart';
import '../../features/prescriptions/repositories/ordonnance_repository.dart';
import '../../shared/providers/sync_status_provider.dart';
import '../../shared/widgets/sync_status_indicator.dart';
import '../utils/logger.dart';
import 'cache_service.dart';
import 'connectivity_service.dart';
import 'sync_notification_service.dart';

@lazySingleton
class SyncService {
  final MedicamentRepository _medicamentRepository;
  final OrdonnanceRepository _ordonnanceRepository;
  final SyncStatusNotifier _syncStatusNotifier;
  final SyncNotificationService _syncNotificationService;
  final ConnectivityService _connectivityService;
  final CacheService _cacheService;

  SyncService(
    this._medicamentRepository,
    this._ordonnanceRepository,
    this._syncStatusNotifier,
    this._syncNotificationService,
    this._connectivityService,
    this._cacheService,
  );

  Future<void> initialize() async {
    try {
      // Mettre à jour le compteur d'opérations en attente
      updatePendingOperationsCount();

      // Si nous sommes en ligne et qu'il y a des opérations en attente,
      // mettre à jour l'état en conséquence
      if (_syncStatusNotifier.state.status != SyncStatus.offline &&
          getPendingOperationsCount() > 0) {
        _syncStatusNotifier.setPendingOperationsCount(getPendingOperationsCount());
        _syncNotificationService.showPendingSync(getPendingOperationsCount());
      }

      AppLogger.debug(
        'SyncService initialized with ${getPendingOperationsCount()} pending operations',
      );
    } catch (e) {
      AppLogger.error('Error initializing SyncService', e);
    }
  }

  /// Synchronise toutes les données avec le serveur
  Future<void> syncAll() async {
    try {
      // Vérifier d'abord si nous sommes en ligne
      if (_connectivityService.currentStatus == ConnectionStatus.offline) {
        _syncStatusNotifier.setOffline();
        _syncNotificationService.showOffline();
        throw Exception('Impossible de synchroniser en mode hors ligne');
      }

      _syncStatusNotifier.setSyncing();
      _syncNotificationService.showSyncing();

      // Synchroniser les ordonnances d'abord
      await _ordonnanceRepository.syncWithServer();

      // Puis synchroniser les médicaments
      await _medicamentRepository.syncWithServer();

      // Invalider les caches pour forcer le rechargement
      _cacheService.invalidateAllCache();

      _syncStatusNotifier.setSynced();
      _syncNotificationService.showSynced();

      AppLogger.info('All data synchronized successfully');
    } catch (e) {
      AppLogger.error('Error synchronizing data', e);

      if (e.toString().contains('hors ligne')) {
        // Déjà géré ci-dessus
      } else {
        _syncStatusNotifier.setError('Erreur de synchronisation: ${e.toString()}');
        _syncNotificationService.showError(e.toString());
      }

      rethrow;
    }
  }

  /// Synchronise une entité spécifique
  Future<void> syncEntity(String entityType) async {
    try {
      if (_connectivityService.currentStatus == ConnectionStatus.offline) {
        throw Exception('Impossible de synchroniser en mode hors ligne');
      }

      _syncStatusNotifier.setSyncing();

      switch (entityType) {
        case 'ordonnances':
          await _ordonnanceRepository.syncWithServer();
          _cacheService.invalidateCache('ordonnances');
          break;
        case 'medicaments':
          await _medicamentRepository.syncWithServer();
          _cacheService.invalidateCache('medicaments');
          break;
        default:
          throw Exception('Type d\'entité non supporté: $entityType');
      }

      _syncStatusNotifier.setSynced();
      AppLogger.info('$entityType synchronized successfully');
    } catch (e) {
      AppLogger.error('Error synchronizing $entityType', e);
      _syncStatusNotifier.setError('Erreur de synchronisation: ${e.toString()}');
      rethrow;
    }
  }

  /// Vérifie s'il y a des opérations en attente
  bool hasPendingOperations() {
    return _ordonnanceRepository.pendingOperations.isNotEmpty ||
        _medicamentRepository.pendingOperations.isNotEmpty;
  }

  /// Obtient le nombre total d'opérations en attente
  int getPendingOperationsCount() {
    return _ordonnanceRepository.pendingOperations.length +
        _medicamentRepository.pendingOperations.length;
  }

  /// Met à jour le compteur d'opérations en attente
  void updatePendingOperationsCount() {
    final count = getPendingOperationsCount();
    _syncStatusNotifier.setPendingOperationsCount(count);

    if (count > 0) {
      _syncNotificationService.showPendingSync(count);
    }
  }

  /// Force la synchronisation même en cas d'erreurs précédentes
  Future<void> forceSyncAll() async {
    try {
      // Réinitialiser l'état d'erreur
      _syncStatusNotifier.setSyncing();

      // Invalider tous les caches pour forcer le rechargement
      _cacheService.invalidateAllCache();

      // Synchroniser
      await syncAll();
    } catch (e) {
      AppLogger.error('Error in force sync', e);
      rethrow;
    }
  }
}
