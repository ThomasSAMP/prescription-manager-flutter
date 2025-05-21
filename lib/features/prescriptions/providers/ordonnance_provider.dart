import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/injection.dart';
import '../../../core/providers/offline_data_provider.dart';
import '../../../core/services/connectivity_service.dart';
import '../models/ordonnance_model.dart';
import '../repositories/ordonnance_repository.dart';

final ordonnanceRepositoryProvider = Provider<OrdonnanceRepository>((ref) {
  return getIt<OrdonnanceRepository>();
});

final ordonnanceProvider = createOfflineDataProvider<OrdonnanceModel>(
  repository: getIt<OrdonnanceRepository>(),
  connectivityService: getIt<ConnectivityService>(),
  fetchItems: () => getIt<OrdonnanceRepository>().getOrdonnances(),
);

// Provider pour une ordonnance spécifique par ID
final ordonnanceByIdProvider = Provider.family<OrdonnanceModel?, String>((ref, id) {
  final state = ref.watch(ordonnanceProvider);
  try {
    return state.items.firstWhere((o) => o.id == id);
  } catch (e) {
    return null; // Retourne null si l'ordonnance n'est pas trouvée
  }
});
