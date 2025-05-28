// lib/features/prescriptions/presentation/screens/ordonnance_list_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/navigation_service.dart';
import '../../../../core/utils/refresh_helper.dart';
import '../../../../shared/widgets/app_bar.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/shimmer_loading.dart';
import '../../models/filter_options.dart';
import '../../models/medicament_model.dart';
import '../../models/ordonnance_model.dart';
import '../../providers/medicament_provider.dart';
import '../../providers/ordonnance_filter_provider.dart';
import '../../providers/ordonnance_provider.dart';
import '../widgets/filter_bar.dart';
import '../widgets/filter_bar_skeleton.dart';
import '../widgets/ordonnance_list_item.dart';
import '../widgets/ordonnance_skeleton_item.dart';

class OrdonnanceListScreen extends ConsumerStatefulWidget {
  const OrdonnanceListScreen({super.key});

  @override
  ConsumerState<OrdonnanceListScreen> createState() => _OrdonnanceListScreenState();
}

class _OrdonnanceListScreenState extends ConsumerState<OrdonnanceListScreen> {
  final _navigationService = getIt<NavigationService>();
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Déclencher le chargement après le premier rendu
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerLoading();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final searchQuery = ref.read(searchQueryProvider);
    if (_searchController.text != searchQuery) {
      _searchController.text = searchQuery;
      _searchController.selection = TextSelection.fromPosition(
        TextPosition(offset: searchQuery.length),
      );
    }
  }

  // Méthode pour déclencher le chargement sans bloquer l'UI
  void _triggerLoading() {
    // Déclencher le chargement sans await pour afficher le skeleton immédiatement
    unawaited(ref.read(ordonnanceProvider.notifier).loadItems());

    // Charger les médicaments en arrière-plan
    unawaited(
      ref.read(allMedicamentsProvider.notifier).loadItems().then((_) {
        if (mounted) {
          // Forcer la mise à jour des comptages exacts une fois les médicaments chargés
          ref.refresh(exactOrdonnanceCountsProvider);
        }
      }),
    );
  }

  // Méthode pour le pull-to-refresh
  Future<void> _refreshData() async {
    await RefreshHelper.refreshData(
      context: context,
      ref: ref,
      onlineRefresh: () async {
        // Ici nous voulons attendre, donc pas de unawaited
        await ref.read(ordonnanceProvider.notifier).forceReload();
        await ref.read(allMedicamentsProvider.notifier).forceReload();
        ref.refresh(exactOrdonnanceCountsProvider);
      },
      offlineRefresh: () async {
        // Ici aussi nous voulons attendre
        await ref.read(ordonnanceProvider.notifier).loadItems();
        await ref.read(allMedicamentsProvider.notifier).loadItems();
        ref.refresh(exactOrdonnanceCountsProvider);
      },
    );
  }

  void _createNewOrdonnance() {
    _navigationService.navigateTo(context, '/ordonnances/new');
  }

  @override
  Widget build(BuildContext context) {
    final ordonnancesState = ref.watch(ordonnanceProvider);
    final isLoading = ordonnancesState.isLoading;

    // Éviter les calculs coûteux pendant le chargement
    final filteredOrdonnances =
        isLoading ? <OrdonnanceModel>[] : ref.watch(filteredOrdonnancesProvider);

    final allMedicaments = ref.watch(allMedicamentsProvider).items;
    final searchQuery = ref.watch(searchQueryProvider);
    final filterOption = ref.watch(filterOptionProvider);

    return Scaffold(
      appBar: const AppBarWidget(title: 'Ordonnances'),
      body: Column(
        children: [
          // Barre de recherche
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: AppTextField(
              controller: _searchController,
              label: 'Rechercher un patient',
              hint: 'Entrez le nom du patient',
              onChanged: (value) {
                ref.read(searchQueryProvider.notifier).state = value;
              },
              prefix: const Icon(Icons.search),
              suffix:
                  searchQuery.isNotEmpty
                      ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(searchQueryProvider.notifier).state = '';
                        },
                      )
                      : null,
            ),
          ),

          // Barre de filtrage - optimisée pour éviter les calculs pendant le chargement
          isLoading
              ? const ShimmerLoading(isLoading: true, child: FilterBarSkeleton())
              : const FilterBar(),

          // Contenu principal
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshData,
              child: _buildOrdonnanceList(
                isLoading,
                filteredOrdonnances,
                allMedicaments,
                searchQuery,
                filterOption,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewOrdonnance,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState(bool isSearching, bool isFiltering) {
    final filterOption = ref.watch(filterOptionProvider);

    String message;
    if (isSearching && isFiltering) {
      message =
          'Aucune ordonnance ne correspond à votre recherche et au filtre "${filterOption.label}"';
    } else if (isSearching) {
      message = 'Aucune ordonnance ne correspond à votre recherche';
    } else if (isFiltering) {
      message = 'Aucune ordonnance ne correspond au filtre "${filterOption.label}"';
    } else {
      message = 'Ajoutez votre première ordonnance en cliquant sur le bouton +';
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSearching || isFiltering ? Icons.search_off : Icons.description_outlined,
            size: 64,
            color: Colors.grey,
          ),
          const SizedBox(height: 16),
          const Text(
            'Aucune ordonnance',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          if (!isSearching && !isFiltering) ...[
            const SizedBox(height: 24),
            AppButton(
              text: 'Ajouter une ordonnance',
              onPressed: _createNewOrdonnance,
              icon: Icons.add,
              fullWidth: false,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOrdonnanceList(
    bool isLoading,
    List<OrdonnanceModel> ordonnances,
    List<MedicamentModel> allMedicaments,
    String searchQuery,
    FilterOption filterOption,
  ) {
    // Si en chargement, afficher les skeletons
    if (isLoading) {
      return ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: 5, // Nombre de skeletons à afficher
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          return const ShimmerLoading(isLoading: true, child: OrdonnanceSkeletonItem());
        },
      );
    }

    // Si aucune ordonnance après filtrage, afficher l'état vide
    if (ordonnances.isEmpty) {
      return _buildEmptyState(searchQuery.isNotEmpty, filterOption != FilterOption.all);
    }

    // Sinon, afficher la liste des ordonnances
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: ordonnances.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final ordonnance = ordonnances[index];

        // Trouver les médicaments pour cette ordonnance
        final medicaments = allMedicaments.where((m) => m.ordonnanceId == ordonnance.id).toList();

        // Trouver le statut d'expiration le plus critique
        ExpirationStatus? mostCriticalStatus;
        if (medicaments.isNotEmpty) {
          mostCriticalStatus = medicaments
              .map((m) => m.getExpirationStatus())
              .reduce((a, b) => a.index > b.index ? a : b);
        }

        return OrdonnanceListItem(
          ordonnance: ordonnance,
          medicamentCount: medicaments.length,
          expirationStatus: mostCriticalStatus,
          isSynced: ordonnance.isSynced,
          onTap: () => context.go('/ordonnances/${ordonnance.id}'),
        );
      },
    );
  }
}
