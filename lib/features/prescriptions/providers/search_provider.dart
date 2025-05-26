import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ordonnance_model.dart';
import 'ordonnance_provider.dart';

// Provider pour la requête de recherche
final searchQueryProvider = StateProvider<String>((ref) => '');

// Provider filtré pour les ordonnances basé sur la recherche
final filteredOrdonnancesProvider = Provider<List<OrdonnanceModel>>((ref) {
  final ordonnancesState = ref.watch(ordonnanceProvider);
  final searchQuery = ref.watch(searchQueryProvider).trim().toLowerCase();

  // Si la recherche est vide, retourner toutes les ordonnances
  if (searchQuery.isEmpty) {
    return ordonnancesState.items;
  }

  // Filtrer les ordonnances dont le nom du patient contient la chaîne de recherche
  return ordonnancesState.items.where((ordonnance) {
    // Les noms sont déjà déchiffrés dans le modèle OrdonnanceModel
    final patientName = ordonnance.patientName.toLowerCase();

    // Vérifier si le nom contient la chaîne de recherche
    return patientName.contains(searchQuery);
  }).toList();
});
