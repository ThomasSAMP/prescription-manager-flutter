// lib/features/prescriptions/presentation/screens/ordonnance_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/navigation_service.dart';
import '../../../../core/utils/refresh_helper.dart';
import '../../../../shared/widgets/app_bar.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../models/medicament_model.dart';
import '../../models/ordonnance_model.dart';
import '../../providers/medicament_provider.dart';
import '../../providers/ordonnance_provider.dart';
import '../../providers/search_provider.dart';
import '../widgets/ordonnance_list_item.dart';

class OrdonnanceListScreen extends ConsumerStatefulWidget {
  const OrdonnanceListScreen({super.key});

  @override
  ConsumerState<OrdonnanceListScreen> createState() => _OrdonnanceListScreenState();
}

class _OrdonnanceListScreenState extends ConsumerState<OrdonnanceListScreen> {
  final _navigationService = getIt<NavigationService>();
  final _authService = getIt<AuthService>();
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
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

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      // Charger plus d'ordonnances lorsqu'on approche de la fin de la liste
      ref.read(ordonnanceProvider.notifier).loadMore();
    }
  }

  Future<void> _loadData() async {
    try {
      // Charger les ordonnances et les médicaments
      await ref.read(ordonnanceProvider.notifier).loadItems();
      await ref.read(allMedicamentsProvider.notifier).loadItems();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur lors du chargement des données: $e')));
      }
    }
  }

  // Méthode pour le pull-to-refresh
  Future<void> _refreshData() async {
    await RefreshHelper.refreshData(
      context: context,
      ref: ref,
      onlineRefresh: () async {
        await ref.read(ordonnanceProvider.notifier).forceReload();
        await ref.read(allMedicamentsProvider.notifier).forceReload();
      },
      offlineRefresh: () async {
        await ref.read(ordonnanceProvider.notifier).loadItems();
        await ref.read(allMedicamentsProvider.notifier).loadItems();
      },
    );
  }

  void _createNewOrdonnance() {
    _navigationService.navigateTo(context, '/ordonnances/new');
  }

  @override
  Widget build(BuildContext context) {
    final ordonnancesState = ref.watch(ordonnanceProvider);
    final searchQuery = ref.watch(searchQueryProvider);
    final filteredOrdonnances = ref.watch(filteredOrdonnancesProvider);
    final allMedicaments = ref.watch(allMedicamentsProvider).items;

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
                          ref.read(searchQueryProvider.notifier).state = '';
                        },
                      )
                      : null,
            ),
          ),
          // Contenu principal
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshData,
              child:
                  ordonnancesState.isLoading && ordonnancesState.items.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : filteredOrdonnances.isEmpty
                      ? _buildEmptyState(searchQuery.isNotEmpty)
                      : _buildOrdonnanceList(
                        filteredOrdonnances,
                        allMedicaments,
                        ordonnancesState.isLoadingMore,
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

  Widget _buildEmptyState(bool isSearching) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSearching ? Icons.search_off : Icons.description_outlined,
            size: 64,
            color: Colors.grey,
          ),
          const SizedBox(height: 16),
          Text(
            isSearching ? 'Aucun résultat trouvé' : 'Aucune ordonnance',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            isSearching
                ? 'Essayez avec un autre terme de recherche'
                : 'Ajoutez votre première ordonnance en cliquant sur le bouton +',
            textAlign: TextAlign.center,
          ),
          if (!isSearching) ...[
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
    List<OrdonnanceModel> ordonnances,
    List<MedicamentModel> allMedicaments,
    bool isLoadingMore,
  ) {
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: ordonnances.length + (isLoadingMore ? 1 : 0),
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        // Si nous sommes à la fin de la liste et qu'il y a plus de données à charger
        if (index == ordonnances.length) {
          return const Center(
            child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()),
          );
        }

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
