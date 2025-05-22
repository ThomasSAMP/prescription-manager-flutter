// lib/features/prescriptions/presentation/screens/ordonnance_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/navigation_service.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
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
      // Mettre à jour l'état de synchronisation
      ref.read(syncStatusProvider.notifier).setSyncing();

      // Forcer le rechargement des ordonnances et des médicaments
      await ref.read(ordonnanceProvider.notifier).forceReload();
      await ref.read(allMedicamentsProvider.notifier).forceReload();

      // Marquer comme synchronisé
      ref.read(syncStatusProvider.notifier).setSynced();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Données synchronisées avec succès')));
      }
    } catch (e) {
      // Marquer l'erreur
      ref.read(syncStatusProvider.notifier).setError('Erreur: ${e.toString()}');

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur lors de la synchronisation: $e')));
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
    final canPop = context.canPop();

    return Scaffold(
      appBar: AppBarWidget(
        title: 'Ordonnances',
        showBackButton: canPop,
        leading: !canPop ? null : null,
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child:
            ordonnancesState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : ordonnancesState.items.isEmpty
                ? _buildEmptyState()
                : _buildOrdonnanceList(ordonnancesState.items, allMedicaments),
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

  Widget _buildOrdonnanceList(List ordonnances, List<MedicamentModel> allMedicaments) {
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
          isSynced: ordonnance.isSynced, // Passer l'état de synchronisation
          onTap: () => context.go('/ordonnances/${ordonnance.id}'),
        );
      },
    );
  }
}
