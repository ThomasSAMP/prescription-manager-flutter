import 'dart:async';

import 'package:injectable/injectable.dart';

import '../../features/prescriptions/repositories/medicament_repository.dart';
import '../../features/prescriptions/repositories/ordonnance_repository.dart';
import '../../shared/providers/sync_status_provider.dart';
import '../utils/logger.dart';
import 'connectivity_service.dart';
import 'unified_cache_service.dart';
import 'unified_notification_service.dart';

// États de synchronisation unifiés
enum UnifiedSyncStatus { idle, syncing, synced, pendingOperations, error, offline, retrying }

// Informations de synchronisation détaillées
class SyncInfo {
  final UnifiedSyncStatus status;
  final int pendingOperationsCount;
  final String? errorMessage;
  final bool isRetrying;
  final int retryAttempts;
  final int maxRetryAttempts;
  final Duration? nextRetryIn;
  final DateTime? lastSyncTime;

  SyncInfo({
    required this.status,
    this.pendingOperationsCount = 0,
    this.errorMessage,
    this.isRetrying = false,
    this.retryAttempts = 0,
    this.maxRetryAttempts = 3,
    this.nextRetryIn,
    this.lastSyncTime,
  });

  SyncInfo copyWith({
    UnifiedSyncStatus? status,
    int? pendingOperationsCount,
    String? errorMessage,
    bool? clearError,
    bool? isRetrying,
    int? retryAttempts,
    int? maxRetryAttempts,
    Duration? nextRetryIn,
    DateTime? lastSyncTime,
  }) {
    return SyncInfo(
      status: status ?? this.status,
      pendingOperationsCount: pendingOperationsCount ?? this.pendingOperationsCount,
      errorMessage: clearError == true ? null : (errorMessage ?? this.errorMessage),
      isRetrying: isRetrying ?? this.isRetrying,
      retryAttempts: retryAttempts ?? this.retryAttempts,
      maxRetryAttempts: maxRetryAttempts ?? this.maxRetryAttempts,
      nextRetryIn: nextRetryIn ?? this.nextRetryIn,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
    );
  }

  bool get hasPendingOperations => pendingOperationsCount > 0;
  bool get hasError => errorMessage != null;
}

@lazySingleton
class UnifiedSyncService {
  final MedicamentRepository _medicamentRepository;
  final OrdonnanceRepository _ordonnanceRepository;
  final SyncStatusNotifier _syncStatusNotifier;
  final UnifiedNotificationService _notificationService;
  final ConnectivityService _connectivityService;
  final UnifiedCacheService _unifiedCache;

  // État de synchronisation unifié
  SyncInfo _syncInfo = SyncInfo(status: UnifiedSyncStatus.idle);
  SyncInfo get syncInfo => _syncInfo;

  // Timers pour la gestion des retry et sync périodique
  Timer? _periodicSyncTimer;
  Timer? _retryTimer;

  // Contrôleur pour les mises à jour d'état
  final StreamController<SyncInfo> _syncInfoController = StreamController<SyncInfo>.broadcast();
  Stream<SyncInfo> get syncInfoStream => _syncInfoController.stream;

  // Configuration
  static const Duration _periodicSyncInterval = Duration(minutes: 15);
  static const Duration _retryBaseDelay = Duration(minutes: 2);
  static const int _maxRetryAttempts = 3;

  UnifiedSyncService(
    this._medicamentRepository,
    this._ordonnanceRepository,
    this._syncStatusNotifier,
    this._notificationService,
    this._connectivityService,
    this._unifiedCache,
  );

  Future<void> initialize() async {
    try {
      // Mettre à jour le compteur d'opérations en attente
      _updatePendingOperationsCount();

      // Écouter les changements de connectivité
      _connectivityService.connectionStatus.listen(_handleConnectivityChange);

      // Démarrer la synchronisation périodique
      _startPeriodicSync();

      // Définir l'état initial
      final initialStatus =
          _connectivityService.currentStatus == ConnectionStatus.offline
              ? UnifiedSyncStatus.offline
              : (_syncInfo.hasPendingOperations
                  ? UnifiedSyncStatus.pendingOperations
                  : UnifiedSyncStatus.idle);

      _updateSyncInfo(_syncInfo.copyWith(status: initialStatus));

      AppLogger.debug(
        'UnifiedSyncService initialized with ${_syncInfo.pendingOperationsCount} pending operations',
      );
    } catch (e) {
      AppLogger.error('Error initializing UnifiedSyncService', e);
    }
  }

