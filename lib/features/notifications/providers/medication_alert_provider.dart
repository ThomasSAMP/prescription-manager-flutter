import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/injection.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/utils/logger.dart';
import '../../../shared/providers/auth_provider.dart';
import '../models/medication_alert_model.dart';
import '../repositories/medication_alert_repository.dart';

final medicationAlertRepositoryProvider = Provider<MedicationAlertRepository>((ref) {
  return getIt<MedicationAlertRepository>();
});

// Provider principal pour les alertes
final medicationAlertsProvider =
    StateNotifierProvider<MedicationAlertNotifier, MedicationAlertState>((ref) {
      return MedicationAlertNotifier(
        repository: getIt<MedicationAlertRepository>(),
        connectivityService: getIt<ConnectivityService>(),
      );
    });

// Provider pour les alertes filtrées par utilisateur
final userMedicationAlertsProvider = Provider<List<MedicationAlertModel>>((ref) {
  final authState = ref.watch(authStateProvider);
  final alertsState = ref.watch(medicationAlertsProvider);

  // Utiliser keepAlive pour éviter les recalculs
  ref.keepAlive();

  return authState.when(
    data: (user) {
      if (user == null) return [];

      final repository = ref.read(medicationAlertRepositoryProvider);
      return repository.getAlertsForUser(alertsState.items, user.uid);
    },
    loading: () => [],
    error: (_, __) => [],
  );
});

// Provider pour les alertes groupées par date
final groupedMedicationAlertsProvider = Provider<Map<String, List<MedicationAlertModel>>>((ref) {
  final userAlerts = ref.watch(userMedicationAlertsProvider);

  // Cache automatique avec keepAlive
  ref.keepAlive();

  if (userAlerts.isEmpty) {
    return <String, List<MedicationAlertModel>>{};
  }

  final repository = ref.read(medicationAlertRepositoryProvider);
  return repository.groupAlertsByDate(userAlerts);
});

// Provider pour le nombre d'alertes non lues
final unreadAlertsCountProvider = Provider<int>((ref) {
  final authState = ref.watch(authStateProvider);
  final alertsState = ref.watch(medicationAlertsProvider);

  // Cache pour éviter les recalculs fréquents
  ref.keepAlive();

  return authState.when(
    data: (user) {
      if (user == null) return 0;

      final repository = ref.read(medicationAlertRepositoryProvider);
      return repository.getUnreadCount(alertsState.items, user.uid);
    },
    loading: () => 0,
    error: (_, __) => 0,
  );
});

// Provider pour une alerte spécifique
final medicationAlertByIdProvider = Provider.family<MedicationAlertModel?, String>((ref, alertId) {
  final alertsState = ref.watch(medicationAlertsProvider);

  try {
    return alertsState.items.firstWhere((alert) => alert.id == alertId);
  } catch (e) {
    return null;
  }
});

// Notifier pour gérer l'état des alertes
class MedicationAlertNotifier extends StateNotifier<MedicationAlertState> {
  final MedicationAlertRepository repository;
  final ConnectivityService connectivityService;
  bool _isInitialized = false;

  MedicationAlertNotifier({required this.repository, required this.connectivityService})
    : super(MedicationAlertState.initial(connectivityService.currentStatus));

