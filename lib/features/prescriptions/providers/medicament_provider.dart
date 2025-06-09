import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/injection.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/utils/logger.dart';
import '../models/medicament_model.dart';
import '../repositories/medicament_repository.dart';

final medicamentRepositoryProvider = Provider<MedicamentRepository>((ref) {
  return getIt<MedicamentRepository>();
});

// Provider pour tous les médicaments
final allMedicamentsProvider = StateNotifierProvider<MedicamentNotifier, MedicamentState>((ref) {
  return MedicamentNotifier(
    repository: getIt<MedicamentRepository>(),
    connectivityService: getIt<ConnectivityService>(),
  );
});

// Provider mémorisé pour les médicaments par ordonnance
final medicamentsByOrdonnanceProvider = Provider.family<List<MedicamentModel>, String>((
  ref,
  ordonnanceId,
) {
  final state = ref.watch(allMedicamentsProvider);

  // Mémoriser le résultat pour éviter les recalculs inutiles
  return state.items.where((m) => m.ordonnanceId == ordonnanceId).toList();
});

// Provider pour les médicaments qui arrivent à expiration
final expiringMedicamentsProvider = Provider<List<MedicamentModel>>((ref) {
  final state = ref.watch(allMedicamentsProvider);
  return state.items.where((m) => m.getExpirationStatus().needsAttention).toList();
});

// Provider pour un médicament spécifique par ID
final medicamentByIdProvider = Provider.family<MedicamentModel?, String>((ref, id) {
  final state = ref.watch(allMedicamentsProvider);
  try {
    return state.items.firstWhere((m) => m.id == id);
  } catch (e) {
    return null; // Retourne null si le médicament n'est pas trouvé
  }
});

class MedicamentNotifier extends StateNotifier<MedicamentState> {
  final MedicamentRepository repository;
  final ConnectivityService connectivityService;
  bool _isInitialized = false;

  MedicamentNotifier({required this.repository, required this.connectivityService})
    : super(MedicamentState.initial(connectivityService.currentStatus));

  // Rafraîchit les données sans invalider le cache
  Future<void> refreshData() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // Charger les données depuis le repository
      final items = await repository.getAllMedicaments();
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      AppLogger.error('Error refreshing medicaments', e);
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to refresh medicaments: ${e.toString()}',
      );
    }
  }

  // Méthode standard de chargement avec vérification de cache
  Future<void> loadItems() async {
    // Vérifier si un chargement est déjà en cours
    if (state.isLoading) {
      AppLogger.debug('Load already in progress, skipping');
      return;
    }

    // Si déjà initialisé et des données existent, ne pas recharger
    if (_isInitialized && state.items.isNotEmpty) {
      AppLogger.debug('Data already loaded, skipping reload');
      return;
    }

    // Mettre isLoading à true immédiatement pour déclencher l'affichage du skeleton
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final items = await repository.getAllMedicaments();
      _isInitialized = true;
      if (items.isEmpty) {
        AppLogger.warning('No medicaments loaded - this might be expected for new users');
      }
      state = state.copyWith(items: items, isLoading: false);
      AppLogger.debug('Successfully loaded ${items.length} medicaments');
    } catch (e) {
      AppLogger.error('Error loading medicaments', e);
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Échec du chargement des médicaments: ${e.toString()}',
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
      final items = await repository.getAllMedicaments();
      _isInitialized = true;
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      AppLogger.error('Error reloading medicaments', e);
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to reload medicaments: ${e.toString()}',
      );
    }
  }

  void updateItemsForOrdonnance(String ordonnanceId, List<MedicamentModel> medicaments) {
    // Obtenir la liste actuelle des médicaments
    final currentItems = List<MedicamentModel>.from(state.items);

    // Supprimer les médicaments existants pour cette ordonnance
    currentItems.removeWhere((item) => item.ordonnanceId == ordonnanceId);

    // Ajouter les nouveaux médicaments
    currentItems.addAll(medicaments);

    // Mettre à jour l'état avec la liste complète
    state = state.copyWith(items: currentItems);
  }

  void updateSingleMedicament(MedicamentModel medicament) {
    // Obtenir la liste actuelle des médicaments
    final currentItems = List<MedicamentModel>.from(state.items);

    // Trouver l'index du médicament à mettre à jour
    final index = currentItems.indexWhere((item) => item.id == medicament.id);

    if (index >= 0) {
      // Remplacer le médicament existant
      currentItems[index] = medicament;
    } else {
      // Ajouter le nouveau médicament s'il n'existe pas
      currentItems.add(medicament);
    }

    // Mettre à jour l'état avec la liste complète
    state = state.copyWith(items: currentItems);
  }
}

class MedicamentState {
  final List<MedicamentModel> items;
  final bool isLoading;
  final String? errorMessage;
  final bool isSyncing;
  final ConnectionStatus connectionStatus;

  MedicamentState({
    required this.items,
    required this.isLoading,
    this.errorMessage,
    required this.isSyncing,
    required this.connectionStatus,
  });

  factory MedicamentState.initial(ConnectionStatus connectionStatus) {
    return MedicamentState(
      items: [],
      isLoading: false,
      errorMessage: null,
      isSyncing: false,
      connectionStatus: connectionStatus,
    );
  }

  MedicamentState copyWith({
    List<MedicamentModel>? items,
    bool? isLoading,
    String? errorMessage,
    bool? clearError,
    bool? isSyncing,
    ConnectionStatus? connectionStatus,
  }) {
    return MedicamentState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError == true ? null : (errorMessage ?? this.errorMessage),
      isSyncing: isSyncing ?? this.isSyncing,
      connectionStatus: connectionStatus ?? this.connectionStatus,
    );
  }
}
