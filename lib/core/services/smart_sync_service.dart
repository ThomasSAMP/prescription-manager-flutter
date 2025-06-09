import 'dart:async';

import 'package:injectable/injectable.dart';

import '../utils/logger.dart';
import 'connectivity_service.dart';
import 'sync_service.dart';

@lazySingleton
class SmartSyncService {
  final SyncService _syncService;
  final ConnectivityService _connectivityService;

  Timer? _periodicSyncTimer;
  Timer? _retryTimer;
  int _retryAttempts = 0;
  static const int _maxRetryAttempts = 3;
  static const Duration _retryDelay = Duration(minutes: 2);
  static const Duration _periodicSyncInterval = Duration(minutes: 15);

  SmartSyncService(this._syncService, this._connectivityService) {
    _initializeSmartSync();
  }

  void _initializeSmartSync() {
    // Écouter les changements de connectivité
    _connectivityService.connectionStatus.listen(_handleConnectivityChange);

    // Démarrer la synchronisation périodique
    _startPeriodicSync();
  }

  void _handleConnectivityChange(ConnectionStatus status) {
    if (status == ConnectionStatus.online) {
      AppLogger.info('Connection restored - triggering smart sync');
      _retryAttempts = 0;
      _attemptSync();
    } else {
      AppLogger.info('Connection lost - stopping periodic sync');
      _stopRetryTimer();
    }
  }

  void _startPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(_periodicSyncInterval, (_) {
      if (_connectivityService.currentStatus == ConnectionStatus.online) {
        _attemptSync();
      }
    });
  }

  Future<void> _attemptSync() async {
    if (_connectivityService.currentStatus == ConnectionStatus.offline) {
      return;
    }

    try {
      await _syncService.syncAll();
      _retryAttempts = 0;
      _stopRetryTimer();
      AppLogger.info('Smart sync completed successfully');
    } catch (e) {
      AppLogger.error('Smart sync failed', e);
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (_retryAttempts >= _maxRetryAttempts) {
      AppLogger.warning('Max retry attempts reached, stopping retries');
      return;
    }

    _retryAttempts++;
    _stopRetryTimer();

    final delay = Duration(minutes: _retryDelay.inMinutes * _retryAttempts);
    AppLogger.info('Scheduling sync retry in ${delay.inMinutes} minutes (attempt $_retryAttempts)');

    _retryTimer = Timer(delay, _attemptSync);
  }

  void _stopRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// Force une synchronisation immédiate
  Future<void> forceSyncNow() async {
    _retryAttempts = 0;
    await _attemptSync();
  }

  /// Obtenir le statut de synchronisation
  SyncInfo getSyncInfo() {
    return SyncInfo(
      isRetrying: _retryTimer != null,
      retryAttempts: _retryAttempts,
      maxRetryAttempts: _maxRetryAttempts,
      nextRetryIn:
          _retryTimer != null ? Duration(minutes: _retryDelay.inMinutes * _retryAttempts) : null,
      hasPendingOperations: _syncService.hasPendingOperations(),
      pendingOperationsCount: _syncService.getPendingOperationsCount(),
    );
  }

  void dispose() {
    _periodicSyncTimer?.cancel();
    _stopRetryTimer();
  }
}

class SyncInfo {
  final bool isRetrying;
  final int retryAttempts;
  final int maxRetryAttempts;
  final Duration? nextRetryIn;
  final bool hasPendingOperations;
  final int pendingOperationsCount;

  SyncInfo({
    required this.isRetrying,
    required this.retryAttempts,
    required this.maxRetryAttempts,
    this.nextRetryIn,
    required this.hasPendingOperations,
    required this.pendingOperationsCount,
  });
}