  // Méthode standard de chargement avec cache
  Future<void> loadItems() async {
    // Si déjà initialisé et des données existent, ne pas recharger
    if (_isInitialized && state.items.isNotEmpty && !state.isLoading) {
      return;
    }

    // Mettre isLoading à true immédiatement
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final items = await repository.getAllAlerts();
      _isInitialized = true;
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      AppLogger.error('Error loading medication alerts', e);
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load alerts: ${e.toString()}',
      );
    }
  }

  // Forcer le rechargement
  Future<void> forceReload() async {
    repository.invalidateCache();
    _isInitialized = false;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final items = await repository.forceReload();
      _isInitialized = true;
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      AppLogger.error('Error reloading medication alerts', e);
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to reload alerts: ${e.toString()}',
      );
    }
  }

  // Rafraîchir sans invalider le cache
  Future<void> refreshData() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final items = await repository.getAllAlerts();
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      AppLogger.error('Error refreshing medication alerts', e);
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to refresh alerts: ${e.toString()}',
      );
    }
  }

  // Mettre à jour une alerte spécifique dans l'état
  void updateSingleAlert(MedicationAlertModel alert) {
    final currentItems = List<MedicationAlertModel>.from(state.items);
    final index = currentItems.indexWhere((item) => item.id == alert.id);

    if (index >= 0) {
      currentItems[index] = alert;
    } else {
      currentItems.add(alert);
      // Trier après ajout
      currentItems.sort((a, b) {
        final dateComparison = b.alertDate.compareTo(a.alertDate);
        if (dateComparison != 0) return dateComparison;
        return b.createdAt.compareTo(a.createdAt);
      });
    }

    state = state.copyWith(items: currentItems);
  }

  // Marquer comme lu
  Future<void> markAsRead(String alertId, String userId) async {
    try {
      await repository.markAsRead(alertId, userId);

      // Mettre à jour l'état local
      final currentItems = List<MedicationAlertModel>.from(state.items);
      final index = currentItems.indexWhere((item) => item.id == alertId);

      if (index >= 0) {
        final alert = currentItems[index];
        final updatedUserStates = Map<String, UserAlertState>.from(alert.userStates);
        updatedUserStates[userId] = alert
            .getUserState(userId)
            .copyWith(isRead: true, readAt: DateTime.now());

        currentItems[index] = alert.copyWith(userStates: updatedUserStates);
        state = state.copyWith(items: currentItems);
      }
    } catch (e) {
      AppLogger.error('Error marking alert as read', e);
      rethrow;
    }
  }

  // Marquer comme caché
  Future<void> markAsHidden(String alertId, String userId) async {
    try {
      await repository.markAsHidden(alertId, userId);

      // Mettre à jour l'état local
      final currentItems = List<MedicationAlertModel>.from(state.items);
      final index = currentItems.indexWhere((item) => item.id == alertId);

      if (index >= 0) {
        final alert = currentItems[index];
        final updatedUserStates = Map<String, UserAlertState>.from(alert.userStates);
        updatedUserStates[userId] = alert.getUserState(userId).copyWith(isHidden: true);

        currentItems[index] = alert.copyWith(userStates: updatedUserStates);
        state = state.copyWith(items: currentItems);
      }
    } catch (e) {
      AppLogger.error('Error marking alert as hidden', e);
      rethrow;
    }
  }

  // Marquer tout comme lu
  Future<void> markAllAsRead(String userId) async {
    try {
      await repository.markAllAsRead(userId);

      // Mettre à jour l'état local
      final currentItems = List<MedicationAlertModel>.from(state.items);
      for (var i = 0; i < currentItems.length; i++) {
        final alert = currentItems[i];
        final userState = alert.getUserState(userId);

        if (!userState.isRead && !userState.isHidden) {
          final updatedUserStates = Map<String, UserAlertState>.from(alert.userStates);
          updatedUserStates[userId] = userState.copyWith(isRead: true, readAt: DateTime.now());

          currentItems[i] = alert.copyWith(userStates: updatedUserStates);
        }
      }

      state = state.copyWith(items: currentItems);
    } catch (e) {
      AppLogger.error('Error marking all alerts as read', e);
      rethrow;
    }
  }

  // Marquer tout comme caché
  Future<void> markAllAsHidden(String userId) async {
    try {
      await repository.markAllAsHidden(userId);

      // Mettre à jour l'état local
      final currentItems = List<MedicationAlertModel>.from(state.items);
      for (var i = 0; i < currentItems.length; i++) {
        final alert = currentItems[i];
        final userState = alert.getUserState(userId);

        if (!userState.isHidden) {
          final updatedUserStates = Map<String, UserAlertState>.from(alert.userStates);
          updatedUserStates[userId] = userState.copyWith(isHidden: true);

          currentItems[i] = alert.copyWith(userStates: updatedUserStates);
        }
      }

      state = state.copyWith(items: currentItems);
    } catch (e) {
      AppLogger.error('Error marking all alerts as hidden', e);
      rethrow;
    }
  }

  Future<void> resetAllUserNotifications(String userId) async {
    try {
      await repository.resetAllUserNotifications(userId);

      // Recharger les données après le reset
      await forceReload();

      AppLogger.debug('Reset all notifications and reloaded data');
    } catch (e) {
      AppLogger.error('Error resetting all notifications', e);
      rethrow;
    }
  }
}

// État pour les alertes de médicaments
class MedicationAlertState {
  final List<MedicationAlertModel> items;
  final bool isLoading;
  final String? errorMessage;
  final bool isSyncing;
  final ConnectionStatus connectionStatus;

  MedicationAlertState({
    required this.items,
    required this.isLoading,
    this.errorMessage,
    required this.isSyncing,
    required this.connectionStatus,
  });

  factory MedicationAlertState.initial(ConnectionStatus connectionStatus) {
    return MedicationAlertState(
      items: [],
      isLoading: false,
      errorMessage: null,
      isSyncing: false,
      connectionStatus: connectionStatus,
    );
  }

  MedicationAlertState copyWith({
    List<MedicationAlertModel>? items,
    bool? isLoading,
    String? errorMessage,
    bool? clearError,
    bool? isSyncing,
    ConnectionStatus? connectionStatus,
  }) {
    return MedicationAlertState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError == true ? null : (errorMessage ?? this.errorMessage),
      isSyncing: isSyncing ?? this.isSyncing,
      connectionStatus: connectionStatus ?? this.connectionStatus,
    );
  }
}
