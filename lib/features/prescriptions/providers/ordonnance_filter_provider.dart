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

// Cache optimisé pour les statuts d'ordonnances
final ordonnanceStatusCacheProvider = Provider<Map<String, ExpirationStatus>>((ref) {
  final allMedicaments = ref.watch(allMedicamentsProvider).items;

  final statusCache = <String, ExpirationStatus>{};

  for (final medicament in allMedicaments) {
    final status = medicament.getExpirationStatus();
    final ordonnanceId = medicament.ordonnanceId;

    if (!statusCache.containsKey(ordonnanceId) || status.index > statusCache[ordonnanceId]!.index) {
      statusCache[ordonnanceId] = status;
    }
  }

  return statusCache;
});

// Provider optimisé pour les ordonnances filtrées
final filteredOrdonnancesProvider = Provider<List<OrdonnanceModel>>((ref) {
  final searchQuery = ref.watch(searchQueryProvider).trim().toLowerCase();
  final filterOption = ref.watch(filterOptionProvider);
  final ordonnancesState = ref.watch(ordonnanceProvider);
  final statusCache = ref.watch(ordonnanceStatusCacheProvider);

  if (ordonnancesState.isLoading) {
    return <OrdonnanceModel>[];
  }

  var filteredOrdonnances = ordonnancesState.items;

  // Filtrage par recherche
  if (searchQuery.isNotEmpty) {
    filteredOrdonnances =
        filteredOrdonnances.where((ordonnance) {
          return ordonnance.patientName.toLowerCase().contains(searchQuery);
        }).toList();
  }

  // Filtrage par criticité
  if (filterOption != FilterOption.all) {
    filteredOrdonnances =
        filteredOrdonnances.where((ordonnance) {
          final status = statusCache[ordonnance.id] ?? ExpirationStatus.ok;

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

  // Tri par criticité puis par nom
  filteredOrdonnances.sort((a, b) {
    final aStatus = statusCache[a.id] ?? ExpirationStatus.ok;
    final bStatus = statusCache[b.id] ?? ExpirationStatus.ok;

    final statusComparison = bStatus.index.compareTo(aStatus.index);
    if (statusComparison != 0) return statusComparison;

    return a.patientName.compareTo(b.patientName);
  });

  return filteredOrdonnances;
});

// Provider optimisé pour les comptages avec mise en cache automatique
final ordonnanceCountsProvider = Provider<Map<FilterOption, int>>((ref) {
  final allOrdonnances = ref.watch(ordonnanceProvider).items;
  final statusCache = ref.watch(ordonnanceStatusCacheProvider);

  final counts = {
    FilterOption.all: allOrdonnances.length,
    FilterOption.expired: 0,
    FilterOption.critical: 0,
    FilterOption.warning: 0,
    FilterOption.ok: 0,
  };

  var okCount = allOrdonnances.length;

  for (final ordonnance in allOrdonnances) {
    final status = statusCache[ordonnance.id] ?? ExpirationStatus.ok;

    switch (status) {
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
});

// Notifier simplifié
class FilterOptionNotifier extends StateNotifier<FilterOption> {
  final Ref _ref;

  FilterOptionNotifier(this._ref) : super(FilterOption.all);

  void setFilter(FilterOption option) {
    if (state != option) {
      state = option;
      AppLogger.debug('Filter changed to ${option.name}');
    }
  }
}
