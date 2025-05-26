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

// Notifier pour gérer les changements d'option de filtrage
class FilterOptionNotifier extends StateNotifier<FilterOption> {
  final Ref _ref;

  FilterOptionNotifier(this._ref) : super(FilterOption.all);

  Future<void> setFilter(FilterOption option) async {
    // Si on change de filtre et que le nouveau filtre n'est pas "Tous"
    if (option != FilterOption.all) {
      AppLogger.debug('Changing filter to ${option.name}, loading all data');

      // Afficher un indicateur de chargement
      final previousState = state;
      state = option; // Mettre à jour l'état immédiatement pour l'UI

      try {
        // Charger toutes les données sans pagination
        await _ref.read(ordonnanceProvider.notifier).loadAllData();
      } catch (e) {
        // En cas d'erreur, revenir au filtre précédent
        state = previousState;
        rethrow;
      }
    } else {
      // Si on revient au filtre "Tous", pas besoin de charger toutes les données
      state = option;
    }
  }
}

// Provider pour les ordonnances filtrées et triées
final filteredOrdonnancesProvider = Provider<List<OrdonnanceModel>>((ref) {
  final searchQuery = ref.watch(searchQueryProvider).trim().toLowerCase();
  final filterOption = ref.watch(filterOptionProvider);
  final ordonnancesState = ref.watch(ordonnanceProvider);
  final allMedicaments = ref.watch(allMedicamentsProvider).items;

  // Étape 1: Filtrer par recherche
  var filteredOrdonnances = ordonnancesState.items;
  if (searchQuery.isNotEmpty) {
    filteredOrdonnances =
        filteredOrdonnances.where((ordonnance) {
          final patientName = ordonnance.patientName.toLowerCase();
          return patientName.contains(searchQuery);
        }).toList();
  }

  // Étape 2: Filtrer par criticité
  if (filterOption != FilterOption.all) {
    filteredOrdonnances =
        filteredOrdonnances.where((ordonnance) {
          // Trouver les médicaments pour cette ordonnance
          final medicaments = allMedicaments.where((m) => m.ordonnanceId == ordonnance.id).toList();

          // Si aucun médicament, considérer comme OK
          if (medicaments.isEmpty) {
            return filterOption == FilterOption.ok;
          }

          // Déterminer la criticité la plus élevée
          final statuses = medicaments.map((m) => m.getExpirationStatus()).toList();

          switch (filterOption) {
            case FilterOption.expired:
              return statuses.contains(ExpirationStatus.expired);
            case FilterOption.critical:
              return statuses.contains(ExpirationStatus.critical) &&
                  !statuses.contains(ExpirationStatus.expired);
            case FilterOption.warning:
              return statuses.contains(ExpirationStatus.warning) &&
                  !statuses.contains(ExpirationStatus.critical) &&
                  !statuses.contains(ExpirationStatus.expired);
            case FilterOption.ok:
              return statuses.every((s) => s == ExpirationStatus.ok);
            default:
              return true;
          }
        }).toList();
  }

  // Étape 3: Trier par criticité (du plus critique au moins critique)
  filteredOrdonnances.sort((a, b) {
    // Trouver les médicaments pour ces ordonnances
    final aMedicaments = allMedicaments.where((m) => m.ordonnanceId == a.id).toList();
    final bMedicaments = allMedicaments.where((m) => m.ordonnanceId == b.id).toList();

    // Déterminer la criticité la plus élevée pour chaque ordonnance
    final aStatus =
        aMedicaments.isEmpty
            ? ExpirationStatus.ok
            : aMedicaments
                .map((m) => m.getExpirationStatus())
                .reduce((value, element) => value.index > element.index ? value : element);

    final bStatus =
        bMedicaments.isEmpty
            ? ExpirationStatus.ok
            : bMedicaments
                .map((m) => m.getExpirationStatus())
                .reduce((value, element) => value.index > element.index ? value : element);

    // Comparer par criticité (du plus critique au moins critique)
    final statusComparison = bStatus.index.compareTo(aStatus.index);
    if (statusComparison != 0) return statusComparison;

    // Si même criticité, trier par nom du patient
    return a.patientName.compareTo(b.patientName);
  });

  return filteredOrdonnances;
});

// Provider pour obtenir le nombre d'ordonnances par catégorie de criticité
final ordonnanceCountsProvider = Provider<Map<FilterOption, int>>((ref) {
  final ordonnancesState = ref.watch(ordonnanceProvider);
  final allMedicaments = ref.watch(allMedicamentsProvider).items;

  final counts = {
    FilterOption.all: ordonnancesState.items.length,
    FilterOption.expired: 0,
    FilterOption.critical: 0,
    FilterOption.warning: 0,
    FilterOption.ok: 0,
  };

  for (final ordonnance in ordonnancesState.items) {
    // Trouver les médicaments pour cette ordonnance
    final medicaments = allMedicaments.where((m) => m.ordonnanceId == ordonnance.id).toList();

    // Si aucun médicament, considérer comme OK
    if (medicaments.isEmpty) {
      counts[FilterOption.ok] = counts[FilterOption.ok]! + 1;
      continue;
    }

    // Déterminer la criticité la plus élevée
    final statuses = medicaments.map((m) => m.getExpirationStatus()).toList();

    if (statuses.contains(ExpirationStatus.expired)) {
      counts[FilterOption.expired] = counts[FilterOption.expired]! + 1;
    } else if (statuses.contains(ExpirationStatus.critical)) {
      counts[FilterOption.critical] = counts[FilterOption.critical]! + 1;
    } else if (statuses.contains(ExpirationStatus.warning)) {
      counts[FilterOption.warning] = counts[FilterOption.warning]! + 1;
    } else {
      counts[FilterOption.ok] = counts[FilterOption.ok]! + 1;
    }
  }

  return counts;
});
