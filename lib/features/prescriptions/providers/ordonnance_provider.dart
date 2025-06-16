import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/injection.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/unified_cache_service.dart';
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
    unifiedCache: getIt<UnifiedCacheService>(),
  );
});

class OrdonnanceNotifier extends StateNotifier<OrdonnanceState> {
  final OrdonnanceRepository repository;
  final ConnectivityService connectivityService;
  final UnifiedCacheService unifiedCache;
  bool _isInitialized = false;

  OrdonnanceNotifier({
    required this.repository,
    required this.connectivityService,
    required this.unifiedCache,
  }) : super(OrdonnanceState.initial(connectivityService.currentStatus));

  // Méthode standard de chargement avec vérification de cache
  Future<void> loadItems() async {
    // Éviter les rechargements inutiles
    if (_isInitialized && state.items.isNotEmpty && !state.isLoading) {
      AppLogger.debug('OrdonnanceProvider: Data already loaded and cached, skipping reload');
      return;
    }

    // Vérifier d'abord le cache unifié sans déclencher de chargement
    final cachedData = await _checkCacheOnly();
    if (cachedData != null && cachedData.isNotEmpty) {
      _isInitialized = true;
      state = state.copyWith(items: cachedData, isLoading: false);
      AppLogger.debug('OrdonnanceProvider: Loaded from cache (${cachedData.length} items)');
      return;
    }

    // Si pas de cache, charger normalement
    await _performLoad();
  }

  // Vérifier seulement le cache sans déclencher de chargement
  Future<List<OrdonnanceModel>?> _checkCacheOnly() async {
    try {
      // Utiliser une vérification rapide du cache
      final hasCache = await unifiedCache.contains('ordonnances');
      if (!hasCache) return null;

      // Charger depuis le cache seulement
      return await repository.getOrdonnances();
    } catch (e) {
      AppLogger.debug('Cache check failed, will perform full load');
      return null;
    }
  }

  // Effectuer le chargement complet
  Future<void> _performLoad() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final items = await repository.getOrdonnances();
      _isInitialized = true;
      state = state.copyWith(items: items, isLoading: false);
      AppLogger.debug('OrdonnanceProvider: Loaded ${items.length} ordonnances');
    } catch (e) {
      AppLogger.error('Error loading ordonnances', e);
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load ordonnances: ${e.toString()}',
      );
    }
  }

  // Rafraîchissement intelligent sans invalider le cache
  Future<void> refreshData() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // Charger les données fraîches (le repository gère le cache automatiquement)
      final items = await repository.getOrdonnances();
      state = state.copyWith(items: items, isLoading: false);
      AppLogger.debug('OrdonnanceProvider: Refreshed ${items.length} ordonnances');
    } catch (e) {
      AppLogger.error('Error refreshing ordonnances', e);
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to refresh ordonnances: ${e.toString()}',
      );
    }
  }

  // Rechargement forcé avec invalidation du cache
  Future<void> forceReload() async {
    AppLogger.debug('OrdonnanceProvider: Force reload requested');

    // Invalider le cache du repository
    await repository.invalidateCache();

    // Réinitialiser le flag d'initialisation
    _isInitialized = false;

    // Charger les données
    await _performLoad();
  }

  // Chargement de toutes les données (pour les filtres)
  Future<void> loadAllData() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // Utiliser la méthode standard qui gère déjà le cache
      final items = await repository.getOrdonnances();
      _isInitialized = true;
      state = state.copyWith(items: items, isLoading: false);
      AppLogger.debug('OrdonnanceProvider: Loaded all data (${items.length} ordonnances)');
    } catch (e) {
      AppLogger.error('Error loading all ordonnances', e);
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load ordonnances: ${e.toString()}',
      );
    }
  }

  // Synchronisation avec le serveur
  Future<void> syncWithServer() async {
    if (state.connectionStatus == ConnectionStatus.offline) {
      state = state.copyWith(errorMessage: 'Cannot sync while offline');
      return;
    }

    state = state.copyWith(isSyncing: true, clearError: true);

    try {
      await repository.syncWithServer();

      // Invalider le cache et recharger pour avoir les données les plus récentes
      await repository.invalidateCache();
      await loadItems();

      state = state.copyWith(isSyncing: false);
      AppLogger.info('OrdonnanceProvider: Sync completed successfully');
    } catch (e) {
      AppLogger.error('Error syncing with server', e);
      state = state.copyWith(
        isSyncing: false,
        errorMessage: 'Failed to sync with server: ${e.toString()}',
      );
    }
  }

  // Mise à jour d'une ordonnance unique
  void updateSingleOrdonnance(OrdonnanceModel ordonnance) {
    final currentItems = List<OrdonnanceModel>.from(state.items);
    final index = currentItems.indexWhere((item) => item.id == ordonnance.id);

    if (index >= 0) {
      currentItems[index] = ordonnance;
    } else {
      currentItems.add(ordonnance);
      // Trier après ajout
      currentItems.sort((a, b) => a.patientName.compareTo(b.patientName));
    }

    state = state.copyWith(items: currentItems);

    // Mettre à jour le cache en arrière-plan
    _updateCacheInBackground(currentItems);

    AppLogger.debug('OrdonnanceProvider: Updated single ordonnance ${ordonnance.id}');
  }

  // Mise à jour du cache en arrière-plan
  Future<void> _updateCacheInBackground(List<OrdonnanceModel> items) async {
    try {
      // Créer un wrapper pour le cache
      final cacheData = OrdonnanceListModel(ordonnances: items, lastUpdated: DateTime.now());

      await unifiedCache.put(
        'ordonnances',
        cacheData,
        ttl: const Duration(hours: 2),
        level: CacheLevel.both,
      );
    } catch (e) {
      AppLogger.error('Error updating cache in background', e);
    }
  }

  // Supprimer une ordonnance de l'état local
  void removeOrdonnance(String ordonnanceId) {
    final currentItems = List<OrdonnanceModel>.from(state.items);
    currentItems.removeWhere((item) => item.id == ordonnanceId);

    state = state.copyWith(items: currentItems);

    // Mettre à jour le cache en arrière-plan
    _updateCacheInBackground(currentItems);

    AppLogger.debug('OrdonnanceProvider: Removed ordonnance $ordonnanceId from state');
  }

  // Obtenir les statistiques du cache
  Future<Map<String, dynamic>> getCacheStats() async {
    try {
      return await unifiedCache.getStats();
    } catch (e) {
      AppLogger.error('Error getting cache stats', e);
      return {};
    }
  }

  // Nettoyer le cache expiré
  Future<void> cleanupCache() async {
    try {
      await unifiedCache.cleanup();
      AppLogger.debug('OrdonnanceProvider: Cache cleanup completed');
    } catch (e) {
      AppLogger.error('Error during cache cleanup', e);
    }
  }
}

