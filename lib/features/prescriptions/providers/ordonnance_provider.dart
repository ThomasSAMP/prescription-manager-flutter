import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/injection.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/utils/logger.dart';
import '../models/ordonnance_model.dart';
import '../repositories/ordonnance_repository.dart';

final ordonnanceRepositoryProvider = Provider<OrdonnanceRepository>((ref) {
  return getIt<OrdonnanceRepository>();
});

final ordonnanceProvider = StateNotifierProvider<OrdonnanceNotifier, OrdonnanceState>((ref) {
  return OrdonnanceNotifier(
    repository: getIt<OrdonnanceRepository>(),
    connectivityService: getIt<ConnectivityService>(),
  );
});

class OrdonnanceNotifier extends StateNotifier<OrdonnanceState> {
  final OrdonnanceRepository repository;
  final ConnectivityService connectivityService;
  bool _isInitialized = false;

  OrdonnanceNotifier({required this.repository, required this.connectivityService})
    : super(OrdonnanceState.initial(connectivityService.currentStatus));

  // Rafraîchit les données sans invalider le cache
  Future<void> refreshData() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // Charger les données depuis le repository
      final items = await repository.getOrdonnances();
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      AppLogger.error('Error refreshing ordonnances', e);
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to refresh ordonnances: ${e.toString()}',
      );
    }
  }

  // Méthode standard de chargement avec vérification de cache
  Future<void> loadItems() async {
    // Si déjà initialisé et des données existent, ne pas recharger
    if (_isInitialized && state.items.isNotEmpty && !state.isLoading) {
      return;
    }

    // Mettre isLoading à true immédiatement pour déclencher l'affichage du skeleton
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final items = await repository.getOrdonnances();
      _isInitialized = true;
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      AppLogger.error('Error loading ordonnances', e);
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load ordonnances: ${e.toString()}',
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

    try {
      final items = await repository.getOrdonnances();
      _isInitialized = true;
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      AppLogger.error('Error reloading ordonnances', e);
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to reload ordonnances: ${e.toString()}',
      );
    }
  }

  // Méthode pour charger toutes les données (sans pagination)
  Future<void> loadAllData() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // Charger toutes les ordonnances
      final items = await repository.getOrdonnances();
      _isInitialized = true;

      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      AppLogger.error('Error loading all ordonnances', e);
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load ordonnances: ${e.toString()}',
      );
    }
  }

  Future<void> syncWithServer() async {
    if (state.connectionStatus == ConnectionStatus.offline) {
      state = state.copyWith(errorMessage: 'Cannot sync while offline');
      return;
    }

    state = state.copyWith(isSyncing: true, clearError: true);

    try {
      await repository.syncWithServer();
      await loadItems(); // Recharger les éléments après la synchronisation
      state = state.copyWith(isSyncing: false);
    } catch (e) {
      AppLogger.error('Error syncing with server', e);
      state = state.copyWith(
        isSyncing: false,
        errorMessage: 'Failed to sync with server: ${e.toString()}',
      );
    }
  }

  void updateSingleOrdonnance(OrdonnanceModel ordonnance) {
    // Obtenir la liste actuelle des ordonnances
    final currentItems = List<OrdonnanceModel>.from(state.items);

    // Trouver l'index de l'ordonnance à mettre à jour
    final index = currentItems.indexWhere((item) => item.id == ordonnance.id);

    if (index >= 0) {
      // Remplacer l'ordonnance existante
      currentItems[index] = ordonnance;
    } else {
      // Ajouter la nouvelle ordonnance si elle n'existe pas
      currentItems.add(ordonnance);
    }

    // Mettre à jour l'état UNIQUEMENT pour l'élément modifié, pas pour toute la liste
    state = state.copyWith(items: currentItems);
  }
}

class OrdonnanceState {
  final List<OrdonnanceModel> items;
  final bool isLoading;
  final String? errorMessage;
  final bool isSyncing;
  final ConnectionStatus connectionStatus;

  OrdonnanceState({
    required this.items,
    required this.isLoading,
    this.errorMessage,
    required this.isSyncing,
    required this.connectionStatus,
  });

  factory OrdonnanceState.initial(ConnectionStatus connectionStatus) {
    return OrdonnanceState(
      items: [],
      isLoading: false,
      errorMessage: null,
      isSyncing: false,
      connectionStatus: connectionStatus,
    );
  }

  OrdonnanceState copyWith({
    List<OrdonnanceModel>? items,
    bool? isLoading,
    String? errorMessage,
    bool? clearError,
    bool? isSyncing,
    ConnectionStatus? connectionStatus,
  }) {
    return OrdonnanceState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError == true ? null : (errorMessage ?? this.errorMessage),
      isSyncing: isSyncing ?? this.isSyncing,
      connectionStatus: connectionStatus ?? this.connectionStatus,
    );
  }
}

// Provider pour une ordonnance spécifique par ID
final ordonnanceByIdProvider = Provider.family<OrdonnanceModel?, String>((ref, id) {
  final state = ref.watch(ordonnanceProvider);
  try {
    return state.items.firstWhere((o) => o.id == id);
  } catch (e) {
    return null; // Retourne null si l'ordonnance n'est pas trouvée
  }
});

final totalOrdonnancesCountProvider = FutureProvider<int?>((ref) async {
  final repository = ref.watch(ordonnanceRepositoryProvider);
  return repository.getTotalOrdonnancesCount();
});
