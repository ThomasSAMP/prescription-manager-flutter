import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/injection.dart';
import '../../../core/providers/offline_data_provider.dart';
import '../../../core/services/connectivity_service.dart';
import '../models/medicament_model.dart';
import '../repositories/medicament_repository.dart';

final medicamentRepositoryProvider = Provider<MedicamentRepository>((ref) {
  return getIt<MedicamentRepository>();
});

// Provider pour tous les médicaments
final allMedicamentsProvider = createOfflineDataProvider<MedicamentModel>(
  repository: getIt<MedicamentRepository>(),
  connectivityService: getIt<ConnectivityService>(),
  fetchItems: () => getIt<MedicamentRepository>().getAllMedicaments(),
);

// Provider pour les médicaments par ordonnance
final medicamentsByOrdonnanceProvider = Provider.family<List<MedicamentModel>, String>((
  ref,
  ordonnanceId,
) {
  final state = ref.watch(allMedicamentsProvider);
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
