import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../models/filter_options.dart';
import '../models/medicament_model.dart';
import '../models/ordonnance_model.dart';
import 'medicament_provider.dart';
import 'ordonnance_provider.dart';

// Provider pour la requête de recherche
final searchQueryProvider = StateProvider<String>((ref) => '');

// Provider pour l'option de filtrage
final filterOptionProvider = StateNotifierProvider<FilterOptionNotifier, FilterOption>((ref) {
  return FilterOptionNotifier(ref);
});

// Cache simple pour les comptages
class _CountsCache {
  static Map<FilterOption, int>? _cached;
  static DateTime? _cacheTime;
  static const Duration _cacheValidityDuration = Duration(minutes: 2);

  static bool get isValid {
    if (_cached == null || _cacheTime == null) return false;
    return DateTime.now().difference(_cacheTime!) < _cacheValidityDuration;
  }

  static Map<FilterOption, int>? get cached => isValid ? _cached : null;

  static void update(Map<FilterOption, int> counts) {
    _cached = counts;
    _cacheTime = DateTime.now();
    AppLogger.debug('Updated counts cache: $counts');
  }

  static void invalidate() {
    _cached = null;
    _cacheTime = null;
    AppLogger.debug('Invalidated counts cache');
  }
}

// Notifier pour gérer les changements d'option de filtrage
class FilterOptionNotifier extends StateNotifier<FilterOption> {
  final Ref _ref;

  FilterOptionNotifier(this._ref) : super(FilterOption.all);

  Future<void> setFilter(FilterOption option) async {
    if (option != FilterOption.all) {
      AppLogger.debug('Changing filter to ${option.name}, loading all data');

      final previousState = state;
      state = option;

      try {
        await _ref.read(ordonnanceProvider.notifier).loadAllData();
        // Invalider le cache des comptages lors du changement de filtre
        _CountsCache.invalidate();
      } catch (e) {
        state = previousState;
        rethrow;
      }
    } else {
      state = option;
    }
  }
}

// Provider pour les ordonnances filtrées et triées (optimisé)
final filteredOrdonnancesProvider = Provider<List<OrdonnanceModel>>((ref) {
  final searchQuery = ref.watch(searchQueryProvider).trim().toLowerCase();
  final filterOption = ref.watch(filterOptionProvider);
  final ordonnancesState = ref.watch(ordonnanceProvider);

  if (ordonnancesState.isLoading) {
    return <OrdonnanceModel>[];
  }

  final allMedicaments = ref.watch(allMedicamentsProvider).items;

  // Créer un cache des statuts pour éviter les recalculs
  final ordonnanceStatuses = <String, ExpirationStatus>{};
  for (final medicament in allMedicaments) {
    final status = medicament.getExpirationStatus();
    final ordonnanceId = medicament.ordonnanceId;

    if (!ordonnanceStatuses.containsKey(ordonnanceId) ||
        status.index > ordonnanceStatuses[ordonnanceId]!.index) {
      ordonnanceStatuses[ordonnanceId] = status;
    }
  }

  // Étape 1: Filtrer par recherche
  var filteredOrdonnances = ordonnancesState.items;
  if (searchQuery.isNotEmpty) {
    filteredOrdonnances =
        filteredOrdonnances.where((ordonnance) {
          return ordonnance.patientName.toLowerCase().contains(searchQuery);
        }).toList();
  }

  // Étape 2: Filtrer par criticité avec cache des statuts
  if (filterOption != FilterOption.all) {
    filteredOrdonnances =
        filteredOrdonnances.where((ordonnance) {
          final status = ordonnanceStatuses[ordonnance.id] ?? ExpirationStatus.ok;

          switch (filterOption) {
            case FilterOption.expired:
              return status == ExpirationStatus.expired;
            case FilterOption.critical:
              return status == ExpirationStatus.critical;
            case FilterOption.warning:
              return status == ExpirationStatus.warning;
            case FilterOption.ok:
              return status == ExpirationStatus.ok;
            default:
              return true;
          }
        }).toList();
  }

  // Étape 3: Trier par criticité
  filteredOrdonnances.sort((a, b) {
    final aStatus = ordonnanceStatuses[a.id] ?? ExpirationStatus.ok;
    final bStatus = ordonnanceStatuses[b.id] ?? ExpirationStatus.ok;

    final statusComparison = bStatus.index.compareTo(aStatus.index);
    if (statusComparison != 0) return statusComparison;

    return a.patientName.compareTo(b.patientName);
  });

  return filteredOrdonnances;
});

