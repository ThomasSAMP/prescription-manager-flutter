import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/injection.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/unified_cache_service.dart';
import '../../../core/utils/logger.dart';
import '../models/medicament_model.dart';
import '../repositories/medicament_repository.dart';

final medicamentRepositoryProvider = Provider<MedicamentRepository>((ref) {
  return getIt<MedicamentRepository>();
});

final allMedicamentsProvider = StateNotifierProvider<MedicamentNotifier, MedicamentState>((ref) {
  return MedicamentNotifier(
    repository: getIt<MedicamentRepository>(),
    connectivityService: getIt<ConnectivityService>(),
    unifiedCache: getIt<UnifiedCacheService>(),
  );
});

class MedicamentNotifier extends StateNotifier<MedicamentState> {
  final MedicamentRepository repository;
  final ConnectivityService connectivityService;
  final UnifiedCacheService unifiedCache;
  bool _isInitialized = false;

  MedicamentNotifier({
    required this.repository,
    required this.connectivityService,
    required this.unifiedCache,
  }) : super(MedicamentState.initial(connectivityService.currentStatus));

  // Méthode de chargement avec cache intelligent
  Future<void> loadItems() async {
    // Éviter les rechargements inutiles
    if (_isInitialized && state.items.isNotEmpty && !state.isLoading) {
      AppLogger.debug('MedicamentProvider: Data already loaded and cached, skipping reload');
      return;
    }

    // Vérifier d'abord le cache unifié
    final cachedData = await _checkCacheOnly();
    if (cachedData != null && cachedData.isNotEmpty) {
      _isInitialized = true;
      state = state.copyWith(items: cachedData, isLoading: false);
      AppLogger.debug('MedicamentProvider: Loaded from cache (${cachedData.length} items)');
      return;
    }

    // Si pas de cache, charger normalement
    await _performLoad();
  }

  // Vérifier seulement le cache sans déclencher de chargement
  Future<List<MedicamentModel>?> _checkCacheOnly() async {
    try {
      final hasCache = await unifiedCache.contains('medicaments');
      if (!hasCache) return null;

      return await repository.getAllMedicaments();
    } catch (e) {
      AppLogger.debug('Cache check failed, will perform full load');
      return null;
    }
  }

  // Effectuer le chargement complet
  Future<void> _performLoad() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final items = await repository.getAllMedicaments();
      _isInitialized = true;
      state = state.copyWith(items: items, isLoading: false);
      AppLogger.debug('MedicamentProvider: Loaded ${items.length} medicaments');
    } catch (e) {
      AppLogger.error('Error loading medicaments', e);
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Échec du chargement des médicaments: ${e.toString()}',
      );
    }
  }

  // Rafraîchissement intelligent
  Future<void> refreshData() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final items = await repository.getAllMedicaments();
      state = state.copyWith(items: items, isLoading: false);
      AppLogger.debug('MedicamentProvider: Refreshed ${items.length} medicaments');
    } catch (e) {
      AppLogger.error('Error refreshing medicaments', e);
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to refresh medicaments: ${e.toString()}',
      );
    }
  }

  // Rechargement forcé avec invalidation du cache
  Future<void> forceReload() async {
    AppLogger.debug('MedicamentProvider: Force reload requested');

    await repository.invalidateCache();
    _isInitialized = false;
    await _performLoad();
  }

  // Mise à jour pour une ordonnance spécifique
  void updateItemsForOrdonnance(String ordonnanceId, List<MedicamentModel> medicaments) {
    final currentItems = List<MedicamentModel>.from(state.items);

    // Supprimer les médicaments existants pour cette ordonnance
    currentItems.removeWhere((item) => item.ordonnanceId == ordonnanceId);

    // Ajouter les nouveaux médicaments
    currentItems.addAll(medicaments);

    state = state.copyWith(items: currentItems);

    // Mettre à jour le cache en arrière-plan
    _updateCacheInBackground(currentItems);

    AppLogger.debug(
      'MedicamentProvider: Updated ${medicaments.length} medicaments for ordonnance $ordonnanceId',
    );
  }

  // Mise à jour d'un médicament unique
  void updateSingleMedicament(MedicamentModel medicament) {
    final currentItems = List<MedicamentModel>.from(state.items);
    final index = currentItems.indexWhere((item) => item.id == medicament.id);

    if (index >= 0) {
      currentItems[index] = medicament;
    } else {
      currentItems.add(medicament);
    }

    state = state.copyWith(items: currentItems);

    // Mettre à jour le cache en arrière-plan
    _updateCacheInBackground(currentItems);

    // Invalider le cache spécifique à l'ordonnance
    _invalidateOrdonnanceCacheInBackground(medicament.ordonnanceId);

    AppLogger.debug('MedicamentProvider: Updated single medicament ${medicament.id}');
  }

  // Supprimer un médicament de l'état local
  void removeMedicament(String medicamentId) {
    final currentItems = List<MedicamentModel>.from(state.items);
    final medicament = currentItems.firstWhere(
      (item) => item.id == medicamentId,
      orElse: () => null as MedicamentModel,
    );

    currentItems.removeWhere((item) => item.id == medicamentId);
    state = state.copyWith(items: currentItems);

    // Mettre à jour le cache en arrière-plan
    _updateCacheInBackground(currentItems);

    // Invalider le cache spécifique à l'ordonnance si on connaît l'ordonnanceId
    _invalidateOrdonnanceCacheInBackground(medicament.ordonnanceId);

    AppLogger.debug('MedicamentProvider: Removed medicament $medicamentId from state');
  }

  // Mise à jour du cache en arrière-plan
  Future<void> _updateCacheInBackground(List<MedicamentModel> items) async {
    try {
      final cacheData = MedicamentListModel(medicaments: items, lastUpdated: DateTime.now());

      await unifiedCache.put(
        'medicaments',
        cacheData,
        ttl: const Duration(hours: 1),
        level: CacheLevel.both,
      );
    } catch (e) {
      AppLogger.error('Error updating medicaments cache in background', e);
    }
  }

  // Invalider le cache d'une ordonnance en arrière-plan
  Future<void> _invalidateOrdonnanceCacheInBackground(String ordonnanceId) async {
    try {
      await repository.invalidateCacheForOrdonnance(ordonnanceId);
    } catch (e) {
      AppLogger.error('Error invalidating ordonnance cache in background', e);
    }
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
      AppLogger.debug('MedicamentProvider: Cache cleanup completed');
    } catch (e) {
      AppLogger.error('Error during cache cleanup', e);
    }
  }
}