class OrdonnanceState {
  final List<OrdonnanceModel> items;
  final bool isLoading;
  final String? errorMessage;
  final bool isSyncing;
  final ConnectionStatus connectionStatus;
  final DateTime? lastCacheUpdate;

  OrdonnanceState({
    required this.items,
    required this.isLoading,
    this.errorMessage,
    required this.isSyncing,
    required this.connectionStatus,
    this.lastCacheUpdate,
  });

  factory OrdonnanceState.initial(ConnectionStatus connectionStatus) {
    return OrdonnanceState(
      items: [],
      isLoading: false,
      errorMessage: null,
      isSyncing: false,
      connectionStatus: connectionStatus,
      lastCacheUpdate: null,
    );
  }

  OrdonnanceState copyWith({
    List<OrdonnanceModel>? items,
    bool? isLoading,
    String? errorMessage,
    bool? clearError,
    bool? isSyncing,
    ConnectionStatus? connectionStatus,
    DateTime? lastCacheUpdate,
  }) {
    return OrdonnanceState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError == true ? null : (errorMessage ?? this.errorMessage),
      isSyncing: isSyncing ?? this.isSyncing,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      lastCacheUpdate: lastCacheUpdate ?? this.lastCacheUpdate,
    );
  }

  // Propriétés utilitaires
  bool get hasData => items.isNotEmpty;
  bool get hasError => errorMessage != null;
  bool get isIdle => !isLoading && !isSyncing;

  // Vérifier si les données sont récentes (moins de 30 minutes)
  bool get isDataFresh {
    if (lastCacheUpdate == null) return false;
    return DateTime.now().difference(lastCacheUpdate!) < const Duration(minutes: 30);
  }
}

// Provider pour une ordonnance spécifique avec cache
final ordonnanceByIdProvider = Provider.family<OrdonnanceModel?, String>((ref, id) {
  final state = ref.watch(ordonnanceProvider);

  // Utiliser keepAlive pour éviter les recalculs
  ref.keepAlive();

  try {
    return state.items.firstWhere((o) => o.id == id);
  } catch (e) {
    return null;
  }
});

// Provider pour le nombre total d'ordonnances avec cache
final totalOrdonnancesCountProvider = FutureProvider<int?>((ref) async {
  final repository = ref.watch(ordonnanceRepositoryProvider);

  // Utiliser keepAlive pour la performance
  ref.keepAlive();

  return repository.getTotalOrdonnancesCount();
});

// Provider pour les statistiques de cache
final ordonnanceCacheStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final notifier = ref.read(ordonnanceProvider.notifier);
  return notifier.getCacheStats();
});
