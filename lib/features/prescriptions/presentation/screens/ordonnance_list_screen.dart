// lib/features/prescriptions/presentation/screens/ordonnance_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/services/navigation_service.dart';
import '../../../../core/services/sync_service.dart';
import '../../../../shared/providers/sync_status_provider.dart';
import '../../../../shared/widgets/app_bar.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../models/medicament_model.dart';
import '../../providers/medicament_provider.dart';
import '../../providers/ordonnance_provider.dart';
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
    super.dispose();
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
    try {
      // Vérifier d'abord si nous sommes en ligne
      final connectivityService = getIt<ConnectivityService>();
      if (connectivityService.currentStatus == ConnectionStatus.offline) {
        // Si nous sommes hors ligne, recharger uniquement les données locales
        await ref.read(ordonnanceProvider.notifier).loadItems();
        await ref.read(allMedicamentsProvider.notifier).loadItems();

        // Afficher une notification de mode hors ligne
        ref.read(syncStatusProvider.notifier).setOffline();

        // Afficher un message à l'utilisateur
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Mode hors ligne : données locales chargées')),
          );
        }

        return; // Sortir de la méthode sans essayer de synchroniser
      }

      // Si nous sommes en ligne, procéder normalement
      await ref.read(ordonnanceProvider.notifier).forceReload();
      await ref.read(allMedicamentsProvider.notifier).forceReload();
      await getIt<SyncService>().syncAll();
    } catch (e) {
      // Gérer l'erreur
      if (!e.toString().contains('hors ligne')) {
        // Ne pas afficher d'erreur pour le mode hors ligne
        ref.read(syncStatusProvider.notifier).setError('Erreur: ${e.toString()}');

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Erreur lors de la synchronisation: $e')));
        }
      }
    }
  }

  void _createNewOrdonnance() {
    _navigationService.navigateTo(context, '/ordonnances/new');
  }

  @override
  Widget build(BuildContext context) {
    final ordonnancesState = ref.watch(ordonnanceProvider);
    final allMedicaments = ref.watch(allMedicamentsProvider).items;

    return Scaffold(
      appBar: const AppBarWidget(title: 'Ordonnances'),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child:
            ordonnancesState.isLoading && ordonnancesState.items.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ordonnancesState.items.isEmpty
                ? _buildEmptyState()
                : _buildOrdonnanceList(ordonnancesState, allMedicaments),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewOrdonnance,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.description_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'Aucune ordonnance',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Ajoutez votre première ordonnance en cliquant sur le bouton +',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          AppButton(
            text: 'Ajouter une ordonnance',
            onPressed: _createNewOrdonnance,
            icon: Icons.add,
            fullWidth: false,
          ),
        ],
      ),
    );
  }

  Widget _buildOrdonnanceList(
    OrdonnanceState ordonnancesState,
    List<MedicamentModel> allMedicaments,
  ) {
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: ordonnancesState.items.length + (ordonnancesState.isLoadingMore ? 1 : 0),
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        // Si nous sommes à la fin de la liste et qu'il y a plus de données à charger
        if (index == ordonnancesState.items.length) {
          return const Center(
            child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()),
          );
        }

        final ordonnance = ordonnancesState.items[index];

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
