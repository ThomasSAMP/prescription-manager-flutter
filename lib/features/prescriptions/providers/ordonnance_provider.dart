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
  bool _hasMoreData = true;
  String? _lastOrdonnanceId;
  static const int _pageSize = 10; // Nombre d'ordonnances à charger par page

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
  Future<void> loadItems({bool refresh = false}) async {
    // Si on rafraîchit, réinitialiser la pagination
    if (refresh) {
      _lastOrdonnanceId = null;
      _hasMoreData = true;
      _isInitialized = false;
    }

    // Si déjà initialisé, pas de données supplémentaires et pas de rafraîchissement, ne pas recharger
    if (_isInitialized && !_hasMoreData && !refresh && !state.isLoading) {
      return;
    }

    // Si c'est un rafraîchissement ou la première page, montrer le chargement
    if (refresh || _lastOrdonnanceId == null) {
      state = state.copyWith(isLoading: true, clearError: true);
    } else {
      // Sinon, c'est un chargement de page supplémentaire
      state = state.copyWith(isLoadingMore: true, clearError: true);
    }

    try {
      // Charger une page d'ordonnances
      final items = await repository.getOrdonnancesPaginated(
        limit: _pageSize,
        lastOrdonnanceId: _lastOrdonnanceId,
      );

      _isInitialized = true;

      // Mettre à jour l'ID de la dernière ordonnance pour la pagination
      if (items.isNotEmpty) {
        _lastOrdonnanceId = items.last.id;
      }

      // Vérifier s'il y a plus de données à charger
      _hasMoreData = items.length == _pageSize;

      // Mettre à jour l'état avec les nouvelles ordonnances
      if (refresh) {
        // Si c'est un rafraîchissement, remplacer toutes les ordonnances
        state = state.copyWith(
          items: items,
          isLoading: false,
          isLoadingMore: false,
          hasMoreData: _hasMoreData,
        );
      } else {
        // Sinon, ajouter les nouvelles ordonnances à la liste existante
        state = state.copyWith(
          items: [...state.items, ...items],
          isLoading: false,
          isLoadingMore: false,
          hasMoreData: _hasMoreData,
        );
      }
    } catch (e) {
      AppLogger.error('Error loading ordonnances', e);
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        errorMessage: 'Failed to load ordonnances: ${e.toString()}',
      );
    }
  }

  // Méthode pour forcer le rechargement (ignorer le cache)
  Future<void> forceReload() async {
    // Invalider le cache du repository
    repository.invalidateCache();

    // Réinitialiser la pagination
    _lastOrdonnanceId = null;
    _hasMoreData = true;
    _isInitialized = false;

    // Charger les données
    await loadItems(refresh: true);
  }

  // Méthode pour charger plus d'ordonnances (pagination)
  Future<void> loadMore() async {
    if (state.isLoadingMore || !_hasMoreData) return;

    await loadItems();
  }

  // Méthode privée qui effectue le chargement réel
  Future<void> _doLoadItems() async {
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
  final bool isLoadingMore;
  final String? errorMessage;
  final bool isSyncing;
  final ConnectionStatus connectionStatus;
  final bool hasMoreData;

  OrdonnanceState({
    required this.items,
    required this.isLoading,
    required this.isLoadingMore,
    this.errorMessage,
    required this.isSyncing,
    required this.connectionStatus,
    required this.hasMoreData,
  });

  factory OrdonnanceState.initial(ConnectionStatus connectionStatus) {
    return OrdonnanceState(
      items: [],
      isLoading: false,
      isLoadingMore: false,
      errorMessage: null,
      isSyncing: false,
      connectionStatus: connectionStatus,
      hasMoreData: true,
    );
  }

  OrdonnanceState copyWith({
    List<OrdonnanceModel>? items,
    bool? isLoading,
    bool? isLoadingMore,
    String? errorMessage,
    bool? clearError,
    bool? isSyncing,
    ConnectionStatus? connectionStatus,
    bool? hasMoreData,
  }) {
    return OrdonnanceState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      errorMessage: clearError == true ? null : (errorMessage ?? this.errorMessage),
      isSyncing: isSyncing ?? this.isSyncing,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      hasMoreData: hasMoreData ?? this.hasMoreData,
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