class MedicamentState {
  final List<MedicamentModel> items;
  final bool isLoading;
  final String? errorMessage;
  final bool isSyncing;
  final ConnectionStatus connectionStatus;
  final DateTime? lastCacheUpdate;

  MedicamentState({
    required this.items,
    required this.isLoading,
    this.errorMessage,
    required this.isSyncing,
    required this.connectionStatus,
    this.lastCacheUpdate,
  });

  factory MedicamentState.initial(ConnectionStatus connectionStatus) {
    return MedicamentState(
      items: [],
      isLoading: false,
      errorMessage: null,
      isSyncing: false,
      connectionStatus: connectionStatus,
      lastCacheUpdate: null,
    );
  }

  MedicamentState copyWith({
    List<MedicamentModel>? items,
    bool? isLoading,
    String? errorMessage,
    bool? clearError,
    bool? isSyncing,
    ConnectionStatus? connectionStatus,
    DateTime? lastCacheUpdate,
  }) {
    return MedicamentState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError == true ? null : (errorMessage ?? this.errorMessage),
      isSyncing: isSyncing ?? this.isSyncing,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      lastCacheUpdate: lastCacheUpdate ?? this.lastCacheUpdate,
    );
  }

  bool get hasData => items.isNotEmpty;
  bool get hasError => errorMessage != null;
  bool get isIdle => !isLoading && !isSyncing;

  bool get isDataFresh {
    if (lastCacheUpdate == null) return false;
    return DateTime.now().difference(lastCacheUpdate!) < const Duration(minutes: 30);
  }
}

// Providers avec cache
final medicamentsByOrdonnanceProvider = Provider.family<List<MedicamentModel>, String>((
  ref,
  ordonnanceId,
) {
  final state = ref.watch(allMedicamentsProvider);

  // Cache automatique avec keepAlive
  ref.keepAlive();

  return state.items.where((m) => m.ordonnanceId == ordonnanceId).toList();
});

final expiringMedicamentsProvider = Provider<List<MedicamentModel>>((ref) {
  final state = ref.watch(allMedicamentsProvider);

  ref.keepAlive();

  return state.items.where((m) => m.getExpirationStatus().needsAttention).toList();
});

final medicamentByIdProvider = Provider.family<MedicamentModel?, String>((ref, id) {
  final state = ref.watch(allMedicamentsProvider);

  ref.keepAlive();

  try {
    return state.items.firstWhere((m) => m.id == id);
  } catch (e) {
    return null;
  }
});

// Provider pour les statistiques de cache
final medicamentCacheStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final notifier = ref.read(allMedicamentsProvider.notifier);
  return notifier.getCacheStats();
});
