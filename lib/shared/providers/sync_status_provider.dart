import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/injection.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/sync_notification_service.dart';
import '../widgets/sync_status_indicator.dart';

class SyncStatusState {
  final SyncStatus status;
  final String? errorMessage;
  final int pendingOperationsCount;

  SyncStatusState({required this.status, this.errorMessage, this.pendingOperationsCount = 0});

  SyncStatusState copyWith({
    SyncStatus? status,
    String? errorMessage,
    bool clearError = false,
    int? pendingOperationsCount,
  }) {
    return SyncStatusState(
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      pendingOperationsCount: pendingOperationsCount ?? this.pendingOperationsCount,
    );
  }
}

class SyncStatusNotifier extends StateNotifier<SyncStatusState> {
  final ConnectivityService _connectivityService;
  final SyncNotificationService _syncNotificationService;

  SyncStatusNotifier(this._connectivityService, this._syncNotificationService)
    : super(
        SyncStatusState(
          status:
              _connectivityService.currentStatus == ConnectionStatus.online
                  ? SyncStatus.synced
                  : SyncStatus.offline,
        ),
      ) {
    // Écouter les changements de connectivité
    _connectivityService.connectionStatus.listen(_handleConnectivityChange);
  }

  void _handleConnectivityChange(ConnectionStatus status) {
    if (status == ConnectionStatus.offline) {
      state = state.copyWith(status: SyncStatus.offline);
      _syncNotificationService.showOffline();
    } else if (state.status == SyncStatus.offline) {
      // Si nous étions hors ligne et sommes maintenant en ligne
      if (state.pendingOperationsCount > 0) {
        state = state.copyWith(status: SyncStatus.pendingSync);
        _syncNotificationService.showPendingSync(state.pendingOperationsCount);
      } else {
        state = state.copyWith(status: SyncStatus.synced);
        // Pas besoin de notification ici
      }
    }
  }

  void setSyncing() {
    state = state.copyWith(status: SyncStatus.syncing, clearError: true);
    _syncNotificationService.showSyncing();
  }

  void setSynced() {
    state = state.copyWith(status: SyncStatus.synced, clearError: true, pendingOperationsCount: 0);
    _syncNotificationService.showSynced();
  }

  void setError(String message) {
    state = state.copyWith(status: SyncStatus.error, errorMessage: message);
    _syncNotificationService.showError(message);
  }

  void setPendingOperationsCount(int count) {
    state = state.copyWith(
      pendingOperationsCount: count,
      status: count > 0 ? SyncStatus.pendingSync : state.status,
    );

    if (count > 0) {
      _syncNotificationService.showPendingSync(count);
    }
  }

  void setOffline() {
    state = state.copyWith(status: SyncStatus.offline);
    _syncNotificationService.showOffline();
  }
}

final syncStatusProvider = StateNotifierProvider<SyncStatusNotifier, SyncStatusState>((ref) {
  return SyncStatusNotifier(getIt<ConnectivityService>(), getIt<SyncNotificationService>());
});