  void _handleConnectivityChange(ConnectionStatus status) {
    if (status == ConnectionStatus.online) {
      AppLogger.info('Connection restored - triggering smart sync');
      _updateSyncInfo(
        _syncInfo.copyWith(
          status:
              _syncInfo.hasPendingOperations
                  ? UnifiedSyncStatus.pendingOperations
                  : UnifiedSyncStatus.idle,
          retryAttempts: 0,
          clearError: true,
        ),
      );

      if (_syncInfo.hasPendingOperations) {
        unawaited(_processPendingOperations());
      }
    } else {
      AppLogger.info('Connection lost - going offline');
      _stopRetryTimer();
      _updateSyncInfo(_syncInfo.copyWith(status: UnifiedSyncStatus.offline, clearError: true));
    }
  }

  void _startPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(_periodicSyncInterval, (_) {
      if (_connectivityService.currentStatus == ConnectionStatus.online &&
          _syncInfo.status != UnifiedSyncStatus.syncing) {
        unawaited(syncAll());
      }
    });
  }

  void _stopRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _scheduleRetry() {
    if (_syncInfo.retryAttempts >= _maxRetryAttempts) {
      AppLogger.warning('Max retry attempts reached, stopping retries');
      _updateSyncInfo(_syncInfo.copyWith(status: UnifiedSyncStatus.error, isRetrying: false));
      return;
    }

    final retryAttempts = _syncInfo.retryAttempts + 1;
    final delay = Duration(minutes: _retryBaseDelay.inMinutes * retryAttempts);

    _updateSyncInfo(
      _syncInfo.copyWith(retryAttempts: retryAttempts, isRetrying: true, nextRetryIn: delay),
    );

    AppLogger.info('Scheduling sync retry in ${delay.inMinutes} minutes (attempt $retryAttempts)');

    _stopRetryTimer();
    _retryTimer = Timer(delay, () {
      _updateSyncInfo(_syncInfo.copyWith(isRetrying: false, nextRetryIn: null));
      unawaited(_processPendingOperations());
    });
  }

  Future<void> _processPendingOperations() async {
    if (_connectivityService.currentStatus == ConnectionStatus.offline) {
      return;
    }

    final totalPending = _getTotalPendingOperations();
    if (totalPending == 0) {
      _updateSyncInfo(
        _syncInfo.copyWith(
          status: UnifiedSyncStatus.synced,
          lastSyncTime: DateTime.now(),
          clearError: true,
        ),
      );
      return;
    }

    AppLogger.info('Processing $totalPending pending operations');
    _updateSyncInfo(_syncInfo.copyWith(status: UnifiedSyncStatus.syncing, clearError: true));

    try {
      // Traiter les opérations en attente des ordonnances
      await _ordonnanceRepository.processPendingOperations();

      // Traiter les opérations en attente des médicaments
      await _medicamentRepository.processPendingOperations();

      // Mettre à jour le compteur
      _updatePendingOperationsCount();

      if (_syncInfo.pendingOperationsCount == 0) {
        _updateSyncInfo(
          _syncInfo.copyWith(
            status: UnifiedSyncStatus.synced,
            lastSyncTime: DateTime.now(),
            retryAttempts: 0,
            clearError: true,
          ),
        );
        _stopRetryTimer();
        AppLogger.info('All pending operations processed successfully');
      } else {
        _updateSyncInfo(_syncInfo.copyWith(status: UnifiedSyncStatus.pendingOperations));
      }
    } catch (e) {
      AppLogger.error('Error processing pending operations', e);
      _updateSyncInfo(
        _syncInfo.copyWith(
          status: UnifiedSyncStatus.error,
          errorMessage: 'Échec de la synchronisation: ${e.toString()}',
        ),
      );
      _scheduleRetry();
    }
  }

  /// Synchronise toutes les données avec le serveur
  Future<void> syncAll() async {
    try {
      if (_connectivityService.currentStatus == ConnectionStatus.offline) {
        _updateSyncInfo(
          _syncInfo.copyWith(
            status: UnifiedSyncStatus.offline,
            errorMessage: 'Impossible de synchroniser en mode hors ligne',
          ),
        );
        return;
      }

      _updateSyncInfo(_syncInfo.copyWith(status: UnifiedSyncStatus.syncing, clearError: true));

      // Synchroniser les ordonnances d'abord
      await _ordonnanceRepository.syncWithServer();

      // Puis synchroniser les médicaments
      await _medicamentRepository.syncWithServer();

      // Invalider les caches pour forcer le rechargement avec le service unifié
      await _invalidateAllCaches();

      _updateSyncInfo(
        _syncInfo.copyWith(
          status: UnifiedSyncStatus.synced,
          lastSyncTime: DateTime.now(),
          retryAttempts: 0,
          clearError: true,
        ),
      );

      AppLogger.info('All data synchronized successfully');
    } catch (e) {
      AppLogger.error('Error synchronizing data', e);

      final errorMessage = 'Erreur de synchronisation: ${e.toString()}';
      _updateSyncInfo(
        _syncInfo.copyWith(status: UnifiedSyncStatus.error, errorMessage: errorMessage),
      );

      // Programmer un retry automatique
      _scheduleRetry();

      rethrow;
    }
  }

  Future<void> _invalidateAllCaches() async {
    try {
      await _unifiedCache.invalidatePattern('ordonnances*');
      await _unifiedCache.invalidatePattern('medicaments*');
      AppLogger.debug('All caches invalidated during sync');
    } catch (e) {
      AppLogger.error('Error invalidating caches during sync', e);
    }
  }

  /// Force une synchronisation immédiate
  Future<void> forceSyncNow() async {
    _updateSyncInfo(_syncInfo.copyWith(retryAttempts: 0, clearError: true));
    await syncAll();
  }

  /// Synchronise une entité spécifique
  Future<void> syncEntity(String entityType) async {
    try {
      if (_connectivityService.currentStatus == ConnectionStatus.offline) {
        throw Exception('Impossible de synchroniser en mode hors ligne');
      }

      _updateSyncInfo(_syncInfo.copyWith(status: UnifiedSyncStatus.syncing, clearError: true));

      switch (entityType) {
        case 'ordonnances':
          await _ordonnanceRepository.syncWithServer();
          await _unifiedCache.invalidatePattern('ordonnances*');
          break;
        case 'medicaments':
          await _medicamentRepository.syncWithServer();
          await _unifiedCache.invalidatePattern('medicaments*');
          break;
        default:
          throw Exception('Type d\'entité non supporté: $entityType');
      }

      _updateSyncInfo(
        _syncInfo.copyWith(
          status: UnifiedSyncStatus.synced,
          lastSyncTime: DateTime.now(),
          clearError: true,
        ),
      );

      AppLogger.info('$entityType synchronized successfully');
    } catch (e) {
      AppLogger.error('Error synchronizing $entityType', e);
      _updateSyncInfo(
        _syncInfo.copyWith(
          status: UnifiedSyncStatus.error,
          errorMessage: 'Erreur de synchronisation: ${e.toString()}',
        ),
      );
      rethrow;
    }
  }

  // Méthode pour obtenir les statistiques de cache
  Future<Map<String, dynamic>> getCacheStats() async {
    try {
      return await _unifiedCache.getStats();
    } catch (e) {
      AppLogger.error('Error getting cache stats', e);
      return {};
    }
  }

  // Méthode pour nettoyer les caches
  Future<void> cleanupCaches() async {
    try {
      await _unifiedCache.cleanup();
      AppLogger.info('Cache cleanup completed');
    } catch (e) {
      AppLogger.error('Error during cache cleanup', e);
    }
  }

  int _getTotalPendingOperations() {
    return _ordonnanceRepository.pendingOperations.length +
        _medicamentRepository.pendingOperations.length;
  }

  void _updatePendingOperationsCount() {
    final count = _getTotalPendingOperations();
    _updateSyncInfo(_syncInfo.copyWith(pendingOperationsCount: count));
  }

  void _updateSyncInfo(SyncInfo newSyncInfo) {
    _syncInfo = newSyncInfo;

    // Mettre à jour le notifier legacy pour compatibilité
    _updateLegacySyncStatus();

    // Émettre le nouvel état
    _syncInfoController.add(_syncInfo);

    // Afficher les notifications appropriées
    _handleSyncNotifications();
  }

  void _updateLegacySyncStatus() {
    switch (_syncInfo.status) {
      case UnifiedSyncStatus.syncing:
        _syncStatusNotifier.setSyncing();
        break;
      case UnifiedSyncStatus.synced:
        _syncStatusNotifier.setSynced();
        break;
      case UnifiedSyncStatus.error:
        _syncStatusNotifier.setError(_syncInfo.errorMessage ?? 'Erreur inconnue');
        break;
      case UnifiedSyncStatus.offline:
        _syncStatusNotifier.setOffline();
        break;
      case UnifiedSyncStatus.pendingOperations:
        _syncStatusNotifier.setPendingOperationsCount(_syncInfo.pendingOperationsCount);
        break;
      default:
        break;
    }
  }

  void _handleSyncNotifications() {
    switch (_syncInfo.status) {
      case UnifiedSyncStatus.syncing:
        unawaited(_notificationService.showSyncNotification('Synchronisation en cours...'));
        break;
      case UnifiedSyncStatus.synced:
        unawaited(_notificationService.showSyncNotification('Synchronisation réussie'));
        break;
      case UnifiedSyncStatus.error:
        unawaited(
          _notificationService.showSyncNotification(
            _syncInfo.errorMessage ?? 'Erreur de synchronisation',
            isError: true,
          ),
        );
        break;
      case UnifiedSyncStatus.offline:
        unawaited(_notificationService.showSyncNotification('Mode hors ligne'));
        break;
      default:
        break;
    }
  }

  void dispose() {
    _periodicSyncTimer?.cancel();
    _stopRetryTimer();
    _syncInfoController.close();
  }
}
