import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/injection.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/utils/logger.dart';
import '../models/notification_model.dart';
import '../repositories/notification_repository.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return getIt<NotificationRepository>();
});

// Provider optimisé pour les notifications avec cache
final notificationsProvider = StateNotifierProvider<NotificationNotifier, NotificationState>((ref) {
  return NotificationNotifier(
    repository: getIt<NotificationRepository>(),
    connectivityService: getIt<ConnectivityService>(),
  );
});

// Provider pour les notifications groupées par date
final groupedNotificationsProvider = Provider<Map<String, List<NotificationModel>>>((ref) {
  final state = ref.watch(notificationsProvider);

  // Court-circuiter si en chargement
  if (state.isLoading) {
    return <String, List<NotificationModel>>{};
  }

  final grouped = <String, List<NotificationModel>>{};

  for (final notification in state.items) {
    final group = notification.getDateGroup();
    if (!grouped.containsKey(group)) {
      grouped[group] = [];
    }
    grouped[group]!.add(notification);
  }

  return grouped;
});

final notificationsStreamProvider = StreamProvider<List<NotificationModel>>((ref) {
  final repository = ref.watch(notificationRepositoryProvider);
  return repository.getNotificationsStream();
});

// Notifier pour gérer l'état des notifications avec cache
class NotificationNotifier extends StateNotifier<NotificationState> {
  final NotificationRepository repository;
  final ConnectivityService connectivityService;
  bool _isInitialized = false;

  NotificationNotifier({required this.repository, required this.connectivityService})
    : super(NotificationState.initial(connectivityService.currentStatus));

  // Méthode standard de chargement avec vérification de cache
  Future<void> loadItems() async {
    // Si déjà initialisé et des données existent, ne pas recharger
    if (_isInitialized && state.items.isNotEmpty && !state.isLoading) {
      return;
    }

    // Mettre isLoading à true immédiatement pour déclencher l'affichage du skeleton
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final items = await repository.getAllNotifications();
      _isInitialized = true;
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      AppLogger.error('Error loading notifications', e);
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load notifications: ${e.toString()}',
      );
    }
  }

  // Méthode pour forcer le rechargement (ignorer le cache)
  Future<void> forceReload() async {
    // Invalider le cache du repository
    repository.invalidateCache();
    // Réinitialiser le flag d'initialisation
    _isInitialized = false;

    // Mettre isLoading à true immédiatement
    state = state.copyWith(isLoading: true, clearError: true);

    // Charger les données
    try {
      final items = await repository.forceReload();
      _isInitialized = true;
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      AppLogger.error('Error reloading notifications', e);
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to reload notifications: ${e.toString()}',
      );
    }
  }

  // Rafraîchit les données sans invalider le cache
  Future<void> refreshData() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // Charger les données depuis le repository
      final items = await repository.getAllNotifications();
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      AppLogger.error('Error refreshing notifications', e);
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to refresh notifications: ${e.toString()}',
      );
    }
  }

  // Méthode pour mettre à jour une notification spécifique
  void updateSingleNotification(NotificationModel notification) {
    final currentItems = List<NotificationModel>.from(state.items);
    final index = currentItems.indexWhere((item) => item.id == notification.id);

    if (index >= 0) {
      currentItems[index] = notification;
    } else {
      currentItems.add(notification);
    }

    state = state.copyWith(items: currentItems);
  }

  // Méthode pour supprimer une notification de l'état
  void removeNotification(String notificationId) {
    final currentItems = List<NotificationModel>.from(state.items);
    currentItems.removeWhere((item) => item.id == notificationId);
    state = state.copyWith(items: currentItems);
  }
}

// État pour les notifications
class NotificationState {
  final List<NotificationModel> items;
  final bool isLoading;
  final String? errorMessage;
  final bool isSyncing;
  final ConnectionStatus connectionStatus;

  NotificationState({
    required this.items,
    required this.isLoading,
    this.errorMessage,
    required this.isSyncing,
    required this.connectionStatus,
  });

  factory NotificationState.initial(ConnectionStatus connectionStatus) {
    return NotificationState(
      items: [],
      isLoading: false,
      errorMessage: null,
      isSyncing: false,
      connectionStatus: connectionStatus,
    );
  }

  NotificationState copyWith({
    List<NotificationModel>? items,
    bool? isLoading,
    String? errorMessage,
    bool? clearError,
    bool? isSyncing,
    ConnectionStatus? connectionStatus,
  }) {
    return NotificationState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError == true ? null : (errorMessage ?? this.errorMessage),
      isSyncing: isSyncing ?? this.isSyncing,
      connectionStatus: connectionStatus ?? this.connectionStatus,
    );
  }
}