// Provider optimisé pour les comptages exacts avec cache spécialisé
final exactOrdonnanceCountsProvider = FutureProvider<Map<FilterOption, int>>((ref) async {
  // Vérifier le cache spécialisé
  final cached = _CountsCache.cached;
  if (cached != null) {
    AppLogger.debug('Using cached ordonnance counts');
    return cached;
  }

  try {
    final ordonnanceRepo = ref.watch(ordonnanceRepositoryProvider);
    final medicamentRepo = ref.watch(medicamentRepositoryProvider);

    // Obtenir toutes les données
    final allOrdonnances = await ordonnanceRepo.getOrdonnancesWithoutPagination();
    final allMedicaments = await medicamentRepo.getAllMedicaments();

    // Calculer les comptages
    final counts = _calculateCounts(allOrdonnances, allMedicaments);

    // Mettre en cache le résultat
    _CountsCache.update(counts);

    return counts;
  } catch (e) {
    AppLogger.error('Error calculating exact ordonnance counts', e);
    return {
      FilterOption.all: 0,
      FilterOption.expired: 0,
      FilterOption.critical: 0,
      FilterOption.warning: 0,
      FilterOption.ok: 0,
    };
  }
});

// Fonction utilitaire pour calculer les comptages
Map<FilterOption, int> _calculateCounts(
  List<OrdonnanceModel> ordonnances,
  List<MedicamentModel> medicaments,
) {
  final counts = {
    FilterOption.all: ordonnances.length,
    FilterOption.expired: 0,
    FilterOption.critical: 0,
    FilterOption.warning: 0,
    FilterOption.ok: 0,
  };

  final ordonnanceStatuses = <String, ExpirationStatus>{};

  // Calculer le statut le plus critique pour chaque ordonnance
  for (final medicament in medicaments) {
    final status = medicament.getExpirationStatus();
    final ordonnanceId = medicament.ordonnanceId;

    if (!ordonnanceStatuses.containsKey(ordonnanceId) ||
        status.index > ordonnanceStatuses[ordonnanceId]!.index) {
      ordonnanceStatuses[ordonnanceId] = status;
    }
  }

  // Compter par statut
  var okCount = ordonnances.length;

  for (final entry in ordonnanceStatuses.entries) {
    switch (entry.value) {
      case ExpirationStatus.expired:
        counts[FilterOption.expired] = counts[FilterOption.expired]! + 1;
        okCount--;
        break;
      case ExpirationStatus.critical:
        counts[FilterOption.critical] = counts[FilterOption.critical]! + 1;
        okCount--;
        break;
      case ExpirationStatus.warning:
        counts[FilterOption.warning] = counts[FilterOption.warning]! + 1;
        okCount--;
        break;
      default:
        break;
    }
  }

  counts[FilterOption.ok] = okCount;
  return counts;
}

// Provider pour les comptages avec fallback optimisé
final ordonnanceCountsProvider = Provider<Map<FilterOption, int>>((ref) {
  final exactCountsAsync = ref.watch(exactOrdonnanceCountsProvider);

  return exactCountsAsync.when(
    data: (exactCounts) => exactCounts,
    loading: () => _getFallbackCounts(ref),
    error: (_, __) => _getFallbackCounts(ref),
  );
});

// Fonction utilitaire pour les comptages de fallback
Map<FilterOption, int> _getFallbackCounts(Ref ref) {
  final ordonnancesState = ref.watch(ordonnanceProvider);
  final allMedicaments = ref.watch(allMedicamentsProvider).items;

  return _calculateCounts(ordonnancesState.items, allMedicaments);
}
